//
//  BackgroundScriptRunner.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Combine
import Foundation
import JavaScriptCore
import OSLog
import WebKit

// MARK: - BackgroundScriptRunner

/// Manages execution of background scripts and service workers for extensions
public class BackgroundScriptRunner: NSObject {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "BackgroundScriptRunner")

    private var contexts: [String: JSContext] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "background-script-runner", qos: .background)

    // Event listener storage for proper Chrome API event handling
    private var eventListeners: [String: [String: [JSValue]]] = [:]

    public override init() {
        super.init()
        setupGlobalErrorHandling()
    }

    /// Starts background script execution for an extension
    public func startBackgroundScript(
        for manifest: ExtensionManifest,
        extensionId: String,
        extensionURL: URL
    ) throws {
        guard let background = manifest.background else {
            logger.info("📝 No background script specified for extension: \(extensionId)")
            return // No background script to run
        }

        logger.info("🚀 Starting background script for extension: \(extensionId)")

        let context = createJSContext(for: extensionId)
        contexts[extensionId] = context

        // Setup Chrome APIs in the background context
        injectChromeAPIs(into: context, extensionId: extensionId, manifest: manifest)

        // Execute background scripts or service worker
        if manifest.manifestVersion == 2 {
            try executeBackgroundScripts(background, in: context, extensionURL: extensionURL, extensionId: extensionId)
        } else {
            try executeServiceWorker(background, in: context, extensionURL: extensionURL, extensionId: extensionId)
        }

        logger.info("✅ Background script started successfully for extension: \(extensionId)")
    }

    /// Stops background script execution for an extension
    public func stopBackgroundScript(for extensionId: String) {
        logger.info("🛑 Stopping background script for extension: \(extensionId)")

        // Clean up event listeners
        eventListeners.removeValue(forKey: extensionId)

        // Remove context
        contexts.removeValue(forKey: extensionId)

        logger.info("✅ Background script stopped for extension: \(extensionId)")
    }

    /// Executes a script in the background context
    public func executeScript(
        _ script: String,
        in extensionId: String
    ) -> JSValue? {
        guard let context = contexts[extensionId] else {
            logger.warning("⚠️ No background context found for extension: \(extensionId)")
            return nil
        }

        logger.debug("📝 Executing script in background context for: \(extensionId)")
        return context.evaluateScript(script)
    }

    /// Sends a message to the background script
    public func sendMessage(
        _ message: [String: Any],
        to extensionId: String,
        from sender: [String: Any]? = nil
    ) {
        guard let context = contexts[extensionId] else {
            logger.warning("⚠️ No background context found for extension: \(extensionId)")
            return
        }

        logger.info("📨 Sending message to background script: \(extensionId)")

        // Trigger runtime.onMessage event
        triggerEvent(
            in: context,
            extensionId: extensionId,
            eventName: "runtime.onMessage",
            arguments: [message, sender ?? [:], JSValue(newObjectIn: context)!]
        )
    }

    /// Trigger chrome.runtime.onInstalled event
    public func triggerOnInstalled(for extensionId: String, reason: String = "install") {
        guard let context = contexts[extensionId] else { return }

        let details = ["reason": reason]
        triggerEvent(in: context, extensionId: extensionId, eventName: "runtime.onInstalled", arguments: [details])
    }

    private func setupGlobalErrorHandling() {
        // Set up global error handling for background scripts
        logger.debug("🔧 Setting up global error handling for background scripts")
    }

    private func createJSContext(for extensionId: String) -> JSContext {
        let context = JSContext()!

        logger.debug("🔧 Creating JavaScript context for extension: \(extensionId)")

        // Set up enhanced error handling
        context.exceptionHandler = { [weak self] _, exception in
            self?.logger
                .error("❌ Background script error in \(extensionId): \(exception?.toString() ?? "Unknown error")")

            // Log additional exception details
            if let exception {
                self?.logger
                    .error("❌ Exception line: \(exception.objectForKeyedSubscript("line")?.toString() ?? "undefined")")
                self?.logger
                    .error(
                        "❌ Exception column: \(exception.objectForKeyedSubscript("column")?.toString() ?? "undefined")"
                    )
                self?.logger
                    .error(
                        "❌ Exception source: \(exception.objectForKeyedSubscript("sourceURL")?.toString() ?? "undefined")"
                    )

                // Log stack trace if available
                if let stack = exception.objectForKeyedSubscript("stack")?.toString() {
                    self?.logger.error("❌ Stack trace: \(stack)")
                }
            }
        }

        // Add enhanced console object for debugging
        setupConsole(in: context, extensionId: extensionId)

        // Add essential globals
        setupGlobals(in: context, extensionId: extensionId)

        return context
    }

    private func setupConsole(in context: JSContext, extensionId: String) {
        let console = JSValue(newObjectIn: context)!

        // Enhanced console methods with proper formatting - support variadic arguments
        console.setObject({ [weak self] (args: [Any]) in
            let message = args.map { arg in
                if let jsValue = arg as? JSValue {
                    return jsValue.toString() ?? String(describing: arg)
                }
                return String(describing: arg)
            }.joined(separator: " ")
            self?.logger.info("📝 Background[\(extensionId)]: \(message)")
        }, forKeyedSubscript: "log" as NSString)

        console.setObject({ [weak self] (args: [Any]) in
            let message = args.map { arg in
                if let jsValue = arg as? JSValue {
                    return jsValue.toString() ?? String(describing: arg)
                }
                return String(describing: arg)
            }.joined(separator: " ")
            self?.logger.error("❌ Background[\(extensionId)] ERROR: \(message)")
        }, forKeyedSubscript: "error" as NSString)

        console.setObject({ [weak self] (args: [Any]) in
            let message = args.map { arg in
                if let jsValue = arg as? JSValue {
                    return jsValue.toString() ?? String(describing: arg)
                }
                return String(describing: arg)
            }.joined(separator: " ")
            self?.logger.warning("⚠️ Background[\(extensionId)] WARN: \(message)")
        }, forKeyedSubscript: "warn" as NSString)

        console.setObject({ [weak self] (args: [Any]) in
            let message = args.map { arg in
                if let jsValue = arg as? JSValue {
                    return jsValue.toString() ?? String(describing: arg)
                }
                return String(describing: arg)
            }.joined(separator: " ")
            self?.logger.debug("🐛 Background[\(extensionId)] DEBUG: \(message)")
        }, forKeyedSubscript: "debug" as NSString)

        console.setObject({ [weak self] (args: [Any]) in
            let message = args.map { arg in
                if let jsValue = arg as? JSValue {
                    return jsValue.toString() ?? String(describing: arg)
                }
                return String(describing: arg)
            }.joined(separator: " ")
            self?.logger.info("ℹ️ Background[\(extensionId)] INFO: \(message)")
        }, forKeyedSubscript: "info" as NSString)

        context.setObject(console, forKeyedSubscript: "console" as NSString)
    }

    private func setupGlobals(in context: JSContext, extensionId: String) {
        // Add globalThis support
        context.evaluateScript("var globalThis = this;")

        // Add setTimeout and setInterval support
        context.setObject({ [weak self] (callback: JSValue, delay: Int) -> Int in
            let timerId = Int.random(in: 1000...9999)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                callback.call(withArguments: [])
            }
            return timerId
        }, forKeyedSubscript: "setTimeout" as NSString)

        context.setObject({ [weak self] (callback: JSValue, interval: Int) -> Int in
            let timerId = Int.random(in: 1000...9999)
            // For simplicity, just call once - real implementation would repeat
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(interval)) {
                callback.call(withArguments: [])
            }
            return timerId
        }, forKeyedSubscript: "setInterval" as NSString)

        context.setObject({ (_: Int) in
            // Clear timer implementation
        }, forKeyedSubscript: "clearTimeout" as NSString)

        context.setObject({ (_: Int) in
            // Clear interval implementation
        }, forKeyedSubscript: "clearInterval" as NSString)

        // Add Date.now() support
        context.evaluateScript("""
            if (!Date.now) {
                Date.now = function() {
                    return new Date().getTime();
                };
            }
        """)
    }

    private func executeBackgroundScripts(
        _ background: ManifestBackgroundConfiguration,
        in context: JSContext,
        extensionURL: URL,
        extensionId: String
    ) throws {
        logger.info("📜 Executing background scripts for extension: \(extensionId)")

        if let scripts = background.scripts {
            for scriptPath in scripts {
                let scriptURL = extensionURL.appendingPathComponent(scriptPath)
                logger.debug("📜 Loading background script: \(scriptPath)")
                try executeScriptFile(at: scriptURL, in: context, extensionId: extensionId)
            }
        }

        if let page = background.page {
            let pageURL = extensionURL.appendingPathComponent(page)
            logger.info("📄 Background page specified: \(pageURL)")
            // For background pages, we would need to load and parse HTML
            // This is a simplified implementation
        }

        // Trigger onInstalled event after scripts are loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.triggerOnInstalled(for: extensionId)
        }
    }

    private func executeServiceWorker(
        _ background: ManifestBackgroundConfiguration,
        in context: JSContext,
        extensionURL: URL,
        extensionId: String
    ) throws {
        guard let serviceWorker = background.service_worker else {
            throw BackgroundScriptError.missingServiceWorker
        }

        logger.info("🔧 Executing service worker for extension: \(extensionId)")

        let workerURL = extensionURL.appendingPathComponent(serviceWorker)
        try executeScriptFile(at: workerURL, in: context, extensionId: extensionId)

        // Service workers have additional lifecycle events
        triggerServiceWorkerInstall(in: context, extensionId: extensionId)

        // Trigger onInstalled event after service worker is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.triggerOnInstalled(for: extensionId)
        }
    }

    private func executeScriptFile(at url: URL, in context: JSContext, extensionId: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            logger.error("❌ Background script file not found: \(url.path)")
            throw BackgroundScriptError.executionFailed("File not found: \(url.lastPathComponent)")
        }

        var script = try String(contentsOf: url)
        logger.debug("📜 Loaded script file: \(url.lastPathComponent) (\(script.count) characters)")

        // Preprocess script to handle modern JavaScript syntax
        script = preprocessJavaScript(script, extensionId: extensionId)

        // Execute with better error handling
        context.evaluateScript(script)

        if let exception = context.exception {
            logger.error("❌ Script execution failed: \(exception.toString())")
            throw BackgroundScriptError.executionFailed(exception.toString())
        }

        logger.info("✅ Background script executed successfully: \(url.lastPathComponent)")
    }

    /// Preprocess JavaScript to handle common compatibility issues
    /// - Parameter script: Original JavaScript code
    /// - Parameter extensionId: Extension identifier for logging
    /// - Returns: Preprocessed JavaScript code
    private func preprocessJavaScript(_ script: String, extensionId: String) -> String {
        logger.debug("🔧 Preprocessing JavaScript for \(extensionId), original length: \(script.count)")

        var processed = script

        // CRITICAL: Handle template literals properly - don't break them!
        // The previous implementation was destroying template literals with ${} interpolation

        // Handle ES6 imports/exports first (before template literal processing)
        processed = processed.replacingOccurrences(
            of: #"^import\s+.*?from\s+['"`][^'"`]+['"`]\s*;?"#,
            with: "/* ES6 import disabled */",
            options: .regularExpression
        )

        processed = processed.replacingOccurrences(
            of: #"^export\s+(default\s+|const\s+|let\s+|var\s+|function\s+|class\s+)"#,
            with: "/* export disabled */ $1",
            options: .regularExpression
        )

        // Handle dynamic imports - but be careful with template literals
        processed = processed.replacingOccurrences(
            of: #"import\s*\(\s*(['"`])([^'"`\$]+)\1\s*\)"#,
            with: "/* Dynamic import disabled: $2 */",
            options: .regularExpression
        )

        // Handle import.meta
        processed = processed.replacingOccurrences(
            of: "import.meta",
            with: "{ /* import.meta polyfill */ url: 'chrome-extension://\(extensionId)/' }"
        )

        // Handle top-level await - preserve it in functions
        processed = processed.replacingOccurrences(
            of: #"^(\s*)await\s+"#,
            with: "$1/* top-level await disabled */ ",
            options: .regularExpression
        )

        // DO NOT touch template literals - they should work fine in modern JSContext
        // The error was caused by the previous regex that was breaking ${} syntax

        // Ensure proper error handling for async functions
        processed = """
        // Extension runtime initialization
        (function() {
            'use strict';

            // Enhanced error handling (works in both window and worker contexts)
            if (typeof window !== 'undefined') {
                window.addEventListener('error', function(e) {
                    console.error('Background script error:', e.error);
                });
            } else if (typeof self !== 'undefined') {
                self.addEventListener('error', function(e) {
                    console.error('Background script error:', e.error);
                });
            }

            // Original script
            \(processed)
        })();
        """

        logger.debug("🔧 JavaScript preprocessing complete for \(extensionId), new length: \(processed.count)")
        return processed
    }

    private func triggerServiceWorkerInstall(in context: JSContext, extensionId: String) {
        logger.debug("🔧 Triggering service worker install event for: \(extensionId)")

        let installScript = """
        (function() {
            if (typeof self !== 'undefined' && self.addEventListener) {
                const installEvent = { type: 'install' };
                if (typeof self.oninstall === 'function') {
                    self.oninstall(installEvent);
                }
                self.dispatchEvent && self.dispatchEvent(installEvent);
            }
        })();
        """
        context.evaluateScript(installScript)
    }

    private func triggerEvent(in context: JSContext, extensionId: String, eventName: String, arguments: [Any]) {
        // Initialize event listeners for this extension if needed
        if eventListeners[extensionId] == nil {
            eventListeners[extensionId] = [:]
        }

        guard let listeners = eventListeners[extensionId]?[eventName] else {
            logger.debug("📡 No listeners for event \(eventName) in extension: \(extensionId)")
            return
        }

        logger.debug("📡 Triggering event \(eventName) for \(listeners.count) listeners in extension: \(extensionId)")

        for listener in listeners {
            listener.call(withArguments: arguments)
        }
    }

    private func injectChromeAPIs(into context: JSContext, extensionId: String, manifest: ExtensionManifest) {
        logger.debug("🔧 Injecting Chrome APIs for extension: \(extensionId)")

        // Create chrome object
        let chrome = JSValue(newObjectIn: context)!

        // Add runtime API
        let runtime = createRuntimeAPI(for: extensionId, in: context, manifest: manifest)
        chrome.setObject(runtime, forKeyedSubscript: "runtime" as NSString)

        // Add storage API
        let storage = createStorageAPI(for: extensionId, in: context)
        chrome.setObject(storage, forKeyedSubscript: "storage" as NSString)

        // Add tabs API
        let tabs = createTabsAPI(for: extensionId, in: context)
        chrome.setObject(tabs, forKeyedSubscript: "tabs" as NSString)

        // Add action API (Manifest v3) or browserAction API (Manifest v2)
        if manifest.manifestVersion >= 3 {
            let action = createActionAPI(for: extensionId, in: context)
            chrome.setObject(action, forKeyedSubscript: "action" as NSString)
        } else {
            let browserAction = createBrowserActionAPI(for: extensionId, in: context)
            chrome.setObject(browserAction, forKeyedSubscript: "browserAction" as NSString)
        }

        context.setObject(chrome, forKeyedSubscript: "chrome" as NSString)

        // Also add as 'browser' for WebExtensions compatibility
        context.setObject(chrome, forKeyedSubscript: "browser" as NSString)

        logger.debug("✅ Chrome APIs injected for extension: \(extensionId)")
    }

    private func createRuntimeAPI(
        for extensionId: String,
        in context: JSContext,
        manifest: ExtensionManifest
    ) -> JSValue {
        let runtime = JSValue(newObjectIn: context)!

        // runtime.id
        runtime.setObject(extensionId, forKeyedSubscript: "id" as NSString)

        // runtime.sendMessage
        runtime.setObject({ [weak self] (message: JSValue, _: JSValue?, callback: JSValue?) in
            self?.logger.debug("📨 runtime.sendMessage called with: \(message)")

            // Handle callback if provided
            if let callback, callback.isObject {
                DispatchQueue.main.async {
                    let response = ["success": true, "timestamp": Date().timeIntervalSince1970]
                    callback.call(withArguments: [response])
                }
            }
        }, forKeyedSubscript: "sendMessage" as NSString)

        // runtime.onMessage event
        let onMessage = createEventAPI(for: extensionId, eventName: "runtime.onMessage", in: context)
        runtime.setObject(onMessage, forKeyedSubscript: "onMessage" as NSString)

        // runtime.onInstalled event
        let onInstalled = createEventAPI(for: extensionId, eventName: "runtime.onInstalled", in: context)
        runtime.setObject(onInstalled, forKeyedSubscript: "onInstalled" as NSString)

        // runtime.openOptionsPage
        runtime.setObject({ [weak self] (callback: JSValue?) in
            self?.logger.info("⚙️ runtime.openOptionsPage called for extension: \(extensionId)")

            // Check for duplicate calls
            let currentTime = Date().timeIntervalSince1970
            let deduplicationKey = "openOptionsPage_\(extensionId)"

            if let lastCallTime = UserDefaults.standard.object(forKey: deduplicationKey) as? TimeInterval,
               currentTime - lastCallTime < 1.0 {
                self?.logger.info("🔄 Skipping duplicate openOptionsPage call from background script for \(extensionId)")
                if let callback, callback.isObject {
                    callback.call(withArguments: [])
                }
                return
            }

            UserDefaults.standard.set(currentTime, forKey: deduplicationKey)

            // Post notification to open options page - mark as handled by runtime to prevent duplication
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .openExtensionSettings,
                    object: nil,
                    userInfo: [
                        "extensionId": extensionId,
                        "handledByRuntime": true,
                        "source": "background-script"
                    ]
                )
            }

            // Call callback if provided
            if let callback, callback.isObject {
                callback.call(withArguments: [])
            }
        }, forKeyedSubscript: "openOptionsPage" as NSString)

        // runtime.getURL
        runtime.setObject({ (path: String) -> String in
            return "chrome-extension://\(extensionId)/\(path)"
        }, forKeyedSubscript: "getURL" as NSString)

        // runtime.getManifest
        runtime.setObject({ [weak self] () -> [String: Any] in
            // Return a basic manifest structure
            return [
                "manifest_version": manifest.manifestVersion,
                "name": manifest.name,
                "version": manifest.version,
                "description": manifest.description ?? ""
            ]
        }, forKeyedSubscript: "getManifest" as NSString)

        return runtime
    }

    private func createStorageAPI(for extensionId: String, in context: JSContext) -> JSValue {
        let storage = JSValue(newObjectIn: context)!

        // storage.sync
        let sync = JSValue(newObjectIn: context)!

        sync.setObject({ [weak self] (_: JSValue?, callback: JSValue?) in
            self?.logger.debug("📦 storage.sync.get called")

            // Mock storage implementation - in real implementation, this would use ExtensionStorage
            let mockData: [String: Any] = [
                "enabled": true,
                "theme": "auto",
                "debugMode": false
            ]

            if let callback, callback.isObject {
                DispatchQueue.main.async {
                    callback.call(withArguments: [mockData])
                }
            }
        }, forKeyedSubscript: "get" as NSString)

        sync.setObject({ [weak self] (data: JSValue, callback: JSValue?) in
            self?.logger.debug("📦 storage.sync.set called with: \(data)")

            if let callback, callback.isObject {
                DispatchQueue.main.async {
                    callback.call(withArguments: [])
                }
            }
        }, forKeyedSubscript: "set" as NSString)

        storage.setObject(sync, forKeyedSubscript: "sync" as NSString)

        // storage.local (similar to sync)
        storage.setObject(sync, forKeyedSubscript: "local" as NSString)

        // storage.onChanged event
        let onChanged = createEventAPI(for: extensionId, eventName: "storage.onChanged", in: context)
        storage.setObject(onChanged, forKeyedSubscript: "onChanged" as NSString)

        return storage
    }

    private func createTabsAPI(for extensionId: String, in context: JSContext) -> JSValue {
        let tabs = JSValue(newObjectIn: context)!

        // tabs.query
        tabs.setObject({ [weak self] (queryInfo: JSValue, callback: JSValue) in
            self?.logger.debug("📑 tabs.query called with: \(queryInfo)")

            // Mock tab data - in real implementation, this would query actual tabs
            let mockTabs = [
                [
                    "id": 1,
                    "url": "https://example.com",
                    "title": "Example Page",
                    "active": true
                ]
            ]

            DispatchQueue.main.async {
                callback.call(withArguments: [mockTabs])
            }
        }, forKeyedSubscript: "query" as NSString)

        // tabs.getCurrent
        tabs.setObject({ [weak self] (callback: JSValue) in
            self?.logger.debug("📑 tabs.getCurrent called")

            let currentTab = [
                "id": 1,
                "url": "https://example.com",
                "title": "Current Tab",
                "active": true
            ]

            DispatchQueue.main.async {
                callback.call(withArguments: [currentTab])
            }
        }, forKeyedSubscript: "getCurrent" as NSString)

        return tabs
    }

    private func createActionAPI(for extensionId: String, in context: JSContext) -> JSValue {
        let action = JSValue(newObjectIn: context)!

        // action.onClicked event
        let onClicked = createEventAPI(for: extensionId, eventName: "action.onClicked", in: context)
        action.setObject(onClicked, forKeyedSubscript: "onClicked" as NSString)

        return action
    }

    private func createBrowserActionAPI(for extensionId: String, in context: JSContext) -> JSValue {
        let browserAction = JSValue(newObjectIn: context)!

        // browserAction.onClicked event
        let onClicked = createEventAPI(for: extensionId, eventName: "browserAction.onClicked", in: context)
        browserAction.setObject(onClicked, forKeyedSubscript: "onClicked" as NSString)

        return browserAction
    }

    private func createEventAPI(for extensionId: String, eventName: String, in context: JSContext) -> JSValue {
        let event = JSValue(newObjectIn: context)!

        // addListener method
        event.setObject({ [weak self] (callback: JSValue) in
            self?.logger.debug("📡 Adding listener for event: \(eventName) in extension: \(extensionId)")

            // Initialize storage if needed
            if self?.eventListeners[extensionId] == nil {
                self?.eventListeners[extensionId] = [:]
            }
            if self?.eventListeners[extensionId]?[eventName] == nil {
                self?.eventListeners[extensionId]?[eventName] = []
            }

            // Store the callback
            self?.eventListeners[extensionId]?[eventName]?.append(callback)
        }, forKeyedSubscript: "addListener" as NSString)

        // removeListener method
        event.setObject({ [weak self] (_: JSValue) in
            self?.logger.debug("📡 Removing listener for event: \(eventName) in extension: \(extensionId)")

            // Remove specific callback (simplified implementation)
            self?.eventListeners[extensionId]?[eventName]?.removeAll()
        }, forKeyedSubscript: "removeListener" as NSString)

        // hasListener method
        event.setObject({ [weak self] (_: JSValue) -> Bool in
            return self?.eventListeners[extensionId]?[eventName]?.isEmpty == false
        }, forKeyedSubscript: "hasListener" as NSString)

        return event
    }
}

// MARK: - BackgroundContext

/// Background execution context
public struct BackgroundContext {
    public let type: BackgroundType
    public let scriptFiles: [String]
    public let isPersistent: Bool

    public enum BackgroundType {
        case serviceWorker
        case backgroundPage
        case backgroundScripts
    }
}

// MARK: - BackgroundConfiguration

/// Background configuration from manifest
public struct BackgroundConfiguration {
    public let serviceWorker: String?
    public let scripts: [String]?
    public let page: String?
    public let persistent: Bool?

    public init(serviceWorker: String? = nil, scripts: [String]? = nil, page: String? = nil, persistent: Bool? = nil) {
        self.serviceWorker = serviceWorker
        self.scripts = scripts
        self.page = page
        self.persistent = persistent
    }
}

// MARK: - BackgroundScriptError

/// Background script errors
public enum BackgroundScriptError: Error, LocalizedError {
    case missingServiceWorker
    case missingBackgroundScripts
    case executionFailed(String)
    case invalidConfiguration
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .missingServiceWorker:
            "Service worker file not found"
        case .missingBackgroundScripts:
            "Background scripts not found"
        case let .executionFailed(message):
            "Script execution failed: \(message)"
        case .invalidConfiguration:
            "Invalid background configuration"
        case let .fileNotFound(path):
            "Script file not found: \(path)"
        }
    }
}
