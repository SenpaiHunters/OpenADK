//
//  ChromeRuntime.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import JavaScriptCore
import OSLog
import WebKit

// MARK: - ChromeRuntime

/// Implementation of chrome.runtime API
@MainActor
public class ChromeRuntime {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeRuntime")

    /// Extension this runtime belongs to
    public let extensionId: String

    /// Extension manifest
    public let manifest: ExtensionManifest

    /// Associated extension runtime
    public weak var runtime: ExtensionRuntime?

    /// Message event listeners
    private var messageListeners: [(ChromeMessage, ChromeMessageSender, @escaping (Any?) -> ()) -> ()] = []

    /// Connect event listeners
    private var connectListeners: [(ChromePort) -> ()] = []

    /// Install event listeners
    private var installListeners: [(ChromeInstallDetails) -> ()] = []

    /// Startup event listeners
    private var startupListeners: [() -> ()] = []

    /// Update available event listeners
    private var updateAvailableListeners: [(ChromeUpdateDetails) -> ()] = []

    /// Initialize Chrome runtime API
    /// - Parameters:
    ///   - extensionId: Extension identifier
    ///   - manifest: Extension manifest
    ///   - runtime: Extension runtime instance
    public init(extensionId: String, manifest: ExtensionManifest, runtime: ExtensionRuntime?) {
        self.extensionId = extensionId
        self.manifest = manifest
        self.runtime = runtime
        logger.info("🚀 Chrome runtime initialized for extension: \(extensionId)")
    }

    // MARK: - Properties

    /// Extension ID
    public var id: String { extensionId }

    /// Last error that occurred
    public var lastError: ChromeRuntimeError?

    /// Get extension manifest
    public func getManifest() -> ChromeManifest {
        ChromeManifest(from: manifest)
    }

    /// Get extension URL
    /// - Parameter path: Path within extension
    /// - Returns: Extension URL
    public func getURL(_ path: String) -> String {
        guard let extensionid = ExtensionRuntime.shared.loadedExtensions[extensionId] else {
            return ""
        }
        return extensionid.url.appendingPathComponent(path).absoluteString
    }

    /// Get platform info
    /// - Parameter callback: Callback with platform info
    public func getPlatformInfo(_ callback: @escaping (ChromePlatformInfo) -> ()) {
        let platformInfo = ChromePlatformInfo(
            os: "mac",
            arch: "x86-64", // or "arm64" depending on system
            nacl_arch: "x86-64"
        )
        callback(platformInfo)
    }

    /// Get package directory entry
    /// - Parameter callback: Callback with directory entry
    public func getPackageDirectoryEntry(_ callback: @escaping (Any?) -> ()) {
        // Not supported in this implementation
        callback(nil)
    }

    // MARK: - Messaging

    /// Send message to extension
    /// - Parameters:
    ///   - extensionId: Target extension ID (optional)
    ///   - message: Message to send
    ///   - options: Send options
    ///   - responseCallback: Response callback
    public func sendMessage(
        extensionId targetExtensionId: String? = nil,
        message: Any,
        options: ChromeMessageOptions? = nil,
        responseCallback: ((Any?) -> ())? = nil
    ) {
        let targetId = targetExtensionId ?? extensionId

        // Convert message to dictionary
        var messageDict: [String: Any] = [:]
        if let dict = message as? [String: Any] {
            messageDict = dict
        } else {
            messageDict["data"] = message
        }

        // Send through extension runtime
        ExtensionRuntime.shared.sendMessageToExtension(
            messageDict,
            extensionId: targetId
        ) { response in
            responseCallback?(response)
        }

        logger.debug("📨 Sent message to extension \(targetId)")
    }

    /// Send message to content script
    /// - Parameters:
    ///   - tabId: Target tab ID
    ///   - message: Message to send
    ///   - options: Send options
    ///   - responseCallback: Response callback
    public func sendMessageToTab(
        tabId: Int,
        message: Any,
        options: ChromeMessageOptions? = nil,
        responseCallback: ((Any?) -> ())? = nil
    ) {
        // Get tab WebView and send message
        // This would integrate with the tab management system
        logger.debug("📨 Send message to tab \(tabId) - not implemented yet")
        responseCallback?(nil)
    }

    /// Connect to extension
    /// - Parameters:
    ///   - extensionId: Target extension ID (optional)
    ///   - connectInfo: Connection info
    /// - Returns: Port for communication
    public func connect(
        extensionId targetExtensionId: String? = nil,
        connectInfo: ChromeConnectInfo? = nil
    ) -> ChromePort {
        let targetId = targetExtensionId ?? extensionId
        let port = ChromePort(
            name: connectInfo?.name ?? "",
            sender: ChromeMessageSender(
                id: extensionId,
                url: nil,
                tlsChannelId: nil
            )
        )

        logger.debug("🔌 Connected to extension \(targetId)")

        // Trigger connect event on target extension
        triggerConnectEvent(port)

        return port
    }

    /// Connect to content script
    /// - Parameters:
    ///   - tabId: Target tab ID
    ///   - connectInfo: Connection info
    /// - Returns: Port for communication
    public func connectToTab(
        tabId: Int,
        connectInfo: ChromeConnectInfo? = nil
    ) -> ChromePort {
        let port = ChromePort(
            name: connectInfo?.name ?? "",
            sender: ChromeMessageSender(
                id: extensionId,
                url: nil,
                tlsChannelId: nil
            )
        )

        logger.debug("🔌 Connected to tab \(tabId)")

        return port
    }

    // MARK: - Event Listeners

    /// Add message listener
    /// - Parameter listener: Message listener callback
    public func addMessageListener(
        _ listener: @escaping (ChromeMessage, ChromeMessageSender, @escaping (Any?) -> ()) -> ()
    ) {
        messageListeners.append(listener)
        logger.debug("📝 Added message listener")
    }

    /// Remove message listener
    /// - Parameter listener: Message listener to remove
    public func removeMessageListener(
        _ listener: @escaping (ChromeMessage, ChromeMessageSender, @escaping (Any?) -> ()) -> ()
    ) {
        // TODO: Implementation, we'd need a way to identify and remove specific listeners
        logger.debug("🗑️ Remove message listener - not fully implemented")
    }

    /// Add connect listener
    /// - Parameter listener: Connect listener callback
    public func addConnectListener(_ listener: @escaping (ChromePort) -> ()) {
        connectListeners.append(listener)
        logger.debug("📝 Added connect listener")
    }

    /// Remove connect listener
    /// - Parameter listener: Connect listener to remove
    public func removeConnectListener(_ listener: @escaping (ChromePort) -> ()) {
        logger.debug("🗑️ Remove connect listener - not fully implemented")
    }

    /// Add install listener
    /// - Parameter listener: Install listener callback
    public func addInstallListener(_ listener: @escaping (ChromeInstallDetails) -> ()) {
        installListeners.append(listener)
        logger.debug("📝 Added install listener")
    }

    /// Add startup listener
    /// - Parameter listener: Startup listener callback
    public func addStartupListener(_ listener: @escaping () -> ()) {
        startupListeners.append(listener)
        logger.debug("📝 Added startup listener")
    }

    /// Add update available listener
    /// - Parameter listener: Update available listener callback
    public func addUpdateAvailableListener(_ listener: @escaping (ChromeUpdateDetails) -> ()) {
        updateAvailableListeners.append(listener)
        logger.debug("📝 Added update available listener")
    }

    // MARK: - Event Triggering

    /// Trigger message event
    /// - Parameters:
    ///   - message: Message received
    ///   - sender: Message sender
    ///   - sendResponse: Response callback
    public func triggerMessageEvent(
        _ message: ChromeMessage,
        sender: ChromeMessageSender,
        sendResponse: @escaping (Any?) -> ()
    ) {
        for listener in messageListeners {
            listener(message, sender, sendResponse)
        }
    }

    /// Trigger connect event
    /// - Parameter port: Connected port
    private func triggerConnectEvent(_ port: ChromePort) {
        for listener in connectListeners {
            listener(port)
        }
    }

    /// Trigger install event
    /// - Parameter details: Install details
    public func triggerInstallEvent(_ details: ChromeInstallDetails) {
        for listener in installListeners {
            listener(details)
        }
    }

    /// Trigger startup event
    public func triggerStartupEvent() {
        for listener in startupListeners {
            listener()
        }
    }

    /// Trigger update available event
    /// - Parameter details: Update details
    public func triggerUpdateAvailableEvent(_ details: ChromeUpdateDetails) {
        for listener in updateAvailableListeners {
            listener(details)
        }
    }

    // MARK: - Extension Management

    /// Request update check
    /// - Parameter callback: Callback with update status
    public func requestUpdateCheck(_ callback: @escaping (ChromeRequestUpdateCheckStatus, ChromeUpdateDetails?) -> ()) {
        // Implement update checking logic
        callback(.no_update, nil)
        logger.debug("🔄 Update check requested")
    }

    /// Restart extension
    public func restart() {
        ExtensionRuntime.shared.uninstallExtension(extensionId)
        logger.info("🔄 Extension restart requested")
    }

    /// Reload extension
    public func reload() {
        restart()
    }

    /// Set uninstall URL
    /// - Parameters:
    ///   - url: Uninstall URL
    ///   - callback: Completion callback
    public func setUninstallURL(_ url: String, callback: (() -> ())? = nil) {
        // Store uninstall URL for later use
        logger.debug("🔗 Set uninstall URL: \(url)")
        callback?()
    }

    /// Open options page
    /// Implements chrome.runtime.openOptionsPage() API
    /// This method opens the extension's options page in a new tab if one is configured.
    /// It supports both manifest v2 (options_page) and v3 (options_ui.page) formats.
    /// - Parameter callback: Completion callback
    public func openOptionsPage(_ callback: (() -> ())? = nil) {
        logger.info("⚙️ chrome.runtime.openOptionsPage() called for extension: \(self.extensionId)")

        // Check for duplicate calls
        let currentTime = Date().timeIntervalSince1970
        let deduplicationKey = "openOptionsPage_\(extensionId)"

        if let lastCallTime = UserDefaults.standard.object(forKey: deduplicationKey) as? TimeInterval,
           currentTime - lastCallTime < 1.0 {
            logger.info("🔄 Skipping duplicate openOptionsPage call from Chrome API for \(self.extensionId)")
            callback?()
            return
        }

        UserDefaults.standard.set(currentTime, forKey: deduplicationKey)

        // Post notification to open settings - mark as from Chrome API to prevent duplication
        DispatchQueue.main.async { [extensionId] in
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenExtensionSettings"),
                object: nil,
                userInfo: [
                    "extensionId": extensionId,
                    "source": "chrome-api",
                    "handledByRuntime": true
                ]
            )
        }

        callback?()
    }

    // MARK: - Event Objects (for JavaScript injection)

    /// chrome.runtime.onMessage event object
    public var onMessage: ChromeRuntimeOnMessageEvent {
        ChromeRuntimeOnMessageEvent(runtime: self)
    }

    /// chrome.runtime.onConnect event object
    public var onConnect: ChromeRuntimeOnConnectEvent {
        ChromeRuntimeOnConnectEvent(runtime: self)
    }

    /// chrome.runtime.onInstalled event object
    public var onInstalled: ChromeRuntimeOnInstalledEvent {
        ChromeRuntimeOnInstalledEvent(runtime: self)
    }

    /// chrome.runtime.onStartup event object
    public var onStartup: ChromeRuntimeOnStartupEvent {
        ChromeRuntimeOnStartupEvent(runtime: self)
    }
}

// MARK: - Supporting Types

/// Chrome message type
public typealias ChromeMessage = [String: Any]

// MARK: - ChromeMessageSender

/// Chrome message sender
public struct ChromeMessageSender {
    public let id: String?
    public let url: String?
    public let tlsChannelId: String?

    public init(id: String?, url: String?, tlsChannelId: String?) {
        self.id = id
        self.url = url
        self.tlsChannelId = tlsChannelId
    }
}

// MARK: - ChromePort

/// Chrome port for long-lived connections
public class ChromePort {
    public let name: String
    public let sender: ChromeMessageSender?

    private var messageListeners: [(Any) -> ()] = []
    private var disconnectListeners: [() -> ()] = []

    public init(name: String, sender: ChromeMessageSender?) {
        self.name = name
        self.sender = sender
    }

    /// Post message through port
    /// - Parameter message: Message to send
    public func postMessage(_ message: Any) {
        // Send message through port
    }

    /// Disconnect port
    public func disconnect() {
        for listener in disconnectListeners {
            listener()
        }
    }

    /// Add message listener
    /// - Parameter listener: Message listener
    public func addMessageListener(_ listener: @escaping (Any) -> ()) {
        messageListeners.append(listener)
    }

    /// Add disconnect listener
    /// - Parameter listener: Disconnect listener
    public func addDisconnectListener(_ listener: @escaping () -> ()) {
        disconnectListeners.append(listener)
    }
}

// MARK: - ChromeMessageOptions

/// Chrome message options
public struct ChromeMessageOptions {
    public let includeTlsChannelId: Bool?

    public init(includeTlsChannelId: Bool? = nil) {
        self.includeTlsChannelId = includeTlsChannelId
    }
}

// MARK: - ChromeConnectInfo

/// Chrome connect info
public struct ChromeConnectInfo {
    public let name: String?
    public let includeTlsChannelId: Bool?

    public init(name: String? = nil, includeTlsChannelId: Bool? = nil) {
        self.name = name
        self.includeTlsChannelId = includeTlsChannelId
    }
}

// MARK: - ChromePlatformInfo

/// Chrome platform info
public struct ChromePlatformInfo {
    public let os: String
    public let arch: String
    public let nacl_arch: String

    public init(os: String, arch: String, nacl_arch: String) {
        self.os = os
        self.arch = arch
        self.nacl_arch = nacl_arch
    }
}

// MARK: - ChromeInstallDetails

/// Chrome install details
public struct ChromeInstallDetails {
    public let reason: ChromeInstallReason
    public let previousVersion: String?

    public init(reason: ChromeInstallReason, previousVersion: String? = nil) {
        self.reason = reason
        self.previousVersion = previousVersion
    }
}

// MARK: - ChromeInstallReason

/// Chrome install reason
public enum ChromeInstallReason: String {
    case install
    case update
    case chrome_update
    case shared_module_update
}

// MARK: - ChromeUpdateDetails

/// Chrome update details
public struct ChromeUpdateDetails {
    public let version: String

    public init(version: String) {
        self.version = version
    }
}

// MARK: - ChromeRequestUpdateCheckStatus

/// Chrome update check status
public enum ChromeRequestUpdateCheckStatus: String {
    case throttled
    case no_update
    case update_available
}

// MARK: - ChromeRuntimeError

/// Chrome runtime error
public struct ChromeRuntimeError {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

// MARK: - ChromeManifest

/// Chrome manifest wrapper
public struct ChromeManifest {
    public let name: String
    public let version: String
    public let manifest_version: Int
    public let description: String?

    public init(from extensionManifest: ExtensionManifest) {
        name = extensionManifest.name
        version = extensionManifest.version
        manifest_version = extensionManifest.manifestVersion
        description = extensionManifest.description
    }
}

// MARK: - ChromeRuntimeOnMessageEvent

/// chrome.runtime.onMessage event object
public class ChromeRuntimeOnMessageEvent {
    private weak var runtime: ChromeRuntime?

    public init(runtime: ChromeRuntime) {
        self.runtime = runtime
    }

    /// Add listener for message events
    /// - Parameter listener: Message listener function
    @MainActor public func addListener(_ listener: @escaping (
        ChromeMessage,
        ChromeMessageSender,
        @escaping (Any?) -> ()
    ) -> ()) {
        runtime?.addMessageListener(listener)
    }

    /// Remove listener for message events
    /// - Parameter listener: Message listener function to remove
    @MainActor public func removeListener(_ listener: @escaping (
        ChromeMessage,
        ChromeMessageSender,
        @escaping (Any?) -> ()
    ) -> ()) {
        runtime?.removeMessageListener(listener)
    }

    /// Check if listener exists
    /// - Parameter listener: Message listener function to check
    /// - Returns: Whether listener exists
    public func hasListener(_ listener: @escaping (ChromeMessage, ChromeMessageSender, @escaping (Any?) -> ()) -> ())
    -> Bool {
        // TODO: Implement proper listener tracking
        false
    }
}

// MARK: - ChromeRuntimeOnConnectEvent

/// chrome.runtime.onConnect event object
public class ChromeRuntimeOnConnectEvent {
    private weak var runtime: ChromeRuntime?

    public init(runtime: ChromeRuntime) {
        self.runtime = runtime
    }

    /// Add listener for connect events
    /// - Parameter listener: Connect listener function
    @MainActor public func addListener(_ listener: @escaping (ChromePort) -> ()) {
        runtime?.addConnectListener(listener)
    }

    /// Remove listener for connect events
    /// - Parameter listener: Connect listener function to remove
    @MainActor public func removeListener(_ listener: @escaping (ChromePort) -> ()) {
        runtime?.removeConnectListener(listener)
    }

    /// Check if listener exists
    /// - Parameter listener: Connect listener function to check
    /// - Returns: Whether listener exists
    public func hasListener(_ listener: @escaping (ChromePort) -> ()) -> Bool {
        // TODO: Implement proper listener tracking
        false
    }
}

// MARK: - ChromeRuntimeOnInstalledEvent

/// chrome.runtime.onInstalled event object
public class ChromeRuntimeOnInstalledEvent {
    private weak var runtime: ChromeRuntime?

    public init(runtime: ChromeRuntime) {
        self.runtime = runtime
    }

    /// Add listener for install events
    /// - Parameter listener: Install listener function
    @MainActor public func addListener(_ listener: @escaping (ChromeInstallDetails) -> ()) {
        runtime?.addInstallListener(listener)
    }

    /// Remove listener for install events
    /// - Parameter listener: Install listener function to remove
    public func removeListener(_ listener: @escaping (ChromeInstallDetails) -> ()) {
        // TODO: Implement removal
    }

    /// Check if listener exists
    /// - Parameter listener: Install listener function to check
    /// - Returns: Whether listener exists
    public func hasListener(_ listener: @escaping (ChromeInstallDetails) -> ()) -> Bool {
        // TODO: Implement proper listener tracking
        false
    }
}

// MARK: - ChromeRuntimeOnStartupEvent

/// chrome.runtime.onStartup event object
public class ChromeRuntimeOnStartupEvent {
    private weak var runtime: ChromeRuntime?

    public init(runtime: ChromeRuntime) {
        self.runtime = runtime
    }

    /// Add listener for startup events
    /// - Parameter listener: Startup listener function
    @MainActor public func addListener(_ listener: @escaping () -> ()) {
        runtime?.addStartupListener(listener)
    }

    /// Remove listener for startup events
    /// - Parameter listener: Startup listener function to remove
    public func removeListener(_ listener: @escaping () -> ()) {
        // TODO: Implement removal
    }

    /// Check if listener exists
    /// - Parameter listener: Startup listener function to check
    /// - Returns: Whether listener exists
    public func hasListener(_ listener: @escaping () -> ()) -> Bool {
        // TODO: Implement proper listener tracking
        false
    }
}
