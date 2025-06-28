//
//  ExtensionManifest.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ManifestVersion

/// Represents the different manifest versions supported
public enum ManifestVersion: Int, Codable {
    case v2 = 2
    case v3 = 3
}

// MARK: - ExtensionPlatform

/// Extension platform types
public enum ExtensionPlatform: String, Codable {
    case chrome
    case firefox
    case webextensions
}

// MARK: - ExtensionManifest

/// Represents a browser extension manifest (Chrome v2/v3 or Firefox WebExtensions)
/// Supports parsing and validation of extension metadata and configuration
public struct ExtensionManifest: Codable, Equatable, Identifiable {
    public let id = UUID()

    // MARK: - Core Properties

    public let manifestVersion: Int
    public let name: String
    public let version: String
    public let description: String?

    // MARK: - Extension Type & Permissions

    public let permissions: [String]?
    public let optionalPermissions: [String]?
    public let hostPermissions: [String]?
    public let contentSecurityPolicy: String?

    // MARK: - Background Configuration

    public let background: ManifestBackgroundConfiguration?

    // MARK: - Content Scripts

    public let contentScripts: [ManifestContentScript]?

    // MARK: - Actions & Icons

    public let action: ActionConfiguration?
    public let browserAction: ActionConfiguration?
    public let pageAction: ActionConfiguration?
    public let icons: [String: String]?

    // MARK: - Web Accessible Resources

    public let webAccessibleResources: WebAccessibleResourcesConfiguration?

    // MARK: - Optional Features

    public let options: OptionsConfiguration?
    public let devtools: DevtoolsConfiguration?
    public let commands: [String: CommandConfiguration]?
    public let externally_connectable: ExternallyConnectableConfiguration?
    public let declarative_net_request: DeclarativeNetRequestConfiguration?

    // MARK: - Firefox Specific

    public let applications: ApplicationsConfiguration?
    public let browser_specific_settings: BrowserSpecificSettingsConfiguration?

    // MARK: - Additional Properties

    public let homepage_url: String?
    public let update_url: String?
    public let minimum_chrome_version: String?
    public let minimum_firefox_version: String?
    public let `default`: String?

    private enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case name, version, description, permissions
        case optionalPermissions = "optional_permissions"
        case hostPermissions = "host_permissions"
        case contentSecurityPolicy = "content_security_policy"
        case background
        case contentScripts = "content_scripts"
        case action, browserAction = "browser_action", pageAction = "page_action"
        case icons
        case webAccessibleResources = "web_accessible_resources"
        case options = "options_ui"
        case devtools = "devtools_page"
        case commands
        case externally_connectable
        case declarative_net_request
        case applications
        case browser_specific_settings
        case homepage_url
        case update_url
        case minimum_chrome_version
        case minimum_firefox_version
        case `default`
    }

    public static func == (lhs: ExtensionManifest, rhs: ExtensionManifest) -> Bool {
        lhs.manifestVersion == rhs.manifestVersion &&
            lhs.name == rhs.name &&
            lhs.version == rhs.version &&
            lhs.description == rhs.description
    }

    // MARK: - Computed Properties for Compatibility

    /// Returns the options page URL for backward compatibility
    public var optionsPage: String? {
        options?.page
    }

    /// Returns all permissions including regular, optional, and host permissions
    public var allPermissions: Set<String> {
        var allPerms = Set<String>()

        if let perms = permissions {
            allPerms.formUnion(perms)
        }

        if let optPerms = optionalPermissions {
            allPerms.formUnion(optPerms)
        }

        if let hostPerms = hostPermissions {
            allPerms.formUnion(hostPerms)
        }

        // Add content script host patterns as permissions
        if let contentScripts {
            for script in contentScripts {
                allPerms.formUnion(script.matches)
            }
        }

        return allPerms
    }
}

// MARK: - ManifestBackgroundConfiguration

public struct ManifestBackgroundConfiguration: Codable, Equatable {
    public let scripts: [String]?
    public let page: String?
    public let service_worker: String?
    public let persistent: Bool?
    public let type: String?
}

// MARK: - ManifestContentScript

public struct ManifestContentScript: Codable, Equatable {
    public let matches: [String]
    public let js: [String]?
    public let css: [String]?
    public let run_at: String?
    public let all_frames: Bool?
    public let match_about_blank: Bool?
    public let include_globs: [String]?
    public let exclude_globs: [String]?
    public let exclude_matches: [String]?
}

// MARK: - ActionConfiguration

public struct ActionConfiguration: Codable, Equatable {
    public let default_title: String?
    public let default_popup: String?
    public let default_icon: IconConfiguration?
}

// MARK: - IconConfiguration

public struct IconConfiguration: Codable, Equatable {
    public let icon16: String?
    public let icon32: String?
    public let icon48: String?
    public let icon128: String?

    private enum CodingKeys: String, CodingKey {
        case icon16 = "16"
        case icon32 = "32"
        case icon48 = "48"
        case icon128 = "128"
    }
}

// MARK: - WebAccessibleResourcesConfiguration

public struct WebAccessibleResourcesConfiguration: Codable, Equatable {
    public let resources: [String]?
    public let matches: [String]?
    public let extension_ids: [String]?

    /// Initialize from array format (manifest v2)
    public init(resources: [String]) {
        self.resources = resources
        matches = nil
        extension_ids = nil
    }

    /// Initialize from object format (manifest v3)
    public init(resources: [String]?, matches: [String]?, extension_ids: [String]?) {
        self.resources = resources
        self.matches = matches
        self.extension_ids = extension_ids
    }

    /// Custom decoder to handle both array and object formats
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Debug logging to see what we're trying to decode
        if let debugValue = try? container.decode(AnyCodable.self) {
            print("🔍 Debug: web_accessible_resources raw value: \(debugValue)")
        }

        // Try to decode as simple array first (manifest v2)
        if let resourceArray = try? container.decode([String].self) {
            print("✅ Decoded web_accessible_resources as simple array (v2): \(resourceArray)")
            resources = resourceArray
            matches = nil
            extension_ids = nil
        }
        // Try to decode as array of objects (manifest v3 array format)
        else if let objectArray = try? container.decode([[String: AnyCodable]].self) {
            print("✅ Decoded web_accessible_resources as array of objects (v3): \(objectArray)")

            // Take the first object in the array and convert it
            if let firstObject = objectArray.first {
                resources = (firstObject["resources"]?.value as? [String]) ?? []
                matches = (firstObject["matches"]?.value as? [String]) ?? []
                extension_ids = (firstObject["extension_ids"]?.value as? [String]) ?? []
            } else {
                resources = []
                matches = nil
                extension_ids = nil
            }
        }
        // Try to decode as single object (manifest v3 object format)
        else {
            print("🔄 Attempting to decode web_accessible_resources as single object (v3)")
            let objContainer = try decoder.container(keyedBy: CodingKeys.self)
            resources = try objContainer.decodeIfPresent([String].self, forKey: .resources)
            matches = try objContainer.decodeIfPresent([String].self, forKey: .matches)
            extension_ids = try objContainer.decodeIfPresent([String].self, forKey: .extension_ids)
            print(
                "✅ Decoded web_accessible_resources as single object: resources=\(resources), matches=\(matches), extension_ids=\(extension_ids)"
            )
        }
    }

    /// Custom encoder to handle both formats
    public func encode(to encoder: Encoder) throws {
        // If only resources exist and no matches/extension_ids, encode as array (v2 format)
        if let resources, matches == nil, extension_ids == nil {
            var container = encoder.singleValueContainer()
            try container.encode(resources)
        } else {
            // Encode as object (v3 format)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(resources, forKey: .resources)
            try container.encodeIfPresent(matches, forKey: .matches)
            try container.encodeIfPresent(extension_ids, forKey: .extension_ids)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case resources
        case matches
        case extension_ids
    }
}

// MARK: - OptionsConfiguration

public struct OptionsConfiguration: Codable, Equatable {
    public let page: String?
    public let chrome_style: Bool?
    public let open_in_tab: Bool?
}

// MARK: - DevtoolsConfiguration

public struct DevtoolsConfiguration: Codable, Equatable {
    public let page: String
}

// MARK: - CommandConfiguration

public struct CommandConfiguration: Codable, Equatable {
    public let suggested_key: SuggestedKeyConfiguration?
    public let description: String?
}

// MARK: - SuggestedKeyConfiguration

public struct SuggestedKeyConfiguration: Codable, Equatable {
    public let `default`: String?
    public let mac: String?
    public let linux: String?
    public let windows: String?
    public let chromeos: String?
}

// MARK: - ExternallyConnectableConfiguration

public struct ExternallyConnectableConfiguration: Codable, Equatable {
    public let ids: [String]?
    public let matches: [String]?
    public let accepts_tls_channel_id: Bool?
}

// MARK: - DeclarativeNetRequestConfiguration

public struct DeclarativeNetRequestConfiguration: Codable, Equatable {
    public let rule_resources: [RuleResourceConfiguration]?
}

// MARK: - RuleResourceConfiguration

public struct RuleResourceConfiguration: Codable, Equatable {
    public let id: String
    public let enabled: Bool
    public let path: String
}

// MARK: - ApplicationsConfiguration

public struct ApplicationsConfiguration: Codable, Equatable {
    public let gecko: GeckoConfiguration?
}

// MARK: - GeckoConfiguration

public struct GeckoConfiguration: Codable, Equatable {
    public let id: String?
    public let strict_min_version: String?
    public let strict_max_version: String?
}

// MARK: - BrowserSpecificSettingsConfiguration

public struct BrowserSpecificSettingsConfiguration: Codable, Equatable {
    public let gecko: GeckoConfiguration?
}

// MARK: - Validation & Parsing

public extension ExtensionManifest {
    /// Validates the manifest according to the specified version
    func validate() throws {
        guard manifestVersion == 2 || manifestVersion == 3 else {
            throw ExtensionManifestError.unsupportedManifestVersion(manifestVersion)
        }

        guard !name.isEmpty else {
            throw ExtensionManifestError.missingRequiredField("name")
        }

        guard !version.isEmpty else {
            throw ExtensionManifestError.missingRequiredField("version")
        }

        // Validate manifest v3 specific requirements
        if manifestVersion == 3 {
            if let background, background.scripts != nil {
                throw ExtensionManifestError.invalidManifestV3("background.scripts not allowed in v3")
            }
        }
    }

    /// Parses manifest from JSON data
    static func parse(from data: Data) throws -> ExtensionManifest {
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(ExtensionManifest.self, from: data)
        try manifest.validate()
        return manifest
    }

    /// Checks if the extension has a specific permission
    func hasPermission(_ permission: String) -> Bool {
        permissions?.contains(permission) == true ||
            optionalPermissions?.contains(permission) == true ||
            hostPermissions?.contains(permission) == true
    }
}

// MARK: - Error Types

public enum ExtensionManifestError: Error, LocalizedError {
    case unsupportedManifestVersion(Int)
    case missingRequiredField(String)
    case invalidManifestV3(String)
    case parseError(Error)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedManifestVersion(version):
            "Unsupported manifest version: \(version)"
        case let .missingRequiredField(field):
            "Missing required field: \(field)"
        case let .invalidManifestV3(reason):
            "Invalid manifest v3: \(reason)"
        case let .parseError(error):
            "Parse error: \(error.localizedDescription)"
        }
    }
}

// MARK: - ExtensionManifest Parser

/// Parser for extension manifest files
public class ExtensionManifestParser {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ManifestParser")

    /// Parse manifest from JSON data
    /// - Parameter data: Raw JSON data from manifest.json
    /// - Returns: Parsed ExtensionManifest
    /// - Throws: ManifestParsingError if parsing fails
    public func parseManifest(from data: Data) throws -> ExtensionManifest {
        do {
            let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
            try validateManifest(manifest)
            return manifest
        } catch let decodingError as DecodingError {
            logger.error("Failed to decode manifest: \(decodingError)")
            throw ManifestParsingError.invalidFormat(decodingError.localizedDescription)
        } catch let validationError as ManifestParsingError {
            throw validationError
        } catch {
            logger.error("Unexpected error parsing manifest: \(error)")
            throw ManifestParsingError.unknown(error.localizedDescription)
        }
    }

    /// Parse manifest from file URL
    /// - Parameter url: URL to manifest.json file
    /// - Returns: Parsed ExtensionManifest
    /// - Throws: ManifestParsingError if parsing fails
    public func parseManifest(from url: URL) throws -> ExtensionManifest {
        do {
            let data = try Data(contentsOf: url)
            return try parseManifest(from: data)
        } catch {
            logger.error("Failed to read manifest from \(url.path): \(error)")
            throw ManifestParsingError.fileNotFound(url.path)
        }
    }

    /// Validate parsed manifest for required fields and consistency
    /// - Parameter manifest: Parsed manifest to validate
    /// - Throws: ManifestParsingError if validation fails
    private func validateManifest(_ manifest: ExtensionManifest) throws {
        // Validate manifest version
        guard [2, 3].contains(manifest.manifestVersion) else {
            throw ManifestParsingError.unsupportedManifestVersion(manifest.manifestVersion)
        }

        // Validate required fields
        guard !manifest.name.isEmpty else {
            throw ManifestParsingError.missingRequiredField("name")
        }

        guard !manifest.version.isEmpty else {
            throw ManifestParsingError.missingRequiredField("version")
        }

        // Validate version format (basic semver check)
        let versionRegex = try NSRegularExpression(pattern: #"^\d+(\.\d+)*$"#)
        let range = NSRange(location: 0, length: manifest.version.utf16.count)
        guard versionRegex.firstMatch(in: manifest.version, options: [], range: range) != nil else {
            throw ManifestParsingError.invalidVersion(manifest.version)
        }

        // Validate manifest v3 specific requirements
        if manifest.manifestVersion == 3 {
            try validateManifestV3(manifest)
        }

        // Validate permissions format
        if let permissions = manifest.permissions {
            try validatePermissions(permissions)
        }

        if let hostPermissions = manifest.hostPermissions {
            try validateHostPermissions(hostPermissions)
        }
    }

    /// Validate manifest v3 specific requirements
    /// - Parameter manifest: Manifest to validate
    /// - Throws: ManifestParsingError if validation fails
    private func validateManifestV3(_ manifest: ExtensionManifest) throws {
        // Check for deprecated background.persistent in v3
        if let background = manifest.background,
           background.persistent != nil {
            logger.warning("background.persistent is deprecated in manifest v3")
        }

        // Service worker should be used instead of background scripts in v3
        if let background = manifest.background,
           background.scripts != nil && background.service_worker == nil {
            logger.warning("background.scripts is deprecated in manifest v3, use service_worker instead")
        }

        // Check for deprecated browser_action/page_action in v3
        if manifest.browserAction != nil || manifest.pageAction != nil {
            logger.warning("browser_action and page_action are deprecated in manifest v3, use action instead")
        }
    }

    /// Validate permission strings
    /// - Parameter permissions: Array of permission strings
    /// - Throws: ManifestParsingError if validation fails
    private func validatePermissions(_ permissions: [String]) throws {
        let validPermissions = Set([
            "activeTab", "alarms", "background", "bookmarks", "clipboardRead", "clipboardWrite",
            "contextMenus", "cookies", "debugger", "declarativeContent", "declarativeNetRequest",
            "declarativeNetRequestFeedback", "desktopCapture", "downloads", "enterprise.deviceAttributes",
            "enterprise.hardwarePlatform", "enterprise.networkingAttributes", "enterprise.platformKeys",
            "experimental", "fileBrowserHandler", "fileSystemProvider", "fontSettings", "gcm",
            "geolocation", "history", "identity", "idle", "loginState", "management", "nativeMessaging",
            "notifications", "offscreen", "pageCapture", "platformKeys", "power", "printerProvider",
            "privacy", "proxy", "scripting", "search", "sessions", "sidePanel", "storage",
            "system.cpu", "system.display", "system.memory", "system.storage", "tabCapture",
            "tabs", "topSites", "tts", "ttsEngine", "unlimitedStorage", "vpnProvider",
            "wallpaper", "webNavigation", "webRequest", "webRequestBlocking"
        ])

        for permission in permissions {
            // Skip URL patterns and special permissions
            if permission.contains("://") || permission.hasPrefix("chrome://") || permission.hasPrefix("*") {
                continue
            }

            if !validPermissions.contains(permission) {
                logger.warning("Unknown permission: \(permission)")
            }
        }
    }

    /// Validate host permission patterns
    /// - Parameter hostPermissions: Array of host permission patterns
    /// - Throws: ManifestParsingError if validation fails
    private func validateHostPermissions(_ hostPermissions: [String]) throws {
        for pattern in hostPermissions {
            guard isValidURLPattern(pattern) else {
                throw ManifestParsingError.invalidHostPermission(pattern)
            }
        }
    }

    /// Check if a URL pattern is valid
    /// - Parameter pattern: URL pattern to validate
    /// - Returns: True if pattern is valid
    private func isValidURLPattern(_ pattern: String) -> Bool {
        // Basic URL pattern validation
        if pattern == "<all_urls>" { return true }
        if pattern.hasPrefix("*://") { return true }
        if pattern.hasPrefix("http://") || pattern.hasPrefix("https://") { return true }
        if pattern.hasPrefix("file://") { return true }
        if pattern.hasPrefix("ftp://") { return true }

        return false
    }
}

// MARK: - Error Types

/// Errors that can occur during manifest parsing
public enum ManifestParsingError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidFormat(String)
    case missingRequiredField(String)
    case unsupportedManifestVersion(Int)
    case invalidVersion(String)
    case invalidHostPermission(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "Manifest file not found at path: \(path)"
        case let .invalidFormat(details):
            "Invalid manifest format: \(details)"
        case let .missingRequiredField(field):
            "Missing required field: \(field)"
        case let .unsupportedManifestVersion(version):
            "Unsupported manifest version: \(version)"
        case let .invalidVersion(version):
            "Invalid version format: \(version)"
        case let .invalidHostPermission(pattern):
            "Invalid host permission pattern: \(pattern)"
        case let .unknown(details):
            "Unknown error: \(details)"
        }
    }
}

// MARK: - AnyCodable Helper for Debugging

private struct AnyCodable: Codable {
    let value: Any

    init(_ value: (some Any)?) {
        self.value = value ?? ()
    }
}

extension AnyCodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = ()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Could not decode unknown type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is ():
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "Could not encode unknown type"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}
