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

struct FaviconCacheEntry: Codable {
    let imageData: Data
    let cachedDate: Date
    let originalURL: String

    var isExpired: Bool {
        let tenDaysInSeconds: TimeInterval = 10 * 24 * 60 * 60 // 10 days
        return Date().timeIntervalSince(cachedDate) > tenDaysInSeconds
    }
}

// MARK: - FaviconManager

@Observable
public class FaviconManager {
    // MARK: - Properties

    private let cacheDirectory: URL
    private let maxCacheSize = 100 * 1024 * 1024 // 100MB
    private let cacheTTL: TimeInterval = 10 * 24 * 60 * 60 // 10 days

    // In-memory cache for quick access
    private var memoryCache: [String: NSImage] = [:]
    private let maxMemoryCacheSize = 50 // Max number of images in memory

    // Cache queue for thread safety
    private let cacheQueue = DispatchQueue(label: "com.alto.favicon.cache", qos: .utility)

    // MARK: - Initialization

    public init() {
        // Create cache directory in app support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        cacheDirectory = appSupport.appendingPathComponent("Alto/FaviconCache")

        createCacheDirectoryIfNeeded()
        cleanExpiredCache()
        preloadCommonFavicons()
    }

    // MARK: - Public Methods

    /// Fetches a favicon for the given URL, using cache when available
    public func fetchFavicon(for url: String, completion: @escaping (NSImage?) -> ()) {
        let cacheKey = generateCacheKey(from: url)

        // First check memory cache
        if let cachedImage = memoryCache[cacheKey] {
            print("🚀 [FaviconManager] Loaded favicon from memory cache for: \(url)")
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }

        // Check disk cache
        cacheQueue.async { [weak self] in
            if let cachedEntry = self?.loadFromDiskCache(cacheKey: cacheKey) {
                if !cachedEntry.isExpired {
                    if let image = NSImage(data: cachedEntry.imageData) {
                        print(
                            "📁 [FaviconManager] Loaded favicon from disk cache for: \(url) (cached on: \(cachedEntry.cachedDate))"
                        )

                        // Store in memory cache for faster future access
                        DispatchQueue.main.async {
                            self?.memoryCache[cacheKey] = image
                            self?.limitMemoryCache()
                            completion(image)
                        }
                        return
                    }
                } else {
                    print("⏰ [FaviconManager] Cached favicon expired for: \(url), will fetch new one")
                    // Remove expired entry
                    self?.removeFromDiskCache(cacheKey: cacheKey)
                }
            }

            // Cache miss - fetch from network
            self?.fetchFromNetwork(url: url, cacheKey: cacheKey, completion: completion)
        }
    }

    /// Extracts favicon from HTML and fetches it intelligently
    public func fetchFaviconFromHTML(webView: WKWebView, baseURL: URL, completion: @escaping (NSImage?) -> ()) {
        let faviconScript = """
        (() => {
            const links = [];

            // Check for various favicon link tags
            const selectors = [
                'link[rel="icon"]',
                'link[rel="shortcut icon"]', 
                'link[rel="apple-touch-icon"]',
                'link[rel="apple-touch-icon-precomposed"]',
                'link[rel="icon" i]' // case insensitive
            ];

            for (const selector of selectors) {
                const elements = document.querySelectorAll(selector);
                for (const element of elements) {
                    const href = element.getAttribute('href');
                    const sizes = element.getAttribute('sizes');
                    const type = element.getAttribute('type');
                    if (href) {
                        links.push({
                            href: href,
                            rel: element.getAttribute('rel'),
                            sizes: sizes,
                            type: type
                        });
                    }
                }
            }

            return links;
        })();
        """

        webView.evaluateJavaScript(faviconScript) { [weak self] result, error in
            if let error {
                print("JavaScript error finding favicon: \(error)")
                // Fallback to traditional method
                self?.fallbackToTraditionalFavicon(baseURL: baseURL, completion: completion)
                return
            }

            guard let links = result as? [[String: Any]], !links.isEmpty else {
                // No favicon links found, try traditional method
                self?.fallbackToTraditionalFavicon(baseURL: baseURL, completion: completion)
                return
            }

            // Sort favicon links by preference (prioritize better formats and sizes)
            let sortedLinks = links.sorted { link1, link2 in
                let type1 = link1["type"] as? String ?? ""
                let type2 = link2["type"] as? String ?? ""
                let sizes1 = link1["sizes"] as? String ?? ""
                let sizes2 = link2["sizes"] as? String ?? ""

                // Prefer PNG over ICO
                if type1.contains("png"), !type2.contains("png") { return true }
                if !type1.contains("png"), type2.contains("png") { return false }

                // Prefer larger sizes
                let size1 = self?.extractSizeFromString(sizes1) ?? 0
                let size2 = self?.extractSizeFromString(sizes2) ?? 0
                if size1 != size2 { return size1 > size2 }

                // Prefer apple-touch-icon over regular icon
                let rel1 = link1["rel"] as? String ?? ""
                let rel2 = link2["rel"] as? String ?? ""
                if rel1.contains("apple-touch"), !rel2.contains("apple-touch") { return true }

                return false
            }

            // Try the best favicon link first
            if let bestLink = sortedLinks.first,
               let href = bestLink["href"] as? String {
                let faviconURL = self?.resolveURL(href: href, baseURL: baseURL) ?? href
                print("🔍 [FaviconManager] Found favicon in HTML: \(faviconURL)")

                self?.fetchFavicon(for: faviconURL) { image in
                    DispatchQueue.main.async {
                        if let image {
                            completion(image)
                        } else {
                            // If the first one fails, try others or fallback
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

    /// Clears all cached favicons
    public func clearCache() {
        cacheQueue.async { [weak self] in
            guard let self else { return }

            // Clear memory cache
            DispatchQueue.main.async {
                self.memoryCache.removeAll()
            }

            // Clear disk cache
            do {
                let cacheFiles = try FileManager.default.contentsOfDirectory(
                    at: cacheDirectory,
                    includingPropertiesForKeys: nil
                )
                for file in cacheFiles {
                    try FileManager.default.removeItem(at: file)
                }
                print("🗑️ [FaviconManager] Cache cleared successfully")
            } catch {
                print("❌ [FaviconManager] Failed to clear cache: \(error)")
            }
        }
    }

    /// Returns cache statistics
    public func getCacheStats() -> (diskCount: Int, memoryCount: Int, totalSizeBytes: Int) {
        var diskCount = 0
        var totalSize = 0

        do {
            let cacheFiles = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            )
            diskCount = cacheFiles.count

            for file in cacheFiles {
                let resourceValues = try file.resourceValues(forKeys: [.fileSizeKey])
                totalSize += resourceValues.fileSize ?? 0
            }
        } catch {
            print("❌ [FaviconManager] Failed to get cache stats: \(error)")
        }

        return (diskCount: diskCount, memoryCount: memoryCache.count, totalSizeBytes: totalSize)
    }

    // MARK: - Private Methods

    private func createCacheDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: cacheDirectory,
                    withIntermediateDirectories: true
                )
                print("📁 [FaviconManager] Created cache directory at: \(cacheDirectory.path)")
            } catch {
                print("❌ [FaviconManager] Failed to create cache directory: \(error)")
            }
        }
    }

    private func generateCacheKey(from url: String) -> String {
        url.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-") ?? url.hash.description
    }

    private func fetchFromNetwork(url: String, cacheKey: String, completion: @escaping (NSImage?) -> ()) {
        guard let faviconURL = URL(string: url) else {
            print("❌ [FaviconManager] Invalid favicon URL: \(url)")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        print("🌐 [FaviconManager] Fetching favicon from network: \(url)")

        // First, try the original favicon URL
        fetchSingleFavicon(from: faviconURL, originalURL: url, cacheKey: cacheKey, completion: completion)
    }

    private func fetchSingleFavicon(
        from url: URL,
        originalURL: String,
        cacheKey: String,
        completion: @escaping (NSImage?) -> ()
    ) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let error {
                print("❌ [FaviconManager] Network error fetching favicon: \(error.localizedDescription)")
                self?.tryFaviconFallback(originalURL: originalURL, cacheKey: cacheKey, completion: completion)
                return
            }

            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("❌ [FaviconManager] HTTP error \(httpResponse.statusCode) for: \(url)")
                self?.tryFaviconFallback(originalURL: originalURL, cacheKey: cacheKey, completion: completion)
                return
            }

            guard let data, !data.isEmpty else {
                print("❌ [FaviconManager] Empty data for: \(url)")
                self?.tryFaviconFallback(originalURL: originalURL, cacheKey: cacheKey, completion: completion)
                return
            }

            // Validate that the data is actually an image
            guard let image = NSImage(data: data), image.isValid else {
                print("❌ [FaviconManager] Invalid image data for: \(url)")
                self?.tryFaviconFallback(originalURL: originalURL, cacheKey: cacheKey, completion: completion)
                return
            }

            print("✅ [FaviconManager] Successfully fetched favicon for: \(url)")

            // Cache the image
            self?.saveToDiskCache(data: data, cacheKey: cacheKey, originalURL: originalURL)

            // Store in memory cache
            DispatchQueue.main.async {
                self?.memoryCache[cacheKey] = image
                self?.limitMemoryCache()
                completion(image)
            }
        }.resume()
    }

    private func tryFaviconFallback(originalURL: String, cacheKey: String, completion: @escaping (NSImage?) -> ()) {
        guard let url = URL(string: originalURL),
              let host = url.host else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        print("🔄 [FaviconManager] Trying fallback methods for: \(host)")

        // Fallback URLs to try
        let fallbackURLs = [
            "https://\(host)/apple-touch-icon.png",
            "https://\(host)/apple-touch-icon-precomposed.png",
            "https://www.google.com/s2/favicons?domain=\(host)",
            "https://icons.duckduckgo.com/ip3/\(host).ico"
        ]

        tryFallbackURLs(
            fallbackURLs: fallbackURLs,
            index: 0,
            originalURL: originalURL,
            cacheKey: cacheKey,
            completion: completion
        )
    }

    private func tryFallbackURLs(
        fallbackURLs: [String],
        index: Int,
        originalURL: String,
        cacheKey: String,
        completion: @escaping (NSImage?) -> ()
    ) {
        guard index < fallbackURLs.count else {
            // All fallbacks failed, try to generate a default favicon
            print("⚠️ [FaviconManager] All fallback methods failed, generating default favicon")
            generateDefaultFavicon(for: originalURL, completion: completion)
            return
        }

        guard let fallbackURL = URL(string: fallbackURLs[index]) else {
            // Skip invalid URL and try next one
            print("❌ [FaviconManager] Invalid fallback URL: \(fallbackURLs[index])")
            tryFallbackURLs(
                fallbackURLs: fallbackURLs,
                index: index + 1,
                originalURL: originalURL,
                cacheKey: cacheKey,
                completion: completion
            )
            return
        }

        print("🔍 [FaviconManager] Trying fallback \(index + 1)/\(fallbackURLs.count): \(fallbackURL)")

        URLSession.shared.dataTask(with: fallbackURL) { [weak self] data, response, error in
            if let error {
                print("❌ [FaviconManager] Fallback \(index + 1) failed: \(error.localizedDescription)")
                self?.tryFallbackURLs(
                    fallbackURLs: fallbackURLs,
                    index: index + 1,
                    originalURL: originalURL,
                    cacheKey: cacheKey,
                    completion: completion
                )
                return
            }

            if let data,
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let image = NSImage(data: data),
               image.isValid {
                print("✅ [FaviconManager] Successfully fetched fallback favicon from: \(fallbackURL)")

                // Cache the fallback image
                self?.saveToDiskCache(data: data, cacheKey: cacheKey, originalURL: originalURL)

                DispatchQueue.main.async {
                    self?.memoryCache[cacheKey] = image
                    self?.limitMemoryCache()
                    completion(image)
                }
                return
            }

            // This fallback failed, try the next one
            print("❌ [FaviconManager] Fallback \(index + 1) invalid or empty data")
            self?.tryFallbackURLs(
                fallbackURLs: fallbackURLs,
                index: index + 1,
                originalURL: originalURL,
                cacheKey: cacheKey,
                completion: completion
            )
        }.resume()
    }

    private func generateDefaultFavicon(for url: String, completion: @escaping (NSImage?) -> ()) {
        guard let domain = URL(string: url)?.host else {
            print("❌ [FaviconManager] Could not extract domain from URL: \(url)")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // Generate a simple default favicon with the first letter of the domain
        let firstLetter = String(domain.prefix(1).uppercased())
        let image = createDefaultFaviconImage(with: firstLetter)

        print("🎨 [FaviconManager] Generated default favicon for \(domain) with letter: \(firstLetter)")

        DispatchQueue.main.async {
            completion(image)
        }
    }

    private func createDefaultFaviconImage(with letter: String) -> NSImage? {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size)

        image.lockFocus()

        // Background
        NSColor.systemBlue.setFill()
        let rect = NSRect(origin: .zero, size: size)
        rect.fill()

        // Text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
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

    private func saveToDiskCache(data: Data, cacheKey: String, originalURL: String) {
        let cacheEntry = FaviconCacheEntry(
            imageData: data,
            cachedDate: Date(),
            originalURL: originalURL
        )

        do {
            let encodedData = try JSONEncoder().encode(cacheEntry)
            let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
            try encodedData.write(to: fileURL)
            print("💾 [FaviconManager] Saved favicon to disk cache: \(originalURL)")
        } catch {
            print("❌ [FaviconManager] Failed to save to disk cache: \(error)")
        }
    }

    private func loadFromDiskCache(cacheKey: String) -> FaviconCacheEntry? {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)

        do {
            let data = try Data(contentsOf: fileURL)
            let cacheEntry = try JSONDecoder().decode(FaviconCacheEntry.self, from: data)
            return cacheEntry
        } catch {
            // File doesn't exist or is corrupted - not an error, just cache miss
            return nil
        }
    }

    private func removeFromDiskCache(cacheKey: String) {
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func limitMemoryCache() {
        if memoryCache.count > maxMemoryCacheSize {
            // Remove oldest entries (simple FIFO for now)
            let keysToRemove = Array(memoryCache.keys).prefix(memoryCache.count - maxMemoryCacheSize)
            for key in keysToRemove {
                memoryCache.removeValue(forKey: key)
            }
        }
    }

    private func cleanExpiredCache() {
        cacheQueue.async { [weak self] in
            guard let self else { return }

            do {
                let cacheFiles = try FileManager.default.contentsOfDirectory(
                    at: cacheDirectory,
                    includingPropertiesForKeys: nil
                )
                var expiredCount = 0

                for file in cacheFiles {
                    let cacheKey = file.lastPathComponent
                    if let cacheEntry = loadFromDiskCache(cacheKey: cacheKey) {
                        if cacheEntry.isExpired {
                            try FileManager.default.removeItem(at: file)
                            expiredCount += 1
                        }
                    }
                }

                if expiredCount > 0 {
                    print("🧹 [FaviconManager] Cleaned \(expiredCount) expired favicon(s) from cache")
                }
            } catch {
                print("❌ [FaviconManager] Failed to clean expired cache: \(error)")
            }
        }
    }

    private func preloadCommonFavicons() {
        // Common websites that users frequently visit
        // TODO: Add more common websites
        /// Note: This should be a JSON file in the app bundle
        /// or a separate Swift file index; this is just a temporary solution.
        let commonFavicons = [
            "https://www.google.com/favicon.ico",
            "https://github.com/favicon.ico",
            "https://stackoverflow.com/favicon.ico",
            "https://www.youtube.com/favicon.ico",
            "https://www.wikipedia.org/favicon.ico"
        ]

        // Preload in background after a short delay to not impact app startup
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) {
            for faviconURL in commonFavicons {
                self.fetchFavicon(for: faviconURL) { _ in
                    // Silent preload - no need to handle result
                }
            }
        }
    }

    // MARK: - HTML Favicon Detection Helpers

    private func tryRemainingFaviconLinks(
        _ remainingLinks: [[String: Any]],
        baseURL: URL,
        completion: @escaping (NSImage?) -> ()
    ) {
        guard let nextLink = remainingLinks.first,
              let href = nextLink["href"] as? String else {
            // No more links to try, fallback to traditional method
            fallbackToTraditionalFavicon(baseURL: baseURL, completion: completion)
            return
        }

        let faviconURL = resolveURL(href: href, baseURL: baseURL)
        print("🔍 [FaviconManager] Trying additional favicon from HTML: \(faviconURL)")

        fetchFavicon(for: faviconURL) { [weak self] image in
            DispatchQueue.main.async {
                if let image {
                    completion(image)
                } else {
                    // Try the next one
                    self?.tryRemainingFaviconLinks(
                        Array(remainingLinks.dropFirst()),
                        baseURL: baseURL,
                        completion: completion
                    )
                }
            }
        }
    }

    private func fallbackToTraditionalFavicon(baseURL: URL, completion: @escaping (NSImage?) -> ()) {
        guard let host = baseURL.host else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let faviconURL = "https://\(host)/favicon.ico"
        print("🔄 [FaviconManager] Falling back to traditional favicon: \(faviconURL)")

        fetchFavicon(for: faviconURL) { image in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private func resolveURL(href: String, baseURL: URL) -> String {
        // Handle absolute URLs
        if href.hasPrefix("http://") || href.hasPrefix("https://") {
            return href
        }

        // Handle protocol-relative URLs
        if href.hasPrefix("//") {
            return "\(baseURL.scheme ?? "https"):\(href)"
        }

        // Handle absolute paths
        if href.hasPrefix("/") {
            return "\(baseURL.scheme ?? "https")://\(baseURL.host ?? "")\(href)"
        }

        // Handle relative paths
        let baseURLString = baseURL.absoluteString
        if baseURLString.hasSuffix("/") {
            return "\(baseURLString)\(href)"
        } else {
            return "\(baseURLString)/\(href)"
        }
    }

    private func extractSizeFromString(_ sizeString: String) -> Int {
        // Extract numeric size from strings like "32x32", "any", etc.
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
