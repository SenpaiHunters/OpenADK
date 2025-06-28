//
//  ExtensionStoreDownloader.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ExtensionStoreDownloader

/// Downloads and installs extensions from the Chrome Web Store
public class ExtensionStoreDownloader: NSObject {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "StoreDownloader")
    private let urlSession = URLSession.shared

    /// Downloads an extension from Chrome Web Store URL
    /// - Parameters:
    ///   - storeURL: Chrome Web Store URL (e.g., https://chromewebstore.google.com/detail/extension-name/id)
    ///   - completion: Completion handler with local extension URL or error
    public func downloadExtension(
        from storeURL: URL,
        completion: @escaping (Result<URL, ExtensionDownloadError>) -> ()
    ) {
        logger.info("📦 Starting extension download from: \(storeURL)")

        // Extract extension ID from Chrome Web Store URL
        guard let extensionId = extractExtensionId(from: storeURL) else {
            completion(.failure(.invalidStoreURL))
            return
        }

        logger.debug("🔍 Extracted extension ID: \(extensionId)")

        // Download the extension using Chrome Web Store API
        downloadExtensionById(extensionId) { result in
            switch result {
            case let .success(localURL):
                self.logger.info("✅ Extension downloaded successfully to: \(localURL)")
                completion(.success(localURL))

            case let .failure(error):
                self.logger.error("❌ Extension download failed: \(error)")
                completion(.failure(error))
            }
        }
    }

    /// Extracts extension ID from Chrome Web Store URL
    /// - Parameter url: Store URL
    /// - Returns: Extension ID if found
    private func extractExtensionId(from url: URL) -> String? {
        let urlString = url.absoluteString

        // Handle different Chrome Web Store URL formats:
        // https://chromewebstore.google.com/detail/extension-name/id
        // https://chrome.google.com/webstore/detail/extension-name/id

        // Updated pattern to match the actual URL format
        if let regex = try? NSRegularExpression(pattern: #"detail/[^/]+/([a-zA-Z]{32})"#, options: []) {
            let range = NSRange(location: 0, length: urlString.utf16.count)
            if let match = regex.firstMatch(in: urlString, options: [], range: range) {
                let idRange = Range(match.range(at: 1), in: urlString)!
                return String(urlString[idRange])
            }
        }

        // Alternative pattern for older URLs
        if let regex = try? NSRegularExpression(pattern: #"webstore/detail/[^/]+/([a-zA-Z]{32})"#, options: []) {
            let range = NSRange(location: 0, length: urlString.utf16.count)
            if let match = regex.firstMatch(in: urlString, options: [], range: range) {
                let idRange = Range(match.range(at: 1), in: urlString)!
                return String(urlString[idRange])
            }
        }

        // Try to extract ID from the end of the URL path
        let pathComponents = url.pathComponents
        if !pathComponents.isEmpty {
            let lastComponent = pathComponents.last ?? ""
            // Extension IDs are 32 character strings with lowercase letters
            if lastComponent.count == 32, lastComponent.allSatisfy({ $0.isLetter && $0.isLowercase }) {
                return lastComponent
            }
        }

        logger.debug("❌ Could not extract extension ID from URL: \(urlString)")
        return nil
    }

    /// Downloads extension by ID from Chrome Web Store
    /// - Parameters:
    ///   - extensionId: Chrome extension ID
    ///   - completion: Completion handler
    private func downloadExtensionById(
        _ extensionId: String,
        completion: @escaping (Result<URL, ExtensionDownloadError>) -> ()
    ) {
        logger.info("📥 Attempting to download extension ID: \(extensionId)")

        // Chrome Web Store download URL - Try multiple formats
        let downloadURLStrings = [
            // Primary format - Chrome update service
            "https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3&prodversion=130.0.6723.116&x=id%3D\(extensionId)%26installsource%3Dondemand%26uc",
            // Alternative format
            "https://clients2.google.com/service/update2/crx?response=redirect&os=mac&arch=x64&prod=chrome&prodchannel=stable&prodversion=130.0.6723.116&acceptformat=crx2,crx3&x=id%3D\(extensionId)%26installsource%3Dondemand%26uc",
            // Backup format
            "https://update.googleapis.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3&x=id%3D\(extensionId)%26installsource%3Dondemand%26uc"
        ]

        tryDownloadWithURLs(extensionId: extensionId, urls: downloadURLStrings, completion: completion)
    }

    /// Attempts to download using multiple URL formats
    /// - Parameters:
    ///   - extensionId: Extension ID
    ///   - urls: Array of URLs to try
    ///   - completion: Completion handler
    private func tryDownloadWithURLs(
        extensionId: String,
        urls: [String],
        completion: @escaping (Result<URL, ExtensionDownloadError>) -> ()
    ) {
        guard !urls.isEmpty else {
            completion(.failure(.invalidDownloadURL))
            return
        }

        let downloadURLString = urls.first!
        let remainingURLs = Array(urls.dropFirst())

        guard let downloadURL = URL(string: downloadURLString) else {
            logger.error("❌ Invalid download URL constructed: \(downloadURLString)")
            if !remainingURLs.isEmpty {
                logger.debug("🔄 Trying next URL format...")
                tryDownloadWithURLs(extensionId: extensionId, urls: remainingURLs, completion: completion)
            } else {
                completion(.failure(.invalidDownloadURL))
            }
            return
        }

        logger.debug("📥 Download URL: \(downloadURL)")

        // Create temporary directory for download
        let tempDir = createTempDirectory()
        let crxFile = tempDir.appendingPathComponent("\(extensionId).crx")

        logger.debug("📁 Temp directory: \(tempDir)")
        logger.debug("📦 CRX file path: \(crxFile)")

        // Create a URL session with Chrome-like headers for better compatibility
        var request = URLRequest(url: downloadURL)

        // Spoof latest Chrome User-Agent
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        // Add comprehensive Chrome headers
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("gzip, deflate, br, zstd", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("1", forHTTPHeaderField: "Sec-CH-UA-Mobile")
        request.setValue(
            "\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"",
            forHTTPHeaderField: "Sec-CH-UA"
        )
        request.setValue("\"macOS\"", forHTTPHeaderField: "Sec-CH-UA-Platform")
        request.setValue("https://chromewebstore.google.com", forHTTPHeaderField: "Referer")
        request.setValue("chromewebstore.google.com", forHTTPHeaderField: "Origin")

        // Download the .crx file
        let downloadTask = urlSession.downloadTask(with: request) { [weak self] localURL, response, error in
            guard let self else { return }

            if let error {
                logger.error("❌ Download failed with error: \(error)")
                if !remainingURLs.isEmpty {
                    logger.debug("🔄 Trying next URL format due to error...")
                    tryDownloadWithURLs(extensionId: extensionId, urls: remainingURLs, completion: completion)
                } else {
                    completion(.failure(.downloadFailed(error)))
                }
                return
            }

            guard let localURL else {
                logger.error("❌ No download URL returned")
                if !remainingURLs.isEmpty {
                    logger.debug("🔄 Trying next URL format due to no response...")
                    tryDownloadWithURLs(extensionId: extensionId, urls: remainingURLs, completion: completion)
                } else {
                    completion(.failure(.downloadFailed(NSError(
                        domain: "ExtensionDownloader",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No download URL returned"]
                    ))))
                }
                return
            }

            // Log response info
            if let httpResponse = response as? HTTPURLResponse {
                logger.debug("📡 Response status: \(httpResponse.statusCode)")
                logger.debug("📡 Response headers: \(httpResponse.allHeaderFields)")

                // Check for non-success status codes
                if httpResponse.statusCode == 204 || httpResponse.statusCode == 404 {
                    logger.warning("⚠️ Received status \(httpResponse.statusCode), trying next URL format...")
                    if !remainingURLs.isEmpty {
                        tryDownloadWithURLs(extensionId: extensionId, urls: remainingURLs, completion: completion)
                        return
                    }
                }
            }

            do {
                // Check if file exists and has content
                let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
                let fileSize = attributes[.size] as? Int64 ?? 0
                logger.debug("📏 Downloaded file size: \(fileSize) bytes")

                if fileSize == 0 {
                    logger.warning("⚠️ Downloaded file is empty, trying next URL format...")
                    if !remainingURLs.isEmpty {
                        tryDownloadWithURLs(extensionId: extensionId, urls: remainingURLs, completion: completion)
                        return
                    } else {
                        throw ExtensionDownloadError.downloadFailed(NSError(
                            domain: "ExtensionDownloader",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Downloaded file is empty"]
                        ))
                    }
                }

                // Move downloaded file to permanent location
                if FileManager.default.fileExists(atPath: crxFile.path) {
                    try FileManager.default.removeItem(at: crxFile)
                }
                try FileManager.default.moveItem(at: localURL, to: crxFile)
                logger.debug("✅ File moved to: \(crxFile)")

                // Check if it's actually a CRX file by reading the first few bytes
                let fileData = try Data(contentsOf: crxFile)
                let header = fileData.prefix(4)
                logger.debug("📄 File header: \(header.map { String(format: "%02x", $0) }.joined())")

                if fileData.count < 16 {
                    throw ExtensionDownloadError.invalidCRXFile
                }

                // Extract the .crx file
                let extractedDir = try extractCRXFile(crxFile, to: tempDir)
                logger.info("✅ Extension extracted to: \(extractedDir)")
                completion(.success(extractedDir))

            } catch {
                logger.error("❌ Failed to process downloaded file: \(error)")
                completion(.failure(.extractionFailed(error)))
            }
        }

        downloadTask.resume()
        logger.debug("🚀 Download task started")
    }

    /// Creates a temporary directory for extension downloads
    /// - Returns: Temporary directory URL
    private func createTempDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AltoExtensions")
            .appendingPathComponent(UUID().uuidString)

        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    /// Extracts a .crx file to a directory
    /// - Parameters:
    ///   - crxFile: Path to .crx file
    ///   - destinationDir: Destination directory
    /// - Returns: Path to extracted extension directory
    private func extractCRXFile(_ crxFile: URL, to destinationDir: URL) throws -> URL {
        // .crx files are essentially ZIP files with a header
        // For simplicity, we'll try to handle them as ZIP files

        let extractDir = destinationDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // Try to extract using NSTask with unzip
        let process = Process()
        process.launchPath = "/usr/bin/unzip"
        process.arguments = ["-o", "-q", crxFile.path, "-d", extractDir.path]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                logger.debug("✅ Successfully extracted CRX file")
                return extractDir
            } else {
                throw ExtensionDownloadError.extractionFailed(NSError(
                    domain: "ExtensionDownloader",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Unzip failed"]
                ))
            }
        } catch {
            // If unzip fails, try manual CRX parsing
            return try extractCRXManually(crxFile, to: extractDir)
        }
    }

    /// Manually extracts a CRX file by parsing its header
    /// - Parameters:
    ///   - crxFile: CRX file to extract
    ///   - extractDir: Destination directory
    /// - Returns: Extracted directory URL
    private func extractCRXManually(_ crxFile: URL, to extractDir: URL) throws -> URL {
        let data = try Data(contentsOf: crxFile)

        // CRX3 format:
        // - Magic number: "Cr24" (4 bytes)
        // - Version: 3 (4 bytes)
        // - Header length (4 bytes)
        // - Header data
        // - ZIP data

        guard data.count > 16 else {
            throw ExtensionDownloadError.invalidCRXFile
        }

        // Check magic number
        let magic = data.subdata(in: 0 ..< 4)
        let magicString = String(data: magic, encoding: .ascii)

        guard magicString == "Cr24" else {
            throw ExtensionDownloadError.invalidCRXFile
        }

        // Read version
        let version = data.subdata(in: 4 ..< 8).withUnsafeBytes { $0.load(as: UInt32.self) }

        guard version == 3 else {
            // Try to handle as CRX2 or fallback
            throw ExtensionDownloadError.unsupportedCRXVersion
        }

        // Read header length
        let headerLength = data.subdata(in: 8 ..< 12).withUnsafeBytes { $0.load(as: UInt32.self) }

        // Extract ZIP data (skip magic + version + header length + header)
        let zipDataStart = 12 + Int(headerLength)
        guard zipDataStart < data.count else {
            throw ExtensionDownloadError.invalidCRXFile
        }

        let zipData = data.subdata(in: zipDataStart ..< data.count)

        // Write ZIP data to temporary file and extract
        let tempZipFile = extractDir.appendingPathComponent("temp.zip")
        try zipData.write(to: tempZipFile)

        // Extract ZIP
        let process = Process()
        process.launchPath = "/usr/bin/unzip"
        process.arguments = ["-o", "-q", tempZipFile.path, "-d", extractDir.path]

        try process.run()
        process.waitUntilExit()

        // Clean up temp ZIP file
        try? FileManager.default.removeItem(at: tempZipFile)

        if process.terminationStatus == 0 {
            return extractDir
        } else {
            throw ExtensionDownloadError.extractionFailed(NSError(
                domain: "ExtensionDownloader",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ZIP extraction failed"]
            ))
        }
    }
}

// MARK: - ExtensionDownloadError

/// Errors that can occur during extension download
public enum ExtensionDownloadError: Error, LocalizedError {
    case invalidStoreURL
    case invalidDownloadURL
    case downloadFailed(Error)
    case extractionFailed(Error)
    case invalidCRXFile
    case unsupportedCRXVersion

    public var errorDescription: String? {
        switch self {
        case .invalidStoreURL:
            "Invalid Chrome Web Store URL"
        case .invalidDownloadURL:
            "Could not construct download URL"
        case let .downloadFailed(error):
            "Download failed: \(error.localizedDescription)"
        case let .extractionFailed(error):
            "Extraction failed: \(error.localizedDescription)"
        case .invalidCRXFile:
            "Invalid CRX file format"
        case .unsupportedCRXVersion:
            "Unsupported CRX file version"
        }
    }
}
