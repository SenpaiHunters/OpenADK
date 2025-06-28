//
//  ExtensionAPICapabilities.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation

/// Extension API implementation tracking and capabilities
public enum ExtensionAPICapabilities {
    /// Manifest versions supported by OpenADK
    public enum ManifestVersion: Int, CaseIterable {
        case v2 = 2
        case v3 = 3
    }

    /// Extension API implementation status
    public enum APIStatus {
        case implemented
        case partial
        case planned
        case notSupported
    }

    /// Chrome Extension APIs and their implementation status
    public static let chromeAPIs: [String: APIStatus] = [
        // Core APIs (High Priority)
        "chrome.runtime": .implemented,
        "chrome.tabs": .implemented,
        "chrome.storage": .implemented,
        "chrome.webRequest": .implemented,
        "chrome.contextMenus": .implemented,

        // Medium Priority
        "chrome.bookmarks": .implemented,
        "chrome.history": .implemented,
        "chrome.cookies": .implemented,
        "chrome.notifications": .implemented,
        "chrome.downloads": .implemented,
        "chrome.alarms": .implemented,

        // Browser Actions
        "chrome.browserAction": .planned, // Manifest v2
        "chrome.action": .planned, // Manifest v3
        "chrome.pageAction": .planned,

        // Advanced APIs
        "chrome.commands": .implemented,
        "chrome.contentSettings": .planned,
        "chrome.declarativeContent": .planned,
        "chrome.scripting": .implemented, // Manifest v3
        "chrome.offscreen": .planned, // Manifest v3

        // System APIs
        "chrome.system.cpu": .planned,
        "chrome.system.memory": .planned,
        "chrome.system.storage": .planned,
        "chrome.power": .planned,
        "chrome.idle": .planned,

        // Privacy & Security
        "chrome.privacy": .planned,
        "chrome.proxy": .planned,
        "chrome.identity": .planned,

        // Developer Tools
        "chrome.devtools": .notSupported,
        "chrome.desktopCapture": .notSupported,

        // Enterprise
        "chrome.enterprise": .notSupported,

        // File System
        "chrome.fileSystemProvider": .notSupported,

        // Communication
        "chrome.gcm": .notSupported,
        "chrome.input": .planned,

        // Browser Integration
        "chrome.management": .planned,
        "chrome.omnibox": .planned,
        "chrome.pageCapture": .planned,
        "chrome.sessions": .planned,
        "chrome.topSites": .planned,
        "chrome.webNavigation": .planned,

        // UI
        "chrome.fontSettings": .planned,
        "chrome.tts": .planned,
        "chrome.sidePanel": .planned,
        "chrome.userScripts": .planned
    ]

    /// Firefox WebExtension APIs and their implementation status
    public static let firefoxAPIs: [String: APIStatus] = [
        // Core APIs
        "browser.runtime": .planned,
        "browser.tabs": .planned,
        "browser.storage": .planned,
        "browser.webRequest": .planned,
        "browser.contextMenus": .planned,

        // Standard APIs
        "browser.bookmarks": .planned,
        "browser.history": .planned,
        "browser.cookies": .planned,
        "browser.notifications": .planned,
        "browser.downloads": .planned,
        "browser.alarms": .planned,

        // Browser Actions
        "browser.browserAction": .planned,
        "browser.pageAction": .planned,
        "browser.action": .planned,

        // Firefox-specific
        "browser.contentScripts": .planned,
        "browser.dns": .planned,
        "browser.find": .planned,
        "browser.i18n": .planned,
        "browser.identity": .planned,
        "browser.idle": .planned,
        "browser.management": .planned,
        "browser.menus": .planned,
        "browser.omnibox": .planned,
        "browser.permissions": .planned,
        "browser.privacy": .planned,
        "browser.proxy": .planned,
        "browser.search": .planned,
        "browser.sessions": .planned,
        "browser.theme": .planned,
        "browser.topSites": .planned,
        "browser.webNavigation": .planned,
        "browser.scripting": .planned,
        "browser.declarativeNetRequest": .planned,
        "browser.userScripts": .planned
    ]

    /// Extension runtime features and their implementation status
    public static let features: [String: APIStatus] = [
        "contentScriptInjection": .implemented,
        "backgroundScripts": .implemented,
        "serviceWorkers": .partial,
        "manifestV2": .implemented,
        "manifestV3": .implemented,
        "permissionSystem": .implemented,
        "messageRouting": .implemented,
        "webStore": .implemented,
        "i18nSupport": .implemented,
        "iconManagement": .implemented,

        // Planned features
        "nativeMessaging": .planned,
        "fileSystemAccess": .planned,
        "clipboardAccess": .planned,
        "geolocationAccess": .planned,
        "popupWindows": .planned,
        "optionsPages": .planned,
        "contentSecurityPolicy": .planned,
        "crossOriginRequests": .planned
    ]

    /// Get implementation status for a specific API
    /// - Parameter apiName: Name of the API (e.g., "chrome.runtime")
    /// - Returns: Implementation status
    public static func getAPIStatus(_ apiName: String) -> APIStatus {
        chromeAPIs[apiName] ?? firefoxAPIs[apiName] ?? .notSupported
    }

    /// Get all implemented APIs
    /// - Returns: List of implemented API names
    public static func getImplementedAPIs() -> [String] {
        let allAPIs = [chromeAPIs, firefoxAPIs]
        return allAPIs.flatMap { apis in
            apis.compactMap { key, value in
                value == .implemented ? key : nil
            }
        }
    }

    /// Get implementation progress statistics
    /// - Returns: Dictionary with implementation statistics
    public static func getImplementationStats() -> [String: Any] {
        let chromeStats = calculateStats(for: chromeAPIs)
        let firefoxStats = calculateStats(for: firefoxAPIs)
        let featureStats = calculateStats(for: features)

        return [
            "chrome": chromeStats,
            "firefox": firefoxStats,
            "features": featureStats
        ]
    }

    /// Calculate statistics for a given API collection
    /// - Parameter apis: Dictionary of APIs and their statuses
    /// - Returns: Statistics dictionary
    private static func calculateStats(for apis: [String: APIStatus]) -> [String: Any] {
        let total = apis.count
        let implemented = apis.values.count { $0 == .implemented }
        let partial = apis.values.count { $0 == .partial }
        let progress = total > 0 ? Double(implemented + partial) / Double(total) : 0.0

        return [
            "total": total,
            "implemented": implemented,
            "partial": partial,
            "progress": progress
        ]
    }

    /// Check if extension platform is supported
    /// - Parameter platform: Platform to check
    /// - Returns: Whether platform is supported
    /// TODO: Support webkit + web store extensions (not just chrome)
    public static func isSupported(platform: String) -> Bool {
        ["chrome", "firefox", "webextensions"].contains(platform.lowercased())
    }

    /// Get supported manifest versions
    /// - Returns: Set of supported manifest versions
    public static func getSupportedManifestVersions() -> Set<Int> {
        Set(ManifestVersion.allCases.map(\.rawValue))
    }
}
