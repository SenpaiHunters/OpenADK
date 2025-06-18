import Foundation
import Observation
import SwiftUI

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
    public static let shared = FaviconManager()

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

    private init() {
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

        URLSession.shared.dataTask(with: faviconURL) { [weak self] data, _, error in
            if let error {
                print("❌ [FaviconManager] Network error fetching favicon: \(error)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            guard let data, let image = NSImage(data: data) else {
                print("❌ [FaviconManager] Invalid image data for: \(url)")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            print("✅ [FaviconManager] Successfully fetched favicon for: \(url)")

            // Cache the image
            self?.saveToDiskCache(data: data, cacheKey: cacheKey, originalURL: url)

            // Store in memory cache
            DispatchQueue.main.async {
                self?.memoryCache[cacheKey] = image
                self?.limitMemoryCache()
                completion(image)
            }
        }.resume()
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
}
