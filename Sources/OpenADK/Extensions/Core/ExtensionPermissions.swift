//
//  ExtensionPermissions.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Combine
import Foundation

// MARK: - ExtensionPermission

/// Represents a permission that an extension can request
public enum ExtensionPermission: String, CaseIterable, Codable, Hashable, Equatable {
    // MARK: - API Permissions

    case activeTab
    case alarms
    case background
    case bookmarks
    case browsingData
    case commands
    case contextMenus
    case cookies
    case declarativeContent
    case declarativeNetRequest
    case downloads
    case fontSettings
    case gcm
    case history
    case identity
    case idle
    case management
    case notifications
    case pageCapture
    case privacy
    case proxy
    case runtime
    case scripting
    case search
    case sessions
    case storage
    case system
    case tabs
    case topSites
    case tts
    case ttsEngine
    case unlimitedStorage
    case webNavigation
    case webRequest
    case webRequestBlocking
    case windows

    // MARK: - Host Permissions (special cases)

    case allUrls = "<all_urls>"
    case hostPattern = "host_pattern" // Placeholder for dynamic host patterns

    /// Returns the category of this permission
    public var category: PermissionCategory {
        switch self {
        case .activeTab,
             .allUrls,
             .hostPattern:
            .hostAccess
        case .webRequest,
             .webRequestBlocking,
             .declarativeNetRequest:
            .networkInterception
        case .bookmarks,
             .history,
             .tabs,
             .windows:
            .browserData
        case .storage,
             .unlimitedStorage:
            .dataStorage
        case .identity,
             .privacy:
            .privacy
        default:
            .api
        }
    }

    /// Returns the risk level of this permission
    public var riskLevel: PermissionRiskLevel {
        switch self {
        case .allUrls,
             .webRequestBlocking,
             .declarativeNetRequest:
            .high
        case .webRequest,
             .hostPattern,
             .tabs,
             .bookmarks,
             .history:
            .medium
        case .activeTab,
             .storage,
             .alarms,
             .notifications:
            .low
        default:
            .low
        }
    }

    /// Returns a user-friendly description of what this permission allows
    public var userDescription: String {
        switch self {
        case .activeTab:
            "Access the currently active tab"
        case .allUrls:
            "Access all websites"
        case .tabs:
            "Read and modify browser tabs"
        case .storage:
            "Store data locally"
        case .webRequest:
            "Monitor network requests"
        case .webRequestBlocking:
            "Block or modify network requests"
        case .bookmarks:
            "Read and modify bookmarks"
        case .history:
            "Read and modify browsing history"
        case .cookies:
            "Read and modify cookies"
        case .notifications:
            "Display notifications"
        case .contextMenus:
            "Add items to context menus"
        case .downloads:
            "Manage downloads"
        case .identity:
            "Access user identity and authentication"
        case .privacy:
            "Access privacy settings"
        case .proxy:
            "Control proxy settings"
        case .declarativeNetRequest:
            "Block network requests using rules"
        default:
            "Access \(rawValue) API"
        }
    }
}

// MARK: - PermissionCategory

/// Categories of permissions for grouping in UI
public enum PermissionCategory: String, CaseIterable {
    case api = "API Access"
    case hostAccess = "Website Access"
    case networkInterception = "Network Control"
    case browserData = "Browser Data"
    case dataStorage = "Data Storage"
    case privacy = "Privacy & Security"
}

// MARK: - PermissionRiskLevel

/// Risk levels for permissions to help users understand security implications
public enum PermissionRiskLevel: String, CaseIterable {
    case low = "Low Risk"
    case medium = "Medium Risk"
    case high = "High Risk"
}

// MARK: - ExtensionPermissionManager

/// Manages extension permissions, including user consent and runtime checking
public class ExtensionPermissionManager: NSObject, ObservableObject {
    @Published public var grantedPermissions: Set<String> = []
    @Published public var pendingRequests: [PermissionRequest] = []

    private let userDefaults = UserDefaults.standard
    private let permissionsKey = "ExtensionPermissions"

    public override init() {
        super.init()
        loadPersistedPermissions()
    }

    /// Requests permissions for an extension, showing user consent UI if needed
    @MainActor
    public func requestPermissions(
        _ permissions: [String],
        for extensionId: String,
        extensionName: String
    ) async -> PermissionRequestResult {
        let newPermissions = Set(permissions).subtracting(grantedPermissions)

        guard !newPermissions.isEmpty else {
            return .granted
        }

        let request = PermissionRequest(
            id: UUID().uuidString,
            extensionId: extensionId,
            extensionName: extensionName,
            permissions: Array(newPermissions)
        )

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.pendingRequests.append(request)

                // TODO: Implementation, this would show a permission dialog
                // For now, we'll auto-approve low-risk permissions
                let riskLevels = newPermissions.compactMap { permString in
                    ExtensionPermission(rawValue: permString)?.riskLevel
                }

                let hasHighRisk = riskLevels.contains(.high)

                if hasHighRisk {
                    // For now, auto-approve high-risk permissions in development mode
                    // TODO: Show proper user consent dialog
                    print("⚠️ Auto-approving high-risk permissions for development: \(Array(newPermissions))")
                    self.grantPermissions(Array(newPermissions), for: extensionId)
                    continuation.resume(returning: .granted)
                } else {
                    self.grantPermissions(Array(newPermissions), for: extensionId)
                    continuation.resume(returning: .granted)
                }

                self.pendingRequests.removeAll { $0.id == request.id }
            }
        }
    }

    /// Grants permissions for an extension without user prompt (internal use)
    public func grantPermissions(_ permissions: [String], for extensionId: String) {
        let key = "\(permissionsKey)_\(extensionId)"
        var currentPermissions = Set(userDefaults.stringArray(forKey: key) ?? [])
        currentPermissions.formUnion(permissions)

        userDefaults.set(Array(currentPermissions), forKey: key)
        grantedPermissions.formUnion(permissions)
    }

    /// Revokes permissions for an extension
    public func revokePermissions(_ permissions: [String], for extensionId: String) {
        let key = "\(permissionsKey)_\(extensionId)"
        var currentPermissions = Set(userDefaults.stringArray(forKey: key) ?? [])
        currentPermissions.subtract(permissions)

        userDefaults.set(Array(currentPermissions), forKey: key)
        grantedPermissions.subtract(permissions)
    }

    /// Checks if an extension has a specific permission
    public func hasPermission(_ permission: String, for extensionId: String) -> Bool {
        let key = "\(permissionsKey)_\(extensionId)"
        let permissions = Set(userDefaults.stringArray(forKey: key) ?? [])
        return permissions.contains(permission)
    }

    /// Gets all granted permissions for an extension
    public func getPermissions(for extensionId: String) -> Set<String> {
        let key = "\(permissionsKey)_\(extensionId)"
        return Set(userDefaults.stringArray(forKey: key) ?? [])
    }

    /// Removes all permissions for an extension (used during uninstall)
    public func removeAllPermissions(for extensionId: String) {
        let key = "\(permissionsKey)_\(extensionId)"
        userDefaults.removeObject(forKey: key)

        // Update the global granted permissions set
        loadPersistedPermissions()
    }

    /// Validates if a host pattern matches a URL
    public func validateHostPermission(_ hostPattern: String, for url: URL) -> Bool {
        if hostPattern == "<all_urls>" {
            return true
        }

        // TODO: Implementation, use proper URL pattern matching
        if hostPattern.hasPrefix("*://") {
            let pattern = String(hostPattern.dropFirst(4))
            return url.host?.hasSuffix(pattern) == true
        }

        if hostPattern.hasPrefix("https://") {
            return url.absoluteString.hasPrefix(hostPattern) ||
                url.host == URL(string: hostPattern)?.host
        }

        if hostPattern.hasPrefix("http://") {
            return url.absoluteString.hasPrefix(hostPattern) ||
                url.host == URL(string: hostPattern)?.host
        }

        return false
    }

    private func loadPersistedPermissions() {
        var allPermissions = Set<String>()

        // Load permissions from all extension keys
        let allKeys = userDefaults.dictionaryRepresentation().keys
        let permissionKeys = allKeys.filter { $0.hasPrefix(permissionsKey) }

        for key in permissionKeys {
            if let permissions = userDefaults.stringArray(forKey: key) {
                allPermissions.formUnion(permissions)
            }
        }

        DispatchQueue.main.async {
            self.grantedPermissions = allPermissions
        }
    }
}

// MARK: - PermissionRequest

/// Represents a permission request awaiting user approval
public struct PermissionRequest: Identifiable, Equatable {
    public let id: String
    public let extensionId: String
    public let extensionName: String
    public let permissions: [String]
    public let timestamp: Date

    public init(id: String, extensionId: String, extensionName: String, permissions: [String]) {
        self.id = id
        self.extensionId = extensionId
        self.extensionName = extensionName
        self.permissions = permissions
        timestamp = Date()
    }

    public static func == (lhs: PermissionRequest, rhs: PermissionRequest) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - PermissionRequestResult

/// Result of a permission request
public enum PermissionRequestResult {
    case granted
    case userDenied
    case systemDenied(String)
}

/// Utility functions for permission management
public extension ExtensionPermissionManager {
    /// Groups permissions by category for UI display
    func groupPermissionsByCategory(_ permissions: [String]) -> [PermissionCategory: [ExtensionPermission]] {
        var grouped: [PermissionCategory: [ExtensionPermission]] = [:]

        for permissionString in permissions {
            if let permission = ExtensionPermission(rawValue: permissionString) {
                let category = permission.category
                if grouped[category] == nil {
                    grouped[category] = []
                }
                grouped[category]?.append(permission)
            }
        }

        return grouped
    }

    /// Calculates overall risk level for a set of permissions
    func calculateRiskLevel(for permissions: [String]) -> PermissionRiskLevel {
        let riskLevels = permissions.compactMap { permString in
            ExtensionPermission(rawValue: permString)?.riskLevel
        }

        if riskLevels.contains(.high) {
            return .high
        } else if riskLevels.contains(.medium) {
            return .medium
        } else {
            return .low
        }
    }

    /// Gets user-friendly descriptions for permissions
    func getPermissionDescriptions(_ permissions: [String]) -> [String: String] {
        var descriptions: [String: String] = [:]

        for permissionString in permissions {
            if let permission = ExtensionPermission(rawValue: permissionString) {
                descriptions[permissionString] = permission.userDescription
            } else {
                descriptions[permissionString] = "Access \(permissionString)"
            }
        }

        return descriptions
    }
}
