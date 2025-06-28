//
//  ExtensionStorage.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ExtensionStorage

/// Manages persistent storage of installed extensions
@MainActor
public class ExtensionStorage {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ExtensionStorage")

    /// Shared instance
    public static let shared = ExtensionStorage()

    /// Extensions directory in Application Support
    private let extensionsDirectory: URL

    /// Installed extensions metadata file
    private let metadataFile: URL

    /// Currently installed extensions metadata
    private var installedExtensions: [String: InstalledExtensionMetadata] = [:]

    private init() {
        // Create extensions directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let altoSupport = appSupport.appendingPathComponent("Alto")
        extensionsDirectory = altoSupport.appendingPathComponent("Extensions")
        metadataFile = altoSupport.appendingPathComponent("installed_extensions.json")

        // Create directories if they don't exist
        createDirectoriesIfNeeded()

        // Load existing metadata
        loadInstalledExtensions()

        logger.info("📁 ExtensionStorage initialized at: \(self.extensionsDirectory.path)")
    }

    // MARK: - Initialization

    /// Initialize extension storage system
    /// This method can be called to ensure storage is ready for use
    public func initialize() async {
        logger.info("🔧 Initializing extension storage system...")

        // Ensure directories exist
        createDirectoriesIfNeeded()

        // Reload metadata to ensure we have the latest state
        loadInstalledExtensions()

        // Validate existing installations and clean up any corrupted entries
        await validateInstalledExtensions()

        logger.info("✅ Extension storage system initialized successfully")
    }

    /// Validate that all installed extensions still exist on disk
    private func validateInstalledExtensions() async {
        var extensionsToRemove: [String] = []

        for (extensionId, metadata) in installedExtensions {
            let extensionPath = metadata.installationPath

            if !FileManager.default.fileExists(atPath: extensionPath) {
                logger.warning("⚠️ Extension \(extensionId) (\(metadata.name)) not found at path: \(extensionPath)")
                extensionsToRemove.append(extensionId)
            }
        }

        // Clean up missing extensions
        for extensionId in extensionsToRemove {
            logger.info("🧹 Removing metadata for missing extension: \(extensionId)")
            installedExtensions.removeValue(forKey: extensionId)
        }

        if !extensionsToRemove.isEmpty {
            saveInstalledExtensions()
            logger.info("🗑️ Cleaned up \(extensionsToRemove.count) missing extension(s)")
        }
    }

    // MARK: - Directory Management

    /// Create necessary directories
    private func createDirectoriesIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)
            logger.debug("📁 Created extensions directory: \(self.extensionsDirectory.path)")
        } catch {
            logger.error("❌ Failed to create extensions directory: \(error)")
        }
    }

    // MARK: - Metadata Management

    /// Load installed extensions metadata
    private func loadInstalledExtensions() {
        guard FileManager.default.fileExists(atPath: metadataFile.path) else {
            logger.debug("📄 No existing metadata file found")
            return
        }

        do {
            let data = try Data(contentsOf: metadataFile)
            let metadata = try JSONDecoder().decode([String: InstalledExtensionMetadata].self, from: data)
            installedExtensions = metadata
            logger.info("📋 Loaded \(metadata.count) installed extensions from metadata")
        } catch {
            logger.error("❌ Failed to load extensions metadata: \(error)")
        }
    }

    /// Save installed extensions metadata
    private func saveInstalledExtensions() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(installedExtensions)
            try data.write(to: metadataFile)
            logger.debug("💾 Saved extensions metadata")
        } catch {
            logger.error("❌ Failed to save extensions metadata: \(error)")
        }
    }

    // MARK: - Extension Installation

    /// Install extension permanently to Application Support
    /// - Parameters:
    ///   - tempURL: Temporary location of extracted extension
    ///   - extensionId: Extension identifier
    ///   - manifest: Extension manifest
    ///   - installationSource: Source where extension was installed from
    ///   - originalId: Original Chrome Web Store ID (if applicable)
    /// - Returns: Permanent installation URL
    public func installExtension(
        from tempURL: URL,
        extensionId: String,
        manifest: ExtensionManifest,
        installationSource: ExtensionInstallationSource = .local,
        originalId: String? = nil
    ) throws -> URL {
        let permanentURL = extensionsDirectory.appendingPathComponent(extensionId)

        logger.info("📦 Installing extension \(extensionId) to permanent location")
        logger.debug("📁 Source: \(tempURL.path)")
        logger.debug("📁 Destination: \(permanentURL.path)")

        // Remove existing installation if it exists
        if FileManager.default.fileExists(atPath: permanentURL.path) {
            try FileManager.default.removeItem(at: permanentURL)
            logger.debug("🗑️ Removed existing installation")
        }

        // Copy extension to permanent location
        try FileManager.default.copyItem(at: tempURL, to: permanentURL)

        // Create metadata entry
        let metadata = InstalledExtensionMetadata(
            id: extensionId,
            name: manifest.name,
            version: manifest.version,
            manifestVersion: manifest.manifestVersion,
            description: manifest.description,
            permissions: Array(manifest.allPermissions),
            hostPermissions: manifest.hostPermissions ?? [],
            contentScripts: manifest.contentScripts?.map { script in
                ContentScriptMetadata(
                    matches: script.matches,
                    js: script.js ?? [],
                    css: script.css ?? [],
                    runAt: script.run_at
                )
            } ?? [],
            installDate: Date(),
            lastUsed: Date(),
            isEnabled: true,
            installationPath: permanentURL.path,
            installationSource: installationSource,
            originalId: originalId
        )

        // Store metadata
        installedExtensions[extensionId] = metadata
        saveInstalledExtensions()

        logger.info("✅ Extension \(extensionId) installed permanently")
        logger.info("📍 Location: \(permanentURL.path)")

        return permanentURL
    }

    /// Uninstall extension
    /// - Parameter extensionId: Extension to uninstall
    public func uninstallExtension(_ extensionId: String) throws {
        guard let metadata = installedExtensions[extensionId] else {
            throw ExtensionStorageError.extensionNotFound(extensionId)
        }

        let extensionURL = URL(fileURLWithPath: metadata.installationPath)

        // Remove extension files
        if FileManager.default.fileExists(atPath: extensionURL.path) {
            try FileManager.default.removeItem(at: extensionURL)
            logger.info("🗑️ Removed extension files: \(extensionURL.path)")
        }

        // Remove from metadata
        installedExtensions.removeValue(forKey: extensionId)
        saveInstalledExtensions()

        logger.info("✅ Extension \(extensionId) uninstalled")
    }

    // MARK: - Extension Management

    /// Check if extension is installed
    /// - Parameter extensionId: Extension ID to check
    /// - Returns: Whether extension is installed
    public func isExtensionInstalled(_ extensionId: String) -> Bool {
        installedExtensions[extensionId] != nil
    }

    /// Get installed extension metadata
    /// - Parameter extensionId: Extension ID
    /// - Returns: Extension metadata if installed
    public func getExtensionMetadata(_ extensionId: String) -> InstalledExtensionMetadata? {
        installedExtensions[extensionId]
    }

    /// Get all installed extensions
    /// - Returns: Dictionary of installed extensions
    public func getAllInstalledExtensions() -> [String: InstalledExtensionMetadata] {
        installedExtensions
    }

    /// Get extensions that should be loaded for a URL
    /// - Parameter url: URL to check
    /// - Returns: Extensions that should be active for this URL
    public func getExtensionsForURL(_ url: URL) -> [InstalledExtensionMetadata] {
        installedExtensions.values.compactMap { metadata in
            guard metadata.isEnabled else { return nil }

            // Check if any content scripts match this URL
            for contentScript in metadata.contentScripts {
                if contentScript.matchesURL(url) {
                    return metadata
                }
            }

            // Check host permissions
            for hostPattern in metadata.hostPermissions {
                if URLPattern.matches(pattern: hostPattern, url: url) {
                    return metadata
                }
            }

            return nil
        }
    }

    /// Enable/disable extension
    /// - Parameters:
    ///   - extensionId: Extension ID
    ///   - enabled: Whether to enable the extension
    public func setExtensionEnabled(_ extensionId: String, enabled: Bool) {
        guard var metadata = installedExtensions[extensionId] else { return }

        metadata.isEnabled = enabled
        metadata.lastUsed = Date()
        installedExtensions[extensionId] = metadata
        saveInstalledExtensions()

        logger.info("⚙️ Extension \(extensionId) \(enabled ? "enabled" : "disabled")")
    }

    /// Update extension last used timestamp
    /// - Parameter extensionId: Extension ID
    public func updateLastUsed(_ extensionId: String) {
        guard var metadata = installedExtensions[extensionId] else { return }

        metadata.lastUsed = Date()
        installedExtensions[extensionId] = metadata
        saveInstalledExtensions()
    }

    // MARK: - Extension Settings

    /// Get extension options page URL if available
    /// - Parameter extensionId: Extension ID
    /// - Returns: Options page URL if available
    public func getExtensionOptionsURL(_ extensionId: String) -> URL? {
        guard let metadata = installedExtensions[extensionId] else { return nil }

        let extensionURL = URL(fileURLWithPath: metadata.installationPath)

        // Load manifest to get options page
        let manifestURL = extensionURL.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? ExtensionManifest.parse(from: manifestData),
              let optionsPage = manifest.optionsPage else {
            return nil
        }

        return extensionURL.appendingPathComponent(optionsPage)
    }
}

// MARK: - InstalledExtensionMetadata

/// Metadata for an installed extension
public struct InstalledExtensionMetadata: Codable {
    public let id: String
    public let name: String
    public let version: String
    public let manifestVersion: Int
    public let description: String?
    public let permissions: [String]
    public let hostPermissions: [String]
    public let contentScripts: [ContentScriptMetadata]
    public let installDate: Date
    public var lastUsed: Date
    public var isEnabled: Bool
    public let installationPath: String

    /// Source where the extension was installed from
    public let installationSource: ExtensionInstallationSource

    /// Original Chrome Web Store ID (if installed from Chrome Web Store)
    public let originalId: String?

    public init(
        id: String,
        name: String,
        version: String,
        manifestVersion: Int,
        description: String?,
        permissions: [String],
        hostPermissions: [String],
        contentScripts: [ContentScriptMetadata],
        installDate: Date,
        lastUsed: Date,
        isEnabled: Bool,
        installationPath: String,
        installationSource: ExtensionInstallationSource = .local,
        originalId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.manifestVersion = manifestVersion
        self.description = description
        self.permissions = permissions
        self.hostPermissions = hostPermissions
        self.contentScripts = contentScripts
        self.installDate = installDate
        self.lastUsed = lastUsed
        self.isEnabled = isEnabled
        self.installationPath = installationPath
        self.installationSource = installationSource
        self.originalId = originalId
    }

    // Custom decoder to handle backward compatibility
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        permissions = try container.decode([String].self, forKey: .permissions)
        hostPermissions = try container.decode([String].self, forKey: .hostPermissions)
        contentScripts = try container.decode([ContentScriptMetadata].self, forKey: .contentScripts)
        installDate = try container.decode(Date.self, forKey: .installDate)
        lastUsed = try container.decode(Date.self, forKey: .lastUsed)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        installationPath = try container.decode(String.self, forKey: .installationPath)

        // Handle new fields with defaults for backward compatibility
        installationSource = try container.decodeIfPresent(
            ExtensionInstallationSource.self,
            forKey: .installationSource
        ) ?? .local
        originalId = try container.decodeIfPresent(String.self, forKey: .originalId)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case manifestVersion
        case description
        case permissions
        case hostPermissions
        case contentScripts
        case installDate
        case lastUsed
        case isEnabled
        case installationPath
        case installationSource
        case originalId
    }
}

// MARK: - ExtensionInstallationSource

/// Source where an extension was installed from
public enum ExtensionInstallationSource: String, Codable {
    case local
    case chromeWebStore = "chrome_web_store"
    case firefoxAddons = "firefox_addons"
    case developer
}

// MARK: - ContentScriptMetadata

/// Content script metadata
public struct ContentScriptMetadata: Codable {
    public let matches: [String]
    public let js: [String]
    public let css: [String]
    public let runAt: String?

    /// Check if this content script matches a URL
    /// - Parameter url: URL to check
    /// - Returns: Whether content script should run on this URL
    public func matchesURL(_ url: URL) -> Bool {
        for pattern in matches {
            if URLPattern.matches(pattern: pattern, url: url) {
                return true
            }
        }
        return false
    }
}

// MARK: - URLPattern

/// URL pattern matching utility
public enum URLPattern {
    /// Check if URL pattern matches a URL
    /// - Parameters:
    ///   - pattern: URL pattern (e.g., "*://*.google.com/*")
    ///   - url: URL to check
    /// - Returns: Whether pattern matches URL
    public static func matches(pattern: String, url: URL) -> Bool {
        // Handle special patterns
        if pattern == "<all_urls>" {
            return true
        }

        // Convert pattern to regex
        let regexPattern = patternToRegex(pattern)

        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }

        let urlString = url.absoluteString
        let range = NSRange(location: 0, length: urlString.count)
        return regex.firstMatch(in: urlString, options: [], range: range) != nil
    }

    /// Convert URL pattern to regex
    /// - Parameter pattern: URL pattern
    /// - Returns: Regex pattern
    private static func patternToRegex(_ pattern: String) -> String {
        var regex = pattern

        // Escape regex special characters except * and ?
        let specialChars = [".", "+", "^", "$", "(", ")", "[", "]", "{", "}", "|", "\\"]
        for char in specialChars {
            regex = regex.replacingOccurrences(of: char, with: "\\\(char)")
        }

        // Convert wildcards
        regex = regex.replacingOccurrences(of: "*", with: ".*")
        regex = regex.replacingOccurrences(of: "?", with: ".")

        // Anchor the pattern
        return "^" + regex + "$"
    }
}

// MARK: - ExtensionStorageError

/// Extension storage errors
public enum ExtensionStorageError: Error, LocalizedError {
    case extensionNotFound(String)
    case installationFailed(String)
    case metadataCorrupted

    public var errorDescription: String? {
        switch self {
        case let .extensionNotFound(id):
            "Extension not found: \(id)"
        case let .installationFailed(reason):
            "Installation failed: \(reason)"
        case .metadataCorrupted:
            "Extension metadata is corrupted"
        }
    }
}
