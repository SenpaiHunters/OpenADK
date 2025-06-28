//
//  ExtensionMessageRouter.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Combine
import Foundation
import OSLog
import WebKit

// MARK: - ExtensionMessageRouter

/// Handles message routing between extension contexts and web pages
public class ExtensionMessageRouter: NSObject {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "MessageRouter")
    private var webViews: Set<WKWebView> = []
    private weak var runtime: ExtensionRuntime?

    public override init() {
        super.init()
    }

    /// Registers the message router with a web view
    public func registerWithWebView(_ webView: WKWebView, runtime: ExtensionRuntime) {
        self.runtime = runtime
        webViews.insert(webView)

        // Check if message handler already exists to prevent duplicates
        let userContentController = webView.configuration.userContentController

        // Try to remove existing handler first (this won't throw if it doesn't exist)
        userContentController.removeScriptMessageHandler(forName: "extensionMessage")

        // Now add the message handler
        userContentController.add(self, name: "extensionMessage")

        logger.info("📱 Message router registered with WebView")
    }

    /// Unregisters the message router from a web view
    public func unregisterFromWebView(_ webView: WKWebView) {
        webViews.remove(webView)

        let userContentController = webView.configuration.userContentController
        userContentController.removeScriptMessageHandler(forName: "extensionMessage")

        logger.info("📱 Message router unregistered from WebView")
    }

    /// Send message to background script
    public func sendMessageToBackground(
        _ message: [String: Any],
        to extensionId: String,
        completion: @escaping ([String: Any]?) -> ()
    ) {
        /// TODO: Basic message routing - Implementation this would
        /// route to the actual background script
        logger.debug("📨 Routing message to background script of extension \(extensionId)")
        completion(["response": "message received"])
    }

    /// Sends a message to content script
    public func sendMessageToContent(
        _ message: [String: Any],
        in webView: WKWebView,
        completion: @escaping ([String: Any]?) -> ()
    ) {
        logger.info("📤 Sending message to content script")

        let messageJSON = try? JSONSerialization.data(withJSONObject: message)
        let messageString = messageJSON.map { String(data: $0, encoding: .utf8) } ?? "{}"

        let script = """
        if (window.chrome && window.chrome.runtime && window.chrome.runtime.onMessage) {
            window.chrome.runtime.onMessage.trigger(\(messageString));
        }
        """

        webView.evaluateJavaScript(script) { _, error in
            if let error {
                self.logger.error("❌ Failed to send message to content script: \(error)")
                completion(nil)
            } else {
                completion(["response": "message sent to content"])
            }
        }
    }
}

// MARK: WKScriptMessageHandler

extension ExtensionMessageRouter: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        logger.info("📨 Received message from web page: \(message.name)")

        if let messageBody = message.body as? [String: Any] {
            logger.info("📋 Message content: \(messageBody)")
        } else {
            logger.warning("⚠️ Message body is not a dictionary: \(type(of: message.body))")
        }

        guard message.name == "extensionMessage",
              let messageBody = message.body as? [String: Any] else {
            logger.warning("⚠️ Ignoring non-extension message or invalid format")
            return
        }

        handleExtensionMessage(messageBody, from: message.webView)
    }

    private func handleExtensionMessage(_ message: [String: Any], from webView: WKWebView?) {
        logger.info("🔍 Processing extension message: \(message)")

        // Handle storage API messages (use "action" field)
        if let action = message["action"] as? String {
            logger.info("📦 Processing storage/tabs API action: \(action)")
            handleStorageAPIMessage(message, action: action, webView: webView)
            return
        }

        // Handle legacy extension messages (use "type" field)
        guard let extensionId = message["extensionId"] as? String,
              let messageType = message["type"] as? String else {
            logger.error("❌ Invalid extension message format - missing extensionId or type")
            logger.error("❌ Message keys: \(message.keys)")
            return
        }

        logger.info("🔧 Processing legacy message type: \(messageType) for extension: \(extensionId)")
        switch messageType {
        case "contentScript":
            handleContentScriptMessage(message, extensionId: extensionId, webView: webView)
        case "background":
            handleBackgroundMessage(message, extensionId: extensionId)
        default:
            logger.warning("⚠️ Unknown message type: \(messageType)")
        }
    }

    /// Handle storage API messages from extension pages
    private func handleStorageAPIMessage(_ message: [String: Any], action: String, webView: WKWebView?) {
        guard let extensionId = message["extensionId"] as? String else {
            logger.error("❌ Storage API message missing extensionId")
            return
        }

        Task { @MainActor in
            guard let loadedExtension = ExtensionRuntime.shared.loadedExtensions[extensionId] else {
                logger.error("❌ Extension not found: \(extensionId)")
                return
            }

            let callbackId = message["callbackId"] as? String

            logger.info("🗄️ Handling storage API message: \(action) for extension: \(extensionId)")

            // Create ChromeStorage instance for this extension
            let chromeStorage = ChromeStorage(extensionId: extensionId)

            switch action {
            case "storage.local.get":
                handleStorageGet(chromeStorage.local, message: message, webView: webView, callbackId: callbackId)

            case "storage.local.set":
                handleStorageSet(chromeStorage.local, message: message, webView: webView, callbackId: callbackId)

            case "storage.local.remove":
                handleStorageRemove(chromeStorage.local, message: message, webView: webView, callbackId: callbackId)

            case "storage.local.clear":
                handleStorageClear(chromeStorage.local, message: message, webView: webView, callbackId: callbackId)

            case "storage.sync.get":
                handleStorageGet(chromeStorage.sync, message: message, webView: webView, callbackId: callbackId)

            case "storage.sync.set":
                handleStorageSet(chromeStorage.sync, message: message, webView: webView, callbackId: callbackId)

            case "storage.sync.remove":
                handleStorageRemove(chromeStorage.sync, message: message, webView: webView, callbackId: callbackId)

            case "storage.sync.clear":
                handleStorageClear(chromeStorage.sync, message: message, webView: webView, callbackId: callbackId)

            case "tabs.query":
                handleTabsQuery(message: message, webView: webView, callbackId: callbackId)

            case "tabs.get":
                handleTabsGet(message: message, webView: webView, callbackId: callbackId)

            case "tabs.getCurrent":
                handleTabsGetCurrent(message: message, webView: webView, callbackId: callbackId)

            case "tabs.create":
                handleTabsCreate(message: message, webView: webView, callbackId: callbackId)

            case "tabs.update":
                handleTabsUpdate(message: message, webView: webView, callbackId: callbackId)

            case "tabs.remove":
                handleTabsRemove(message: message, webView: webView, callbackId: callbackId)

            case "runtime.openOptionsPage":
                handleRuntimeOpenOptionsPage(message: message, webView: webView, callbackId: callbackId)

            default:
                logger.warning("⚠️ Unknown storage action: \(action)")
            }
        }
    }

    /// Handle storage get operation
    private func handleStorageGet(
        _ storageArea: ChromeStorageArea,
        message: [String: Any],
        webView: WKWebView?,
        callbackId: String?
    ) {
        let keys = message["keys"]

        storageArea.get(keys) { result in
            if let webView, let callbackId {
                // Ensure result is JSON-serializable by removing any Optional values
                let cleanResult = self.cleanForJSON(result)

                // Double-check JSON serialization and provide more detailed error handling
                do {
                    let resultJSON = try JSONSerialization.data(withJSONObject: cleanResult, options: [])
                    let resultString = String(data: resultJSON, encoding: .utf8) ?? "{}"

                    let script = """
                    if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                        window.extensionCallbacks['\(callbackId)'](\(resultString));
                        delete window.extensionCallbacks['\(callbackId)'];
                    }
                    """

                    webView.evaluateJavaScript(script) { _, error in
                        if let error {
                            self.logger.error("❌ Failed to execute storage get callback: \(error)")
                        }
                    }
                } catch {
                    self.logger.error("❌ Failed to serialize storage result to JSON: \(error)")
                    self.logger.error("❌ Raw result: \(result)")
//                    self.logger.error("❌ Cleaned result: \(cleanResult)")

                    // Fallback to empty object
                    let script = """
                    if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                        window.extensionCallbacks['\(callbackId)']({});
                        delete window.extensionCallbacks['\(callbackId)'];
                    }
                    """

                    webView.evaluateJavaScript(script) { _, error in
                        if let error {
                            self.logger.error("❌ Failed to execute fallback storage get callback: \(error)")
                        }
                    }
                }
            }
        }
    }

    /// Handle storage set operation
    private func handleStorageSet(
        _ storageArea: ChromeStorageArea,
        message: [String: Any],
        webView: WKWebView?,
        callbackId: String?
    ) {
        // Try both 'data' and 'items' keys for compatibility
        let data = (message["data"] as? [String: Any]) ?? (message["items"] as? [String: Any])
        guard let data else {
            logger.error("❌ Storage set missing data or items")
            return
        }

        storageArea.set(data) { error in
            if let webView, let callbackId {
                let script = """
                if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                    window.extensionCallbacks['\(callbackId)']();
                    delete window.extensionCallbacks['\(callbackId)'];
                }
                """

                webView.evaluateJavaScript(script) { _, jsError in
                    if let jsError {
                        self.logger.error("❌ Failed to execute storage set callback: \(jsError)")
                    }
                }
            }

            if let error {
                self.logger.error("❌ Storage set error: \(error)")
            }
        }
    }

    /// Handle storage remove operation
    private func handleStorageRemove(
        _ storageArea: ChromeStorageArea,
        message: [String: Any],
        webView: WKWebView?,
        callbackId: String?
    ) {
        let keys = message["keys"]
        storageArea.remove(keys as Any) { error in
            if let webView, let callbackId {
                let script = """
                if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                    window.extensionCallbacks['\(callbackId)']();
                    delete window.extensionCallbacks['\(callbackId)'];
                }
                """

                webView.evaluateJavaScript(script) { _, jsError in
                    if let jsError {
                        self.logger.error("❌ Failed to execute storage remove callback: \(jsError)")
                    }
                }
            }

            if let error {
                self.logger.error("❌ Storage remove error: \(error)")
            }
        }
    }

    /// Handle storage clear operation
    private func handleStorageClear(
        _ storageArea: ChromeStorageArea,
        message: [String: Any],
        webView: WKWebView?,
        callbackId: String?
    ) {
        storageArea.clear { error in
            if let webView, let callbackId {
                let script = """
                if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                    window.extensionCallbacks['\(callbackId)']();
                    delete window.extensionCallbacks['\(callbackId)'];
                }
                """

                webView.evaluateJavaScript(script) { _, jsError in
                    if let jsError {
                        self.logger.error("❌ Failed to execute storage clear callback: \(jsError)")
                    }
                }
            }

            if let error {
                self.logger.error("❌ Storage clear error: \(error)")
            }
        }
    }

    private func handleContentScriptMessage(
        _ message: [String: Any],
        extensionId: String,
        webView: WKWebView?
    ) {
        logger.info("📝 Handling content script message from: \(extensionId)")
        // Handle content script messages
    }

    private func handleBackgroundMessage(
        _ message: [String: Any],
        extensionId: String
    ) {
        logger.info("🎬 Handling background message from: \(extensionId)")
        // Handle background script messages
    }

    // MARK: - Tabs API Handlers

    /// Handle tabs.query operation
    private func handleTabsQuery(message: [String: Any], webView: WKWebView?, callbackId: String?) {
        logger.info("📑 Handling tabs.query")

        // Get current tab information from webView
        let currentTab = createTabInfo(from: webView, id: 1, active: true)
        let result = [currentTab]

        if let webView, let callbackId {
            // Clean result for JSON serialization
            let cleanResult = cleanForJSON(result)

            // Double-check JSON serialization and provide more detailed error handling
            do {
                let resultJSON = try JSONSerialization.data(withJSONObject: cleanResult, options: [])
                let resultString = String(data: resultJSON, encoding: .utf8) ?? "[]"

                let script = """
                if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                    window.extensionCallbacks['\(callbackId)'](\(resultString));
                    delete window.extensionCallbacks['\(callbackId)'];
                }
                """

                webView.evaluateJavaScript(script) { _, error in
                    if let error {
                        self.logger.error("❌ Failed to execute tabs.query callback: \(error)")
                    }
                }
            } catch {
                logger.error("❌ Failed to serialize tabs.query result to JSON: \(error)")
                logger.error("❌ Raw result: \(result)")
//                self.logger.error("❌ Cleaned result: \(cleanResult)")

                // Fallback to empty array
                let script = """
                if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                    window.extensionCallbacks['\(callbackId)']([]);
                    delete window.extensionCallbacks['\(callbackId)'];
                }
                """

                webView.evaluateJavaScript(script) { _, error in
                    if let error {
                        self.logger.error("❌ Failed to execute fallback tabs.query callback: \(error)")
                    }
                }
            }
        }
    }

    /// Handle tabs.get operation
    private func handleTabsGet(message: [String: Any], webView: WKWebView?, callbackId: String?) {
        logger.info("📑 Handling tabs.get")

        let tabId = message["tabId"] as? Int ?? 1
        let currentTab = createTabInfo(from: webView, id: tabId, active: true)

        if let webView, let callbackId {
            // Clean result for JSON serialization
            let cleanResult = cleanForJSON(currentTab)

            let resultJSON = try? JSONSerialization.data(withJSONObject: cleanResult)
            let resultString = resultJSON.map { String(data: $0, encoding: .utf8) } ?? "{}"

            let script = """
            if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                window.extensionCallbacks['\(callbackId)'](\(resultString));
                delete window.extensionCallbacks['\(callbackId)'];
            }
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    self.logger.error("❌ Failed to execute tabs.get callback: \(error)")
                }
            }
        }
    }

    /// Handle tabs.getCurrent operation
    private func handleTabsGetCurrent(message: [String: Any], webView: WKWebView?, callbackId: String?) {
        logger.info("📑 Handling tabs.getCurrent")

        let currentTab = createTabInfo(from: webView, id: 1, active: true)

        if let webView, let callbackId {
            // Clean result for JSON serialization
            let cleanResult = cleanForJSON(currentTab)

            let resultJSON = try? JSONSerialization.data(withJSONObject: cleanResult)
            let resultString = resultJSON.map { String(data: $0, encoding: .utf8) } ?? "{}"

            let script = """
            if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                window.extensionCallbacks['\(callbackId)'](\(resultString));
                delete window.extensionCallbacks['\(callbackId)'];
            }
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    self.logger.error("❌ Failed to execute tabs.getCurrent callback: \(error)")
                }
            }
        }
    }

    /// Handle tabs.create operation
    private func handleTabsCreate(message: [String: Any], webView: WKWebView?, callbackId: String?) {
        logger.info("📑 Handling tabs.create")

        guard let createProperties = message["createProperties"] as? [String: Any] else {
            logger.error("❌ Missing createProperties in tabs.create")
            return
        }

        let url = createProperties["url"] as? String ?? "about:blank"

        // Post notification to create new tab
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("CreateNewTab"),
                object: nil,
                userInfo: ["url": url]
            )
        }

        // Create mock tab for callback
        let newTab = createTabInfo(from: nil, id: 2, active: false, url: url)

        if let webView, let callbackId {
            // Clean result for JSON serialization
            let cleanResult = cleanForJSON(newTab)

            let resultJSON = try? JSONSerialization.data(withJSONObject: cleanResult)
            let resultString = resultJSON.map { String(data: $0, encoding: .utf8) } ?? "{}"

            let script = """
            if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                window.extensionCallbacks['\(callbackId)'](\(resultString));
                delete window.extensionCallbacks['\(callbackId)'];
            }
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    self.logger.error("❌ Failed to execute tabs.create callback: \(error)")
                }
            }
        }
    }

    /// Handle tabs.update operation
    private func handleTabsUpdate(message: [String: Any], webView: WKWebView?, callbackId: String?) {
        logger.info("📑 Handling tabs.update")

        let tabId = message["tabId"] as? Int ?? 1
        guard let updateProperties = message["updateProperties"] as? [String: Any] else {
            logger.error("❌ Missing updateProperties in tabs.update")
            return
        }

        if let url = updateProperties["url"] as? String {
            // Navigate to new URL if provided
            webView?.load(URLRequest(url: URL(string: url) ?? URL(string: "about:blank")!))
        }

        let updatedTab = createTabInfo(from: webView, id: tabId, active: true)

        if let webView, let callbackId {
            // Clean result for JSON serialization
            let cleanResult = cleanForJSON(updatedTab)

            let resultJSON = try? JSONSerialization.data(withJSONObject: cleanResult)
            let resultString = resultJSON.map { String(data: $0, encoding: .utf8) } ?? "{}"

            let script = """
            if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                window.extensionCallbacks['\(callbackId)'](\(resultString));
                delete window.extensionCallbacks['\(callbackId)'];
            }
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    self.logger.error("❌ Failed to execute tabs.update callback: \(error)")
                }
            }
        }
    }

    /// Handle tabs.remove operation
    private func handleTabsRemove(message: [String: Any], webView: WKWebView?, callbackId: String?) {
        logger.info("📑 Handling tabs.remove")

        // Post notification to close tab(s)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("CloseTab"),
                object: nil,
                userInfo: message
            )
        }

        if let webView, let callbackId {
            let script = """
            if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                window.extensionCallbacks['\(callbackId)']();
                delete window.extensionCallbacks['\(callbackId)'];
            }
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    self.logger.error("❌ Failed to execute tabs.remove callback: \(error)")
                }
            }
        }
    }

    /// Handle runtime.openOptionsPage operation
    private func handleRuntimeOpenOptionsPage(message: [String: Any], webView: WKWebView?, callbackId: String?) {
        logger.info("⚙️ Handling runtime.openOptionsPage")

        guard let extensionId = message["extensionId"] as? String else {
            logger.error("❌ Missing extensionId in runtime.openOptionsPage")
            return
        }

        // Use a static variable to track recent openOptionsPage calls to prevent duplicates
        let currentTime = Date().timeIntervalSince1970
        let deduplicationKey = "openOptionsPage_\(extensionId)"

        // Check if we've already handled this request recently (within 1 second)
        if let lastCallTime = UserDefaults.standard.object(forKey: deduplicationKey) as? TimeInterval,
           currentTime - lastCallTime < 1.0 {
            logger.info("🔄 Skipping duplicate openOptionsPage call for \(extensionId)")
            return
        }

        // Record this call time
        UserDefaults.standard.set(currentTime, forKey: deduplicationKey)

        // Post notification to open options page
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenExtensionSettings"),
                object: nil,
                userInfo: [
                    "extensionId": extensionId,
                    "source": "extension-page",
                    "handledByRuntime": true
                ]
            )
        }

        // Call callback if provided
        if let webView, let callbackId {
            let script = """
            if (window.extensionCallbacks && window.extensionCallbacks['\(callbackId)']) {
                window.extensionCallbacks['\(callbackId)']();
                delete window.extensionCallbacks['\(callbackId)'];
            }
            """

            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    self.logger.error("❌ Failed to execute runtime.openOptionsPage callback: \(error)")
                }
            }
        }
    }

    /// Create tab info object from WebView
    private func createTabInfo(from webView: WKWebView?, id: Int, active: Bool, url: String? = nil) -> [String: Any] {
        let currentURL = url ?? webView?.url?.absoluteString ?? "about:blank"
        let title = webView?.title ?? "New Tab"

        let tabInfo: [String: Any] = [
            "id": id,
            "url": currentURL,
            "title": title,
            "active": active,
            "highlighted": active,
            "pinned": false,
            "status": "complete",
            "incognito": false,
            "index": 0,
            "windowId": 1
        ]

        return tabInfo
    }

    /// Clean data for JSON serialization by removing Swift Optional types
    private func cleanForJSON(_ data: Any) -> Any {
        // Handle nil/NSNull first
        if data is NSNull {
            return NSNull()
        }

        // Use String representation to check for Optional types as a fallback
        let typeString = String(describing: type(of: data))
        if typeString.contains("Optional") {
            // This is an Optional type - try to extract the value
            let mirror = Mirror(reflecting: data)
            if let unwrapped = mirror.children.first?.value {
                return cleanForJSON(unwrapped)
            } else {
                return NSNull()
            }
        }

        // Use Mirror to safely inspect the type
        let mirror = Mirror(reflecting: data)

        // Check if it's an Optional type using Mirror
        if mirror.displayStyle == .optional {
            if let unwrapped = mirror.children.first?.value {
                return cleanForJSON(unwrapped)
            } else {
                return NSNull()
            }
        }

        // Handle dictionary types safely
        if let dict = data as? [String: Any] {
            var cleanDict: [String: Any] = [:]
            for (key, value) in dict {
                let cleanValue = cleanForJSON(value)
                // Skip NSNull values entirely and ensure JSON compatibility
                if !(cleanValue is NSNull) {
                    // Additional check for JSON serializable types
                    if JSONSerialization.isValidJSONObject([key: cleanValue]) {
                        cleanDict[key] = cleanValue
                    } else {
                        // Convert to string if not JSON serializable
                        cleanDict[key] = String(describing: cleanValue)
                    }
                }
            }
            return cleanDict
        }

        // Handle array types safely
        if let array = data as? [Any] {
            return array.compactMap { element -> Any? in
                let cleanElement = cleanForJSON(element)
                // Skip NSNull elements and ensure JSON compatibility
                if cleanElement is NSNull {
                    return nil
                }
                // Additional check for JSON serializable types
                if JSONSerialization.isValidJSONObject([cleanElement]) {
                    return cleanElement
                } else {
                    // Convert to string if not JSON serializable
                    return String(describing: cleanElement)
                }
            }
        }

        // For primitive types, ensure they're JSON serializable
        if data is String || data is NSString ||
            data is Int || data is NSNumber ||
            data is Bool || data is NSNull {
            return data
        }

        // For any other type, convert to string to ensure JSON compatibility
        return String(describing: data)
    }
}

// MARK: - MessageHandler

/// Message handler protocol
public protocol MessageHandler {
    func handleMessage(
        _ message: [String: Any],
        sender: MessageSender,
        completion: @escaping ([String: Any]?) -> ()
    )
}

// MARK: - MessageSender

/// Message sender information
public struct MessageSender {
    public let extensionId: UUID
    public let tabId: Int?
    public let frameId: Int
    public let url: String?

    public init(extensionId: UUID, tabId: Int?, frameId: Int, url: String?) {
        self.extensionId = extensionId
        self.tabId = tabId
        self.frameId = frameId
        self.url = url
    }
}

// MARK: - ExtensionConnection

/// Extension connection for long-lived messaging
public struct ExtensionConnection {
    public let id: String
    public let name: String?
    public let sender: MessageSender

    public init(id: String, name: String?, sender: MessageSender) {
        self.id = id
        self.name = name
        self.sender = sender
    }
}

// MARK: - ExtensionPort

/// Extension port for communication
public struct ExtensionPort {
    public let connectionId: String
    public let name: String?
    public let sender: MessageSender

    public init(connectionId: String, name: String?, sender: MessageSender) {
        self.connectionId = connectionId
        self.name = name
        self.sender = sender
    }
}
