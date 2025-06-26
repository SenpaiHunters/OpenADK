//
//  FaviconManager.swift
//  OpenADK
//
//  Created by Kami on 18/06/2025.
//

import Foundation
import Observation
import SwiftUI
import WebKit

// MARK: - NSImage Extension

extension NSImage {
    /// Validates that the NSImage is valid and has proper dimensions
    var isValid: Bool {
        size.width > 0 && size.height > 0 && !representations.isEmpty
    }
}

// MARK: - FaviconCacheEntry

/// Represents a cached favicon entry with metadata
struct FaviconCacheEntry: Codable {
    let imageData: Data
    let cachedDate: Date
    let originalURL: String
    let accessCount: Int
    let lastAccessDate: Date

    /// Checks if the cache entry has expired based on TTL
    var isExpired: Bool {
        Date().timeIntervalSince(cachedDate) > 864_000 // 10 days in seconds
    }

    /// Creates a new cache entry with incremented access count
    func withIncrementedAccess() -> FaviconCacheEntry {
        FaviconCacheEntry(
            imageData: imageData,
            cachedDate: cachedDate,
            originalURL: originalURL,
            accessCount: accessCount + 1,
            lastAccessDate: Date()
        )
    }
}

// MARK: - FaviconManager

/// Manages favicon fetching, caching
@Observable
public class FaviconManager {
    public static let shared = FaviconManager()

    // MARK: - Properties

    private let cacheDirectory: URL
    private let maxCacheSize = 104_857_600 // 100MB
    private let cacheTTL: TimeInterval = 864_000 // 10 days

    /// LRU-based memory cache with access tracking
    private var memoryCache: [String: (image: NSImage, lastAccess: Date)] = [:]
    private let maxMemoryCacheSize = 75 // Increased for better hit rate

    /// Priority queue for intelligent preloading
    private var preloadURLQueue: Set<String> = []
    private var activePreloads: Set<String> = []
    private let maxConcurrentPreloads = 3

    private let cacheQueue = DispatchQueue(label: "com.openadk.favicon.cache", qos: .utility)
    private let preloadDispatchQueue = DispatchQueue(label: "com.openadk.favicon.preload", qos: .background)

    // MARK: - Initialization

    /// Initializes the FaviconManager
    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("OpenADK/FaviconCache")

        createCacheDirectoryIfNeeded()
        cleanExpiredCache()
    }

    // MARK: - Public Methods

    /// Fetches a favicon for the given URL with intelligent caching and preloading
    /// - Parameters:
    ///   - url: The URL to fetch favicon for
    ///   - completion: Completion handler with the fetched image
    public func fetchFavicon(for url: String, completion: @escaping (NSImage?) -> ()) {
        let cacheKey = generateCacheKey(from: url)

        // Check memory cache with LRU update
        if let cached = memoryCache[cacheKey] {
            memoryCache[cacheKey] = (cached.image, Date())

            // Check if this was a preloaded favicon
            if activePreloads.contains(cacheKey) {
                activePreloads.remove(cacheKey)
            }

            // print("🚀 [FaviconManager] Memory cache hit for: \(url)")
            DispatchQueue.main.async { completion(cached.image) }

            return
        }

        cacheQueue.async { [weak self] in
            if let cachedEntry = self?.loadFromDiskCache(cacheKey: cacheKey), !cachedEntry.isExpired,
               let image = NSImage(data: cachedEntry.imageData) {
                // Update access statistics
                let updatedEntry = cachedEntry.withIncrementedAccess()
                self?.updateDiskCache(entry: updatedEntry, cacheKey: cacheKey)

                // print("📁 [FaviconManager] Disk cache hit for: \(url) (access count: \(updatedEntry.accessCount))")

                DispatchQueue.main.async {
                    self?.memoryCache[cacheKey] = (image, Date())
                    self?.optimizeMemoryCache()
                    completion(image)
                }

                return
            } else if let cachedEntry = self?.loadFromDiskCache(cacheKey: cacheKey), cachedEntry.isExpired {
                // print("⏰ [FaviconManager] Expired cache for: \(url), refetching")
                self?.removeFromDiskCache(cacheKey: cacheKey)
            }

            self?.fetchFromNetwork(url: url, cacheKey: cacheKey, completion: completion)
        }
    }

    /// Extracts favicon from HTML with enhanced parsing and fallback strategies
    /// - Parameters:
    ///   - webView: The WKWebView to extract favicon from
    ///   - baseURL: Base URL for resolving relative paths
    ///   - completion: Completion handler with the extracted favicon
    public func fetchFaviconFromHTML(webView: WKWebView, baseURL: URL, completion: @escaping (NSImage?) -> ()) {
        let faviconScript = """
        (() => {
            const links = [];
            const selectors = [
                'link[rel="icon"]',
                'link[rel="shortcut icon"]', 
                'link[rel="apple-touch-icon"]',
                'link[rel="apple-touch-icon-precomposed"]',
                'link[rel="icon" i]',
                'link[rel="mask-icon"]',
                'link[rel="fluid-icon"]'
            ];

            for (const selector of selectors) {
                const elements = document.querySelectorAll(selector);
                for (const element of elements) {
                    const href = element.getAttribute('href');
                    if (href) {
                        links.push({
                            href: href,
                            rel: element.getAttribute('rel'),
                            sizes: element.getAttribute('sizes'),
                            type: element.getAttribute('type'),
                            color: element.getAttribute('color')
                        });
                    }
                }
            }
            return links;
        })();
        """

        webView.evaluateJavaScript(faviconScript) { [weak self] result, error in
            if let error {
                // print("❌ [FaviconManager] JavaScript error: \(error)")
                self?.fallbackToTraditionalFavicon(baseURL: baseURL, completion: completion)
                return
            }

            guard let links = result as? [[String: Any]], !links.isEmpty else {
                self?.fallbackToTraditionalFavicon(baseURL: baseURL, completion: completion)
                return
            }

            let sortedLinks = self?.prioritizeFaviconLinks(links) ?? links

            if let bestLink = sortedLinks.first, let href = bestLink["href"] as? String {
                let faviconURL = self?.resolveURL(href: href, baseURL: baseURL) ?? href
                // print("🔍 [FaviconManager] Best favicon from HTML: \(faviconURL)")

                self?.fetchFavicon(for: faviconURL) { image in
                    DispatchQueue.main.async {
                        if let image {
                            completion(image)
                        } else {
                            self?.tryRemainingFaviconLinks(
                                Array(sortedLinks.dropFirst()),
                                baseURL: baseURL,
                                completion: completion
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    /// Creates cache directory if it doesn't exist
    private func createCacheDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                // print("📁 [FaviconManager] Created cache directory at: \(cacheDirectory.path)")
            } catch {
                // print("❌ [FaviconManager] Failed to create cache directory: \(error)")
            }
        }
    }

    /// Generates a cache key from URL using efficient hashing
    /// - Parameter url: URL to generate cache key for
    /// - Returns: Cache key string
    private func generateCacheKey(from url: String) -> String {
        url.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-") ?? String(url.hashValue)
    }

    /// Fetches favicon from network with enhanced error handling
    /// - Parameters:
    ///   - url: URL to fetch from
    ///   - cacheKey: Cache key for storage
    ///   - completion: Completion handler
    private func fetchFromNetwork(url: String, cacheKey: String, completion: @escaping (NSImage?) -> ()) {
        guard let faviconURL = URL(string: url) else {
            // print("❌ [FaviconManager] Invalid favicon URL: \(url)")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // print("🌐 [FaviconManager] Fetching from network: \(url)")
        fetchSingleFavicon(from: faviconURL, originalURL: url, cacheKey: cacheKey, completion: completion)
    }

    /// Fetches a single favicon with comprehensive error handling
    /// - Parameters:
    ///   - url: URL to fetch from
    ///   - originalURL: Original URL for fallback
    ///   - cacheKey: Cache key for storage
    ///   - completion: Completion handler
    private func fetchSingleFavicon(
        from url: URL,
        originalURL: String,
        cacheKey: String,
        completion: @escaping (NSImage?) -> ()
    ) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                // print("❌ [FaviconManager] Network error: \(error.localizedDescription)")
                self?.tryFaviconFallback(originalURL: originalURL, cacheKey: cacheKey, completion: completion)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                // print("❌ [FaviconManager] HTTP error \(httpResponse.statusCode) for: \(url)")
                self?.tryFaviconFallback(originalURL: originalURL, cacheKey: cacheKey, completion: completion)
                return
            }

            guard let data, !data.isEmpty, let image = NSImage(data: data), image.isValid else {
                // print("❌ [FaviconManager] Invalid image data for: \(url)")
                self?.tryFaviconFallback(originalURL: originalURL, cacheKey: cacheKey, completion: completion)
                return
            }

            // print("✅ [FaviconManager] Successfully fetched: \(url)")
            self?.saveToDiskCache(data: data, cacheKey: cacheKey, originalURL: originalURL)

            DispatchQueue.main.async {
                self?.memoryCache[cacheKey] = (image, Date())
                self?.optimizeMemoryCache()
                completion(image)
            }
        }.resume()
    }

    /// Enhanced fallback strategy with multiple providers
    /// - Parameters:
    ///   - originalURL: Original URL that failed
    ///   - cacheKey: Cache key for storage
    ///   - completion: Completion handler
    private func tryFaviconFallback(originalURL: String, cacheKey: String, completion: @escaping (NSImage?) -> ()) {
        guard let url = URL(string: originalURL), let host = url.host else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // print("🔄 [FaviconManager] Trying fallback methods for: \(host)")

        let fallbackURLs = [
            "https://\(host)/apple-touch-icon.png",
            "https://\(host)/apple-touch-icon-precomposed.png",
            "https://\(host)/apple-touch-icon-120x120.png",
            "https://www.google.com/s2/favicons?domain=\(host)&sz=32",
            "https://icons.duckduckgo.com/ip3/\(host).ico",
            "https://favicons.githubusercontent.com/\(host)",
            "https://\(host)/favicon.png"
        ]

        tryFallbackURLs(
            fallbackURLs: fallbackURLs,
            index: 0,
            originalURL: originalURL,
            cacheKey: cacheKey,
            completion: completion
        )
    }

    /// Tries fallback URLs sequentially with improved error handling
    /// - Parameters:
    ///   - fallbackURLs: Array of fallback URLs to try
    ///   - index: Current index in the array
    ///   - originalURL: Original URL for context
    ///   - cacheKey: Cache key for storage
    ///   - completion: Completion handler
    private func tryFallbackURLs(
        fallbackURLs: [String],
        index: Int,
        originalURL: String,
        cacheKey: String,
        completion: @escaping (NSImage?) -> ()
    ) {
        guard index < fallbackURLs.count else {
            // print("⚠️ [FaviconManager] All fallbacks failed, generating default favicon")
            generateDefaultFavicon(for: originalURL, completion: completion)
            return
        }

        guard let fallbackURL = URL(string: fallbackURLs[index]) else {
            // print("❌ [FaviconManager] Invalid fallback URL: \(fallbackURLs[index])")
            tryFallbackURLs(
                fallbackURLs: fallbackURLs,
                index: index + 1,
                originalURL: originalURL,
                cacheKey: cacheKey,
                completion: completion
            )
            return
        }

        // print("🔍 [FaviconManager] Trying fallback \(index + 1)/\(fallbackURLs.count): \(fallbackURL)")

        var request = URLRequest(url: fallbackURL)
        request.timeoutInterval = 8.0

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error {
                // print("❌ [FaviconManager] Fallback \(index + 1) failed: \(error.localizedDescription)")
                self?.tryFallbackURLs(
                    fallbackURLs: fallbackURLs,
                    index: index + 1,
                    originalURL: originalURL,
                    cacheKey: cacheKey,
                    completion: completion
                )
                return
            }

            if let data, let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
               let image = NSImage(data: data), image.isValid {
                // print("✅ [FaviconManager] Fallback success from: \(fallbackURL)")
                self?.saveToDiskCache(data: data, cacheKey: cacheKey, originalURL: originalURL)

                DispatchQueue.main.async {
                    self?.memoryCache[cacheKey] = (image, Date())
                    self?.optimizeMemoryCache()
                    completion(image)
                }
                return
            }

            // print("❌ [FaviconManager] Fallback \(index + 1) invalid data")
            self?.tryFallbackURLs(
                fallbackURLs: fallbackURLs,
                index: index + 1,
                originalURL: originalURL,
                cacheKey: cacheKey,
                completion: completion
            )
        }.resume()
    }

    /// Generates a default favicon with improved visual design
    /// - Parameters:
    ///   - url: URL to generate favicon for
    ///   - completion: Completion handler
    private func generateDefaultFavicon(for url: String, completion: @escaping (NSImage?) -> ()) {
        guard let domain = URL(string: url)?.host else {
            // print("❌ [FaviconManager] Could not extract domain from URL: \(url)")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let firstLetter = String(domain.prefix(1).uppercased())
        let image = createDefaultFaviconImage(with: firstLetter, domain: domain)

        // print("🎨 [FaviconManager] Generated default favicon for \(domain)")
        DispatchQueue.main.async { completion(image) }
    }

    /// Creates a default favicon image with domain-based color
    /// - Parameters:
    ///   - letter: Letter to display
    ///   - domain: Domain for color generation
    /// - Returns: Generated NSImage
    private func createDefaultFaviconImage(with letter: String, domain: String) -> NSImage? {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)

        image.lockFocus()

        // Generate color based on domain hash for consistency
        let domainHash = abs(domain.hashValue)
        let hue = Double(domainHash % 360) / 360.0
        let backgroundColor = NSColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1.0)

        backgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white
        ]

        let attributedString = NSAttributedString(string: letter, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        attributedString.draw(in: textRect)
        image.unlockFocus()

        return image
    }

    /// Saves favicon to disk cache with enhanced metadata
    /// - Parameters:
    ///   - data: Image data to save
    ///   - cacheKey: Cache key for storage
    ///   - originalURL: Original URL for metadata
    private func saveToDiskCache(data: Data, cacheKey: String, originalURL: String) {
        let cacheEntry = FaviconCacheEntry(
            imageData: data,
            cachedDate: Date(),
            originalURL: originalURL,
            accessCount: 1,
            lastAccessDate: Date()
        )

        do {
            let encodedData = try JSONEncoder().encode(cacheEntry)
            let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
            try encodedData.write(to: fileURL)
            // print("💾 [FaviconManager] Saved to disk cache: \(originalURL)")
        } catch {
            // print("❌ [FaviconManager] Failed to save to disk cache: \(error)")
        }
    }

    /// Updates existing disk cache entry with new access data
    /// - Parameters:
    ///   - entry: Updated cache entry
    ///   - cacheKey: Cache key for storage
    private func updateDiskCache(entry: FaviconCacheEntry, cacheKey: String) {
        do {
            let encodedData = try JSONEncoder().encode(entry)
            let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
            try encodedData.write(to: fileURL)
        } catch {
            // print("❌ [FaviconManager] Failed to update disk cache: \(error)")
        }
    }

    /// Loads favicon from disk cache
    /// - Parameter cacheKey: Cache key to load
    /// - Returns: Cached entry if found
    private func loadFromDiskCache(cacheKey: String) -> FaviconCacheEntry? {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(FaviconCacheEntry.self, from: data)
        } catch {
            return nil
        }
    }

    /// Removes favicon from disk cache
    /// - Parameter cacheKey: Cache key to remove
    private func removeFromDiskCache(cacheKey: String) {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Optimizes memory cache using LRU eviction strategy
    private func optimizeMemoryCache() {
        if memoryCache.count > maxMemoryCacheSize {
            let sortedByAccess = memoryCache.sorted { $0.value.lastAccess < $1.value.lastAccess }
            let keysToRemove = sortedByAccess.prefix(memoryCache.count - maxMemoryCacheSize).map(\.key)
            keysToRemove.forEach { memoryCache.removeValue(forKey: $0) }
            // print("🧹 [FaviconManager] Evicted \(keysToRemove.count) items from memory cache")
        }
    }

    /// Cleans expired cache entries
    private func cleanExpiredCache() {
        cacheQueue.async { [weak self] in
            guard let self else { return }

            do {
                let cacheFiles = try FileManager.default.contentsOfDirectory(
                    at: cacheDirectory,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
                )
                var expiredCount = 0
                var totalSize = 0

                // Sort by access frequency and age for intelligent cleanup
                var cacheEntries: [(url: URL, entry: FaviconCacheEntry, size: Int)] = []

                for file in cacheFiles {
                    let cacheKey = file.lastPathComponent
                    if let cacheEntry = loadFromDiskCache(cacheKey: cacheKey) {
                        let resourceValues = try? file.resourceValues(forKeys: [.fileSizeKey])
                        let size = resourceValues?.fileSize ?? 0
                        totalSize += size

                        if cacheEntry.isExpired {
                            try FileManager.default.removeItem(at: file)
                            expiredCount += 1
                        } else {
                            cacheEntries.append((file, cacheEntry, size))
                        }
                    }
                }

                // If cache is too large, remove least accessed items
                if totalSize > maxCacheSize {
                    let sortedEntries = cacheEntries.sorted {
                        ($0.entry.accessCount, $0.entry.lastAccessDate) < (
                            $1.entry.accessCount,
                            $1.entry.lastAccessDate
                        )
                    }

                    var currentSize = totalSize
                    var removedCount = 0

                    for (file, _, size) in sortedEntries {
                        if currentSize <= maxCacheSize * 3 / 4 { break } // Keep 75% of max size

                        try? FileManager.default.removeItem(at: file)
                        currentSize -= size
                        removedCount += 1
                    }

                    if removedCount > 0 {
                        // print("🗂️ [FaviconManager] Removed \(removedCount) least-used items to optimize disk usage")
                    }
                }

                if expiredCount > 0 {
                    // print("🧹 [FaviconManager] Cleaned \(expiredCount) expired favicon(s) from cache")
                }
            } catch {
                // print("❌ [FaviconManager] Failed to clean expired cache: \(error)")
            }
        }
    }

    /// Prioritizes favicon links based on quality and compatibility
    /// - Parameter links: Array of favicon link dictionaries
    /// - Returns: Sorted array of favicon links
    private func prioritizeFaviconLinks(_ links: [[String: Any]]) -> [[String: Any]] {
        links.sorted { link1, link2 in
            let type1 = link1["type"] as? String ?? ""
            let type2 = link2["type"] as? String ?? ""
            let sizes1 = link1["sizes"] as? String ?? ""
            let sizes2 = link2["sizes"] as? String ?? ""
            let rel1 = link1["rel"] as? String ?? ""
            let rel2 = link2["rel"] as? String ?? ""

            // Prefer SVG for scalability
            if type1.contains("svg"), !type2.contains("svg") { return true }
            if !type1.contains("svg"), type2.contains("svg") { return false }

            // Prefer PNG over ICO
            if type1.contains("png"), !type2.contains("png") { return true }
            if !type1.contains("png"), type2.contains("png") { return false }

            // Prefer larger sizes (32x32 or higher)
            let size1 = extractSizeFromString(sizes1)
            let size2 = extractSizeFromString(sizes2)
            if size1 >= 32, size2 < 32 { return true }
            if size1 < 32, size2 >= 32 { return false }
            if size1 != size2 { return size1 > size2 }

            // Prefer apple-touch-icon for better quality
            if rel1.contains("apple-touch"), !rel2.contains("apple-touch") { return true }

            return false
        }
    }

    /// Tries remaining favicon links from HTML parsing
    /// - Parameters:
    ///   - remainingLinks: Remaining links to try
    ///   - baseURL: Base URL for resolution
    ///   - completion: Completion handler
    private func tryRemainingFaviconLinks(
        _ remainingLinks: [[String: Any]],
        baseURL: URL,
        completion: @escaping (NSImage?) -> ()
    ) {
        guard let nextLink = remainingLinks.first, let href = nextLink["href"] as? String else {
            fallbackToTraditionalFavicon(baseURL: baseURL, completion: completion)
            return
        }

        let faviconURL = resolveURL(href: href, baseURL: baseURL)
        // print("🔍 [FaviconManager] Trying additional favicon from HTML: \(faviconURL)")

        fetchFavicon(for: faviconURL) { [weak self] image in
            DispatchQueue.main.async {
                if let image {
                    completion(image)
                } else {
                    self?.tryRemainingFaviconLinks(
                        Array(remainingLinks.dropFirst()),
                        baseURL: baseURL,
                        completion: completion
                    )
                }
            }
        }
    }

    /// Falls back to traditional favicon.ico approach
    /// - Parameters:
    ///   - baseURL: Base URL to construct favicon.ico path
    ///   - completion: Completion handler
    private func fallbackToTraditionalFavicon(baseURL: URL, completion: @escaping (NSImage?) -> ()) {
        guard let host = baseURL.host else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let faviconURL = "https://\(host)/favicon.ico"
        // print("🔄 [FaviconManager] Falling back to traditional favicon: \(faviconURL)")

        fetchFavicon(for: faviconURL) { image in
            DispatchQueue.main.async { completion(image) }
        }
    }

    /// Resolves relative URLs to absolute URLs
    /// - Parameters:
    ///   - href: The href attribute value
    ///   - baseURL: Base URL for resolution
    /// - Returns: Resolved absolute URL string
    private func resolveURL(href: String, baseURL: URL) -> String {
        if href.hasPrefix("http://") || href.hasPrefix("https://") {
            return href
        }

        if href.hasPrefix("//") {
            return "\(baseURL.scheme ?? "https"):\(href)"
        }

        if href.hasPrefix("/") {
            return "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(href)"
        }

        let baseURLString = baseURL.absoluteString
        return baseURLString.hasSuffix("/") ? "\(baseURLString)\(href)" : "\(baseURLString)/\(href)"
    }

    /// Extracts numeric size from size strings like "32x32", "any", etc.
    /// - Parameter sizeString: Size string to parse
    /// - Returns: Extracted size as integer
    private func extractSizeFromString(_ sizeString: String) -> Int {
        let pattern = #"(\d+)x?\d*"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(
               in: sizeString,
               options: [],
               range: NSRange(sizeString.startIndex..., in: sizeString)
           ),
           let range = Range(match.range(at: 1), in: sizeString) {
            return Int(String(sizeString[range])) ?? 0
        }
        return 0
    }
}
