//
//  ExtensionRuntime.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Combine
import CryptoKit
import Foundation
import OSLog
import WebKit

// MARK: - ExtensionRuntime

/// Main coordinator for extension runtime operations
@MainActor
public class ExtensionRuntime: NSObject, ObservableObject {
    public static let shared = ExtensionRuntime()

    private let logger = Logger(subsystem: "com.alto.extensions", category: "ExtensionRuntime")

    // MARK: - Runtime State

    @Published public var loadedExtensions: [String: LoadedExtension] = [:]
    @Published public var isEnabled = true

    /// Runtime configuration
    private let configuration: ExtensionRuntimeConfiguration

    // MARK: - Core Components

    private let permissionManager = ExtensionPermissionManager()
    private let backgroundScriptRunner = BackgroundScriptRunner()
    private let contentScriptInjector = ContentScriptInjector()
    private let messageRouter = ExtensionMessageRouter()
    private let storeDownloader = ExtensionStoreDownloader()

    // MARK: - WebView Registry

    /// Active WebViews with their extension integrations
    private var webViewRegistry: [WKWebView: Set<String>] = [:]

    public override init() {
        configuration = ExtensionRuntimeConfiguration.default
        super.init()
        setupNotificationObservers()
        logger.info("🚀 Extension runtime initialized")
    }

    /// Initialize extensions at startup
    /// - Parameter basePath: Base path for extensions directory
    public func initializeAtStartup() async {
        logger.info("🔧 Initializing extensions at startup...")

        // Set up extension storage
        await ExtensionStorage.shared.initialize()

        // Load all installed extensions
        let installedExtensions = ExtensionStorage.shared.getAllInstalledExtensions()
        logger.info("📋 Found \(installedExtensions.count) installed extensions")

        // Load each extension with error handling
        var successfullyLoaded = 0
        var failedExtensions: [String] = []

        for (extensionId, extensionMetadata) in installedExtensions {
            guard extensionMetadata.isEnabled else {
                logger.debug("⏸️ Skipping disabled extension: \(extensionMetadata.name)")
                continue
            }

            do {
                let extensionURL = URL(fileURLWithPath: extensionMetadata.installationPath)

                // Check if extension directory exists
                guard FileManager.default.fileExists(atPath: extensionURL.path) else {
                    logger.warning("📁 Extension directory not found: \(extensionURL.path)")
                    throw ExtensionRuntimeError.extensionNotFound(extensionId)
                }

                // Load existing extension without reinstalling
                try await loadExistingExtension(
                    extensionId: extensionId,
                    from: extensionURL,
                    metadata: extensionMetadata
                )

                successfullyLoaded += 1
                logger.debug("✅ Loaded extension: \(extensionMetadata.name)")
            } catch {
                logger.error("❌ Failed to load extension \(extensionMetadata.name): \(error)")
                failedExtensions.append(extensionId)

                // If it's a file not found error, clean up the metadata
                if let nsError = error as NSError?,
                   nsError.domain == NSCocoaErrorDomain,
                   nsError.code == 260 { // File not found
                    logger.warning("🧹 Cleaning up corrupted extension metadata: \(extensionMetadata.name)")
                    try? ExtensionStorage.shared.uninstallExtension(extensionId)
                }
            }
        }

        logger.info("🎉 Extension startup initialization complete")
        logger.info("✅ Successfully loaded: \(successfullyLoaded)/\(installedExtensions.count) extensions")

        // Clean up duplicate extensions
        await cleanupDuplicateExtensions()

        // Process i18n messages for all loaded extensions
        processI18nMessages()
    }

    /// Clean up duplicate extensions based on name and version
    private func cleanupDuplicateExtensions() async {
        logger.info("🧹 Cleaning up duplicate extensions...")

        let allExtensions = ExtensionStorage.shared.getAllInstalledExtensions()
        var extensionsBySignature: [String: [String]] = [:]

        // Group extensions by name+version signature
        for (extensionId, metadata) in allExtensions {
            let signature = "\(metadata.name)|\(metadata.version)"
            extensionsBySignature[signature, default: []].append(extensionId)
        }

        // Find duplicates and keep only the most recent one
        var extensionsToRemove: [String] = []

        for (signature, extensionIds) in extensionsBySignature {
            if extensionIds.count > 1 {
                logger.warning("🔍 Found \(extensionIds.count) duplicates for: \(signature)")

                // Get metadata for all duplicates to find the most recent
                var extensionDates: [(String, Date)] = []
                for extId in extensionIds {
                    if let metadata = ExtensionStorage.shared.getExtensionMetadata(extId) {
                        extensionDates.append((extId, metadata.installDate))
                    }
                }

                // Sort by install date (newest first) and keep the first one
                extensionDates.sort { $0.1 > $1.1 }
                let toKeep = extensionDates.first?.0

                // Mark others for removal
                for (extId, _) in extensionDates.dropFirst() {
                    logger.info("🗑️ Marking duplicate extension for removal: \(extId)")
                    extensionsToRemove.append(extId)
                }

                if let keeping = toKeep {
                    logger.info("✅ Keeping most recent extension: \(keeping)")
                }
            }
        }

        // Remove duplicate extensions
        for extensionId in extensionsToRemove {
            logger.info("🗑️ Removing duplicate extension: \(extensionId)")

            // Remove from loaded extensions if present
            loadedExtensions.removeValue(forKey: extensionId)

            // Stop background script if running
            backgroundScriptRunner.stopBackgroundScript(for: extensionId)

            // Remove from storage
            do {
                try ExtensionStorage.shared.uninstallExtension(extensionId)
                logger.info("✅ Successfully removed duplicate extension: \(extensionId)")
            } catch {
                logger.error("❌ Failed to remove duplicate extension \(extensionId): \(error)")
            }
        }

        if extensionsToRemove.isEmpty {
            logger.info("✅ No duplicate extensions found")
        } else {
            logger.info("🧹 Cleanup complete: removed \(extensionsToRemove.count) duplicate extensions")
        }
    }

    /// Load an existing extension from storage without reinstalling
    /// - Parameters:
    ///   - extensionId: Existing extension ID
    ///   - extensionURL: URL to extension directory
    ///   - metadata: Extension metadata from storage
    private func loadExistingExtension(
        extensionId: String,
        from extensionURL: URL,
        metadata: InstalledExtensionMetadata
    ) async throws {
        logger.debug("📂 Loading existing extension: \(extensionId)")

        // Load and parse manifest
        let manifestURL = extensionURL.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ExtensionRuntimeError.missingFile("manifest.json")
        }

        let manifestData = try Data(contentsOf: manifestURL)
        var manifest = try ExtensionManifest.parse(from: manifestData)

        // Process i18n messages if needed
        manifest = try processI18nMessages(manifest, in: extensionURL)

        // Create loaded extension using existing ID
        let loadedExt = LoadedExtension(
            id: extensionId,
            manifest: manifest,
            url: extensionURL,
            isEnabled: metadata.isEnabled,
            installDate: metadata.installDate,
            chromeWebStoreId: metadata.originalId
        )

        loadedExtensions[extensionId] = loadedExt
        logger.debug("📚 Extension added to loaded extensions registry: \(manifest.name)")

        // Start background script if present and extension is enabled
        if metadata.isEnabled, let backgroundConfig = manifest.background {
            logger.debug("🚀 Starting background script for extension: \(manifest.name)")

            try backgroundScriptRunner.startBackgroundScript(
                for: manifest,
                extensionId: extensionId,
                extensionURL: extensionURL
            )
        }
    }

    // MARK: - Extension Cleanup

    /// Manually trigger cleanup of duplicate extensions
    public func cleanupDuplicates() async {
        await cleanupDuplicateExtensions()
    }

    // MARK: - Extension Lifecycle

    /// Install an extension from a directory
    /// - Parameters:
    ///   - extensionURL: URL to extension directory
    ///   - isTemporary: Whether this is a temporary development extension
    /// - Returns: Extension ID if successful
    @discardableResult
    public func installExtension(from extensionURL: URL, isTemporary: Bool = false) async throws -> String {
        logger.info("📦 Installing extension from: \(extensionURL)")

        // Check if this is a Chrome Web Store URL
        if isWebStoreURL(extensionURL) {
            return try await installFromWebStore(extensionURL)
        }

        // Handle local directory installation
        return try await installFromLocalDirectory(extensionURL, isTemporary: isTemporary)
    }

    /// Install extension from Chrome Web Store URL
    /// - Parameter storeURL: Chrome Web Store URL
    /// - Returns: Extension ID if successful
    private func installFromWebStore(_ storeURL: URL) async throws -> String {
        logger.info("🌐 Installing extension from Chrome Web Store: \(storeURL)")

        // Extract the Chrome Web Store extension ID
        guard let extensionInfo = ChromeWebStoreIntegration.shared.detectExtensionPage(storeURL),
              !extensionInfo.extensionId.isEmpty else {
            logger.error("❌ Could not extract extension ID from URL: \(storeURL)")
            throw ExtensionDownloadError.invalidStoreURL
        }

        let chromeExtensionId = extensionInfo.extensionId
        logger.info("🆔 Chrome Web Store Extension ID: \(chromeExtensionId)")

        return try await withCheckedThrowingContinuation { continuation in
            storeDownloader.downloadExtension(from: storeURL) { result in
                switch result {
                case let .success(localURL):
                    Task {
                        do {
                            let extensionId = try await self.installFromLocalDirectory(
                                localURL,
                                isTemporary: false,
                                installationSource: .chromeWebStore,
                                originalId: chromeExtensionId
                            )
                            continuation.resume(returning: extensionId)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }

                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Install extension from local directory
    /// - Parameters:
    ///   - extensionURL: Local directory URL
    ///   - isTemporary: Whether this is temporary
    ///   - installationSource: Source where extension was installed from
    ///   - originalId: Original Chrome Web Store ID (if applicable)
    /// - Returns: Extension ID
    private func installFromLocalDirectory(
        _ extensionURL: URL,
        isTemporary: Bool,
        installationSource: ExtensionInstallationSource = .local,
        originalId: String? = nil
    ) async throws -> String {
        logger.info("📦 Installing extension from local directory: \(extensionURL.path)")

        // Load and parse manifest
        let manifestURL = extensionURL.appendingPathComponent("manifest.json")
        logger.debug("📄 Loading manifest from: \(manifestURL.path)")

        let manifestData = try Data(contentsOf: manifestURL)
        var manifest = try ExtensionManifest.parse(from: manifestData)

        // Process i18n messages if needed
        manifest = try processI18nMessages(manifest, in: extensionURL)

        logger.info("📋 Extension Details:")
        logger.info("   📛 Name: \(manifest.name)")
        logger.info("   🔢 Version: \(manifest.version)")
        logger.info("   📖 Description: \(manifest.description ?? "No description")")
        logger.info("   🏷️ Manifest Version: \(manifest.manifestVersion)")

        let extensionId = generateExtensionId(for: manifest, from: extensionURL)
        logger.info("🆔 Generated Extension ID: \(extensionId)")

        // Check if extension is already installed
        if loadedExtensions.keys.contains(extensionId) {
            logger.warning("⚠️ Extension with ID \(extensionId) is already loaded")
            return extensionId
        }

        // Check if extension is already in storage
        if ExtensionStorage.shared.isExtensionInstalled(extensionId) {
            logger.warning("⚠️ Extension with ID \(extensionId) is already installed in storage")
            // Load the existing extension instead of reinstalling
            if let metadata = ExtensionStorage.shared.getExtensionMetadata(extensionId) {
                try await loadExistingExtension(
                    extensionId: extensionId,
                    from: extensionURL,
                    metadata: metadata
                )
                return extensionId
            }
        }

        // List all permissions requested
        let allPerms = Array(manifest.allPermissions)
        if !allPerms.isEmpty {
            logger.info("🔐 Requested Permissions: \(allPerms.joined(separator: ", "))")
        } else {
            logger.info("🔐 No permissions requested")
        }

        // Check permissions
        let result = await permissionManager.requestPermissions(
            allPerms,
            for: extensionId,
            extensionName: manifest.name
        )

        guard case .granted = result else {
            logger.error("❌ Permission request denied for extension: \(manifest.name)")
            throw ExtensionRuntimeError.permissionDenied
        }

        logger.info("✅ Permissions granted")

        // Install extension to permanent location
        let permanentURL = try await ExtensionStorage.shared.installExtension(
            from: extensionURL,
            extensionId: extensionId,
            manifest: manifest,
            installationSource: installationSource,
            originalId: originalId
        )

        // Create loaded extension
        let loadedExt = LoadedExtension(
            id: extensionId,
            manifest: manifest,
            url: permanentURL,
            isEnabled: true,
            chromeWebStoreId: originalId
        )

        loadedExtensions[extensionId] = loadedExt
        logger.info("📚 Extension added to loaded extensions registry")

        // Start background script if present
        if let backgroundConfig = manifest.background {
            logger.info("🚀 Starting background script for extension")
            if let scripts = backgroundConfig.scripts {
                logger.debug("📜 Background scripts: \(scripts.joined(separator: ", "))")
            }
            if let serviceWorker = backgroundConfig.service_worker {
                logger.debug("⚙️ Service worker: \(serviceWorker)")
            }

            try backgroundScriptRunner.startBackgroundScript(
                for: manifest,
                extensionId: extensionId,
                extensionURL: extensionURL
            )
        } else {
            logger.info("ℹ️ No background script to start")
        }

        logger.info("✅ Extension installed: \(manifest.name)")
        logger.info("📁 Extension location: \(extensionURL.path)")
        return extensionId
    }

    /// Checks if URL is a Chrome Web Store URL
    /// - Parameter url: URL to check
    /// - Returns: True if it's a web store URL
    private func isWebStoreURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("chrome.google.com") ||
            host.contains("chromewebstore.google.com")
    }

    /// Uninstall an extension completely
    /// - Parameter extensionId: Extension to uninstall
    public func uninstallExtension(_ extensionId: String) {
        guard let loadedExt = loadedExtensions[extensionId] else { return }

        logger.info("🗑️ Uninstalling extension: \(loadedExt.manifest.name)")

        // Stop background script
        backgroundScriptRunner.stopBackgroundScript(for: extensionId)

        // Remove permissions
        permissionManager.removeAllPermissions(for: extensionId)

        // Remove from loaded extensions
        loadedExtensions.removeValue(forKey: extensionId)

        logger.info("✅ Extension uninstalled: \(loadedExt.manifest.name)")
    }

    /// Enable/disable an extension
    /// - Parameters:
    ///   - extensionId: Extension to toggle
    ///   - enabled: Whether to enable or disable
    public func setExtensionEnabled(_ extensionId: String, enabled: Bool) {
        guard var loadedExt = loadedExtensions[extensionId] else { return }

        loadedExt.isEnabled = enabled
        loadedExtensions[extensionId] = loadedExt

        if enabled {
            // Restart background script
            if loadedExt.manifest.background != nil {
                try? backgroundScriptRunner.startBackgroundScript(
                    for: loadedExt.manifest,
                    extensionId: extensionId,
                    extensionURL: loadedExt.url
                )
            }
        } else {
            // Stop background script
            backgroundScriptRunner.stopBackgroundScript(for: extensionId)
        }

        logger.info("🔄 Extension \(enabled ? "enabled" : "disabled"): \(loadedExt.manifest.name)")
    }

    /// Injects content scripts when a web view navigates
    public func handleNavigation(in webView: WKWebView, to url: URL) async {
        guard isEnabled else { return }

        logger.debug("🧭 Handling navigation to: \(url.absoluteString)")

        // Ensure Chrome user agent for Web Store URLs
        if let adkWebView = webView as? ADKWebView {
            adkWebView.ensureChromeUserAgentForURL(url)
        }

        // Check if this is an extension page (options page, popup, etc.)
        if let extensionInfo = detectExtensionPage(url) {
            // logger.info("🔌 Detected extension page: \(extensionInfo.extensionId) - \(extensionInfo.pageType)")
            await injectExtensionAPIs(into: webView, for: extensionInfo)
            return
        }

        // Check if this is a Chrome Web Store extension page
        if let extensionInfo = ChromeWebStoreIntegration.shared.detectExtensionPage(url) {
            logger.info("🌐 Detected Chrome Web Store extension page: \(extensionInfo.extensionId)")

            // Add a small delay to ensure page is loaded, then inject controls
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                ChromeWebStoreIntegration.shared.injectAltoControls(into: webView, extensionInfo: extensionInfo)
            }
        }
    }

    /// Detect if a URL is an extension page
    /// - Parameter url: URL to check
    /// - Returns: Extension page information if detected
    private func detectExtensionPage(_ url: URL) -> ExtensionPageInfo? {
        guard url.isFileURL else { return nil }

        let path = url.path.lowercased()

        // Check if it's in an extension directory
        for (extensionId, loadedExtension) in loadedExtensions {
            let extensionPath = loadedExtension.url.path.lowercased()

            if path.hasPrefix(extensionPath) {
                // Determine page type
                let relativePath = String(path.dropFirst(extensionPath.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

                let pageType: ExtensionPageType = if relativePath == loadedExtension.manifest.optionsPage?
                    .lowercased() ||
                    relativePath == loadedExtension.manifest.options?.page?
                    .lowercased() {
                    .options
                } else if let action = loadedExtension.manifest.action,
                          relativePath == action.default_popup?.lowercased() {
                    .popup
                } else if let browserAction = loadedExtension.manifest.browserAction,
                          relativePath == browserAction.default_popup?.lowercased() {
                    .popup
                } else {
                    .other
                }

                return ExtensionPageInfo(
                    extensionId: extensionId,
                    pageType: pageType,
                    relativePath: relativePath,
                    loadedExtension: loadedExtension
                )
            }
        }

        return nil
    }

    /// Inject extension APIs into a WebView for extension pages
    /// - Parameters:
    ///   - webView: WebView to inject APIs into
    ///   - extensionInfo: Extension information
    private func injectExtensionAPIs(into webView: WKWebView, for extensionInfo: ExtensionPageInfo) async {
        // logger.info("💉 Injecting Chrome APIs into extension page: \(extensionInfo.pageType)")

        // Register message router BEFORE injecting JavaScript to ensure message handlers are available
        messageRouter.registerWithWebView(webView, runtime: self)
        logger.info("📱 Message router registered for extension page")

        // Generate JavaScript that creates the Chrome APIs
        let apiScript = generateChromeAPIScript(
            for: extensionInfo.extensionId,
            manifest: extensionInfo.loadedExtension.manifest
        )

        // Inject the APIs into the WebView - remove async continuation to avoid timing issues
        webView.evaluateJavaScript(apiScript) { _, error in
            if let error {
                self.logger.error("❌ Failed to inject Chrome APIs: \(error.localizedDescription)")
            } else {
                self.logger.info("✅ Chrome APIs injected successfully into extension page")
            }
        }
    }

    /// Generate JavaScript code that creates Chrome extension APIs in a WebView
    /// - Parameters:
    ///   - extensionId: Extension ID
    ///   - manifest: Extension manifest
    /// - Returns: JavaScript code to inject
    private func generateChromeAPIScript(for extensionId: String, manifest: ExtensionManifest) -> String {
        """
        (function() {
            console.log('🔧 Alto Settings Test Extension - Injecting Chrome APIs');

            // Create chrome object if it doesn't exist
            if (typeof window.chrome === 'undefined') {
                window.chrome = {};
            }

            // Chrome Runtime API
            window.chrome.runtime = {
                id: '\(extensionId)',

                sendMessage: function(message, options, callback) {
                    console.log('📨 chrome.runtime.sendMessage called:', message);

                    // Handle different parameter patterns
                    if (typeof options === 'function') {
                        callback = options;
                        options = undefined;
                    }

                    // Mock response for now
                    if (callback) {
                        setTimeout(() => {
                            callback({
                                success: true,
                                timestamp: Date.now(),
                                echo: message
                            });
                        }, 0);
                    }
                },

                openOptionsPage: function(callback) {
                    console.log('⚙️ chrome.runtime.openOptionsPage called');

                    try {
                        // Post message to native implementation to open options page
                        window.webkit.messageHandlers.extensionMessage.postMessage({
                            action: 'runtime.openOptionsPage',
                            extensionId: '\(extensionId)'
                        });
                    } catch (error) {
                        console.error('❌ Failed to open options page:', error);
                    }

                    if (callback) callback();
                },

                getURL: function(path) {
                    return 'chrome-extension://\(extensionId)/' + path;
                },

                getManifest: function() {
                    return {
                        manifest_version: \(manifest.manifestVersion),
                        name: '\(manifest.name.replacingOccurrences(of: "'", with: "\\'"))',
                        version: '\(manifest.version)',
                        description: '\(manifest.description?.replacingOccurrences(of: "'", with: "\\'") ?? "")'
                    };
                },

                onMessage: {
                    addListener: function(callback) {
                        console.log('📡 chrome.runtime.onMessage.addListener called');
                        // Store listener for later use
                    },
                    removeListener: function(callback) {
                        console.log('📡 chrome.runtime.onMessage.removeListener called');
                    }
                },

                onInstalled: {
                    addListener: function(callback) {
                        console.log('📡 chrome.runtime.onInstalled.addListener called');
                        // Store listener for later use
                    }
                }
            };

            // Chrome Storage API
            window.chrome.storage = {
                sync: {
                    get: function(keys, callback) {
                        console.log('📦 chrome.storage.sync.get called with:', keys);

                        try {
                            // Initialize callback registry if not exists
                            if (!window.extensionCallbacks) {
                                window.extensionCallbacks = {};
                            }

                            const callbackId = 'storage_sync_get_' + Date.now() + '_' + Math.random();
                            window.extensionCallbacks[callbackId] = callback;

                            // Send message to native implementation
                            console.log('📤 Sending storage.sync.get message with callbackId:', callbackId);
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'storage.sync.get',
                                extensionId: '\(extensionId)',
                                keys: keys,
                                callbackId: callbackId
                            });
                        } catch (error) {
                            console.error('❌ Storage.sync.get error:', error, error.stack);
                            if (callback) callback({});
                        }
                    },

                    set: function(data, callback) {
                        console.log('📦 chrome.storage.sync.set called with:', data);

                        try {
                            if (!window.extensionCallbacks) {
                                window.extensionCallbacks = {};
                            }

                            const callbackId = 'storage_sync_set_' + Date.now() + '_' + Math.random();
                            if (callback) {
                                window.extensionCallbacks[callbackId] = callback;
                            }

                            console.log('📤 Sending storage.sync.set message with callbackId:', callbackId);
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'storage.sync.set',
                                extensionId: '\(extensionId)',
                                data: data,
                                callbackId: callbackId
                            });
                        } catch (error) {
                            console.error('❌ Storage.sync.set error:', error, error.stack);
                            if (callback) callback();
                        }
                    },

                    remove: function(keys, callback) {
                        console.log('📦 chrome.storage.sync.remove called with:', keys);

                        try {
                            if (!window.extensionCallbacks) {
                                window.extensionCallbacks = {};
                            }

                            const callbackId = 'storage_sync_remove_' + Date.now() + '_' + Math.random();
                            if (callback) {
                                window.extensionCallbacks[callbackId] = callback;
                            }

                            console.log('📤 Sending storage.sync.remove message with callbackId:', callbackId);
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'storage.sync.remove',
                                extensionId: '\(extensionId)',
                                keys: keys,
                                callbackId: callbackId
                            });
                        } catch (error) {
                            console.error('❌ Storage.sync.remove error:', error, error.stack);
                            if (callback) callback();
                        }
                    },

                    clear: function(callback) {
                        console.log('📦 chrome.storage.sync.clear called');

                        try {
                            if (!window.extensionCallbacks) {
                                window.extensionCallbacks = {};
                            }

                            const callbackId = 'storage_sync_clear_' + Date.now() + '_' + Math.random();
                            if (callback) {
                                window.extensionCallbacks[callbackId] = callback;
                            }

                            console.log('📤 Sending storage.sync.clear message with callbackId:', callbackId);
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'storage.sync.clear',
                                extensionId: '\(extensionId)',
                                callbackId: callbackId
                            });
                        } catch (error) {
                            console.error('❌ Storage.sync.clear error:', error, error.stack);
                            if (callback) callback();
                        }
                    }
                },

                local: {
                    get: function(keys, callback) {
                        console.log('📦 chrome.storage.local.get called with:', keys);

                        try {
                            if (!window.extensionCallbacks) {
                                window.extensionCallbacks = {};
                            }

                            const callbackId = 'storage_local_get_' + Date.now() + '_' + Math.random();
                            window.extensionCallbacks[callbackId] = callback;

                            console.log('📤 Sending storage.local.get message with callbackId:', callbackId);
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'storage.local.get',
                                extensionId: '\(extensionId)',
                                keys: keys,
                                callbackId: callbackId
                            });
                        } catch (error) {
                            console.error('❌ Storage.local.get error:', error, error.stack);
                            if (callback) callback({});
                        }
                    },

                    set: function(data, callback) {
                        console.log('📦 chrome.storage.local.set called with:', data);

                        try {
                            if (!window.extensionCallbacks) {
                                window.extensionCallbacks = {};
                            }

                            const callbackId = 'storage_local_set_' + Date.now() + '_' + Math.random();
                            if (callback) {
                                window.extensionCallbacks[callbackId] = callback;
                            }

                            console.log('📤 Sending storage.local.set message with callbackId:', callbackId);
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'storage.local.set',
                                extensionId: '\(extensionId)',
                                data: data,
                                callbackId: callbackId
                            });
                        } catch (error) {
                            console.error('❌ Storage.local.set error:', error, error.stack);
                            if (callback) callback();
                        }
                    },

                    remove: function(keys, callback) {
                        console.log('📦 chrome.storage.local.remove called with:', keys);

                        try {
                            if (!window.extensionCallbacks) {
                                window.extensionCallbacks = {};
                            }

                            const callbackId = 'storage_local_remove_' + Date.now() + '_' + Math.random();
                            if (callback) {
                                window.extensionCallbacks[callbackId] = callback;
                            }

                            console.log('📤 Sending storage.local.remove message with callbackId:', callbackId);
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'storage.local.remove',
                                extensionId: '\(extensionId)',
                                keys: keys,
                                callbackId: callbackId
                            });
                        } catch (error) {
                            console.error('❌ Storage.local.remove error:', error, error.stack);
                            if (callback) callback();
                        }
                    },

                    clear: function(callback) {
                        console.log('📦 chrome.storage.local.clear called');

                        try {
                            if (!window.extensionCallbacks) {
                                window.extensionCallbacks = {};
                            }

                            const callbackId = 'storage_local_clear_' + Date.now() + '_' + Math.random();
                            if (callback) {
                                window.extensionCallbacks[callbackId] = callback;
                            }

                            console.log('📤 Sending storage.local.clear message with callbackId:', callbackId);
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'storage.local.clear',
                                extensionId: '\(extensionId)',
                                callbackId: callbackId
                            });
                        } catch (error) {
                            console.error('❌ Storage.local.clear error:', error, error.stack);
                            if (callback) callback();
                        }
                    }
                },

                onChanged: {
                    addListener: function(callback) {
                        console.log('👂 chrome.storage.onChanged.addListener called');
                        // Store listener for later use
                    },
                    removeListener: function(callback) {
                        console.log('👂 chrome.storage.onChanged.removeListener called');
                    }
                }
            };

            // Chrome Tabs API
            window.chrome.tabs = {
                query: function(queryInfo, callback) {
                    console.log('📑 chrome.tabs.query called with:', queryInfo);

                    try {
                        if (!window.extensionCallbacks) {
                            window.extensionCallbacks = {};
                        }

                        const callbackId = 'tabs_query_' + Date.now() + '_' + Math.random();
                        window.extensionCallbacks[callbackId] = callback;

                        console.log('📤 Sending tabs.query message with callbackId:', callbackId);
                        window.webkit.messageHandlers.extensionMessage.postMessage({
                            action: 'tabs.query',
                            extensionId: '\(extensionId)',
                            queryInfo: queryInfo,
                            callbackId: callbackId
                        });
                    } catch (error) {
                        console.error('❌ Tabs.query error:', error, error.stack);
                        if (callback) callback([]);
                    }
                },

                get: function(tabId, callback) {
                    console.log('📑 chrome.tabs.get called with tabId:', tabId);

                    try {
                        if (!window.extensionCallbacks) {
                            window.extensionCallbacks = {};
                        }

                        const callbackId = 'tabs_get_' + Date.now() + '_' + Math.random();
                        window.extensionCallbacks[callbackId] = callback;

                        console.log('📤 Sending tabs.get message with callbackId:', callbackId);
                        window.webkit.messageHandlers.extensionMessage.postMessage({
                            action: 'tabs.get',
                            extensionId: '\(extensionId)',
                            tabId: tabId,
                            callbackId: callbackId
                        });
                    } catch (error) {
                        console.error('❌ Tabs.get error:', error, error.stack);
                        if (callback) callback(null);
                    }
                },

                getCurrent: function(callback) {
                    console.log('📑 chrome.tabs.getCurrent called');

                    try {
                        if (!window.extensionCallbacks) {
                            window.extensionCallbacks = {};
                        }

                        const callbackId = 'tabs_getCurrent_' + Date.now() + '_' + Math.random();
                        window.extensionCallbacks[callbackId] = callback;

                        console.log('📤 Sending tabs.getCurrent message with callbackId:', callbackId);
                        window.webkit.messageHandlers.extensionMessage.postMessage({
                            action: 'tabs.getCurrent',
                            extensionId: '\(extensionId)',
                            callbackId: callbackId
                        });
                    } catch (error) {
                        console.error('❌ Tabs.getCurrent error:', error, error.stack);
                        if (callback) callback(null);
                    }
                },

                create: function(createProperties, callback) {
                    console.log('📑 chrome.tabs.create called with:', createProperties);

                    try {
                        if (!window.extensionCallbacks) {
                            window.extensionCallbacks = {};
                        }

                        const callbackId = 'tabs_create_' + Date.now() + '_' + Math.random();
                        if (callback) {
                            window.extensionCallbacks[callbackId] = callback;
                        }

                        console.log('📤 Sending tabs.create message with callbackId:', callbackId);
                        window.webkit.messageHandlers.extensionMessage.postMessage({
                            action: 'tabs.create',
                            extensionId: '\(extensionId)',
                            createProperties: createProperties,
                            callbackId: callbackId
                        });
                    } catch (error) {
                        console.error('❌ Tabs.create error:', error, error.stack);
                        if (callback) callback(null);
                    }
                },

                update: function(tabId, updateProperties, callback) {
                    console.log('📑 chrome.tabs.update called');

                    try {
                        if (!window.extensionCallbacks) {
                            window.extensionCallbacks = {};
                        }

                        const callbackId = 'tabs_update_' + Date.now() + '_' + Math.random();
                        if (callback) {
                            window.extensionCallbacks[callbackId] = callback;
                        }

                        console.log('📤 Sending tabs.update message with callbackId:', callbackId);
                        window.webkit.messageHandlers.extensionMessage.postMessage({
                            action: 'tabs.update',
                            extensionId: '\(extensionId)',
                            tabId: tabId,
                            updateProperties: updateProperties,
                            callbackId: callbackId
                        });
                    } catch (error) {
                        console.error('❌ Tabs.update error:', error, error.stack);
                        if (callback) callback(null);
                    }
                },

                remove: function(tabIds, callback) {
                    console.log('📑 chrome.tabs.remove called with:', tabIds);

                    try {
                        if (!window.extensionCallbacks) {
                            window.extensionCallbacks = {};
                        }

                        const callbackId = 'tabs_remove_' + Date.now() + '_' + Math.random();
                        if (callback) {
                            window.extensionCallbacks[callbackId] = callback;
                        }

                        console.log('📤 Sending tabs.remove message with callbackId:', callbackId);
                        window.webkit.messageHandlers.extensionMessage.postMessage({
                            action: 'tabs.remove',
                            extensionId: '\(extensionId)',
                            tabIds: tabIds,
                            callbackId: callbackId
                        });
                    } catch (error) {
                        console.error('❌ Tabs.remove error:', error, error.stack);
                        if (callback) callback();
                    }
                }
            };

            // Also create browser object for WebExtensions compatibility
            window.browser = window.chrome;

            // Global error handler for better debugging
            window.onerror = function(msg, url, lineNo, columnNo, error) {
                console.error('❌ JavaScript Error in Extension Page:', {
                    message: msg,
                    source: url,
                    line: lineNo,
                    column: columnNo,
                    error: error,
                    stack: error ? error.stack : 'No stack trace'
                });
                return false;
            };

            // Promise rejection handler
            window.addEventListener('unhandledrejection', function(event) {
                console.error('❌ Unhandled Promise Rejection:', event.reason);
                console.error('❌ Stack trace:', event.reason ? event.reason.stack : 'No stack trace');
            });

            // Debug information
            console.log('🔧 Extension API Debug Info:', {
                extensionId: '\(extensionId)',
                manifestName: '\(manifest.name.replacingOccurrences(of: "'", with: "\\'"))',
                manifestVersion: \(manifest.manifestVersion),
                userAgent: navigator.userAgent,
                location: window.location.href,
                hasWebkit: typeof window.webkit !== 'undefined',
                hasMessageHandler: typeof window.webkit !== 'undefined' && 
                                  typeof window.webkit.messageHandlers !== 'undefined' &&
                                  typeof window.webkit.messageHandlers.extensionMessage !== 'undefined',
                webkitMessageHandlers: typeof window.webkit !== 'undefined' && window.webkit.messageHandlers ? 
                                      Object.keys(window.webkit.messageHandlers) : [],
                chrome: {
                    runtime: typeof window.chrome.runtime,
                    storage: typeof window.chrome.storage,
                    tabs: typeof window.chrome.tabs
                }
            });

            console.log('✅ Chrome APIs injected successfully');
        })();
        """
    }

    /// Registers the extension runtime with a web view for message handling
    public func registerWithWebView(_ webView: WKWebView) {
        messageRouter.registerWithWebView(webView, runtime: self)
    }

    // MARK: - WebView Integration

    /// Register a WebView with the extension runtime
    /// - Parameter webView: WebView to register
    public func registerWebView(_ webView: WKWebView) async {
        logger.debug("📱 Registering WebView with extension runtime")
        webViewRegistry[webView] = Set()

        // Register message router with this WebView to enable extension communication
        messageRouter.registerWithWebView(webView, runtime: self)
    }

    /// Unregister a WebView from the extension runtime
    /// - Parameter webView: WebView to unregister
    public func unregisterWebView(_ webView: WKWebView) {
        logger.debug("📱 Unregistering WebView from extension runtime")
        webViewRegistry.removeValue(forKey: webView)

        // Unregister message router from this WebView
        messageRouter.unregisterFromWebView(webView)
    }

    // MARK: - Extension Communication

    /// Send message to extension
    /// - Parameters:
    ///   - message: Message to send
    ///   - extensionId: Target extension
    ///   - completion: Response callback
    public func sendMessageToExtension(
        _ message: [String: Any],
        extensionId: String,
        completion: @escaping ([String: Any]?) -> ()
    ) {
        messageRouter.sendMessageToBackground(message, to: extensionId, completion: completion)
    }

    // MARK: - Private Helpers

    /// Setup notification observers
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AltoWebViewCreated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let webView = notification.object as? WKWebView else { return }
            Task { @MainActor in
                await self?.registerWebView(webView)
            }
        }

        // Handle extension settings opening requests - only from UI and background scripts marked as handledByRuntime
        NotificationCenter.default.addObserver(
            forName: .openExtensionSettings,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let extensionId = userInfo["extensionId"] as? String else {
                self?.logger.warning("⚠️ Received openExtensionSettings notification without extensionId")
                return
            }

            // Only handle if this is marked as handled by runtime (from background script) or UI origin
            let handledByRuntime = userInfo["handledByRuntime"] as? Bool == true
            let fromUI = userInfo["source"] as? String == "ui"
            let fromBackgroundScript = userInfo["source"] as? String == "background-script"

            guard handledByRuntime || fromUI || fromBackgroundScript else {
                self?.logger.debug("🔄 Skipping openExtensionSettings - not marked for runtime handling")
                return
            }

            // Check for duplicate calls using the same key pattern as other components
            let currentTime = Date().timeIntervalSince1970
            let deduplicationKey = "openExtensionSettings_\(extensionId)"

            if let lastCallTime = UserDefaults.standard.object(forKey: deduplicationKey) as? TimeInterval,
               currentTime - lastCallTime < 1.0 {
                self?.logger
                    .info("🔄 Skipping duplicate openExtensionSettings call from ExtensionRuntime for \(extensionId)")
                return
            }

            UserDefaults.standard.set(currentTime, forKey: deduplicationKey)

            Task { @MainActor in
                await self?.openExtensionSettings(for: extensionId)
            }
        }
    }

    /// Open extension settings page
    /// - Parameter extensionId: The extension ID to open settings for
    private func openExtensionSettings(for extensionId: String) async {
        logger.info("⚙️ Opening settings for extension: \(extensionId)")

        guard let loadedExtension = loadedExtensions[extensionId] else {
            logger.error("❌ Extension not found: \(extensionId)")
            return
        }

        // Check if extension has options page configured (options_ui in manifest)
        if let optionsUI = loadedExtension.manifest.options {
            // Extension has a dedicated options page
            guard let page = optionsUI.page else {
                logger.warning("⚠️ Extension \(extensionId) has options_ui configured but no page specified")
                return
            }

            let optionsPageURL = loadedExtension.url.appendingPathComponent(page)

            // Verify the options page file exists
            guard FileManager.default.fileExists(atPath: optionsPageURL.path) else {
                logger.error("❌ Options page file not found: \(optionsPageURL.path)")
                return
            }

            logger.info("📄 Opening dedicated options page: \(optionsPageURL)")

            // Post notification to open the options page in a new tab
            let openTabNotification = Notification.Name("OpenExtensionOptionsPage")
            NotificationCenter.default.post(
                name: openTabNotification,
                object: nil,
                userInfo: [
                    "extensionId": extensionId,
                    "optionsPageURL": optionsPageURL,
                    "openInTab": optionsUI.open_in_tab ?? true,
                    "source": "extension-runtime"
                ]
            )
        } else {
            // No dedicated options page - check if extension has a popup we can show as fallback
            var fallbackURL: URL?
            var fallbackDescription = "default popup"

            // Try action popup (manifest v3)
            if let action = loadedExtension.manifest.action,
               let popup = action.default_popup {
                fallbackURL = loadedExtension.url.appendingPathComponent(popup)
                fallbackDescription = "action popup"
            }
            // Try browserAction popup (manifest v2)
            else if let browserAction = loadedExtension.manifest.browserAction,
                    let popup = browserAction.default_popup {
                fallbackURL = loadedExtension.url.appendingPathComponent(popup)
                fallbackDescription = "browser action popup"
            }

            if let fallbackURL,
               FileManager.default.fileExists(atPath: fallbackURL.path) {
                logger.info("⚙️ No options page configured, opening \(fallbackDescription) as fallback: \(fallbackURL)")

                // Post notification to open the fallback popup in a new tab
                let openTabNotification = Notification.Name("OpenExtensionOptionsPage")
                NotificationCenter.default.post(
                    name: openTabNotification,
                    object: nil,
                    userInfo: [
                        "extensionId": extensionId,
                        "optionsPageURL": fallbackURL,
                        "openInTab": true, // Always open fallback in tab
                        "isFallback": true,
                        "source": "extension-runtime"
                    ]
                )
            } else {
                logger
                    .warning(
                        "⚠️ Extension \(extensionId) (\(loadedExtension.manifest.name)) has no options page or popup configured"
                    )

                // Could potentially show a generic extension info page here
                // For now, just log the warning
            }
        }
    }

    private func generateExtensionId(for manifest: ExtensionManifest, from extensionURL: URL? = nil) -> String {
        // Create a deterministic ID based on manifest content and path
        var contentForHash = "\(manifest.name)\(manifest.version)\(manifest.description ?? "")"

        // Include some manifest details to make hash more unique
        if let permissions = manifest.permissions {
            contentForHash += permissions.joined(separator: ",")
        }
        if let hostPermissions = manifest.hostPermissions {
            contentForHash += hostPermissions.joined(separator: ",")
        }

        // Use path as additional discriminator if available
        if let extensionURL {
            contentForHash += extensionURL.lastPathComponent
        }

        // Create hash for uniqueness using CryptoKit
        let hashData = contentForHash.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: hashData)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        let shortHash = String(hashString.prefix(8)).uppercased()

        // Create a more readable ID, handling localized names
        let baseName = manifest.name.hasPrefix("__MSG_") ? "extension" : manifest.name
        let cleanName = baseName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "__msg_", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)

        return "\(cleanName)-\(shortHash)"
    }

    /// Process i18n messages in the manifest
    /// - Parameters:
    ///   - manifest: Original manifest
    ///   - extensionURL: Extension directory URL
    /// - Returns: Manifest with processed i18n messages
    private func processI18nMessages(_ manifest: ExtensionManifest, in extensionURL: URL) throws -> ExtensionManifest {
        // Check if localization is needed
        guard manifest.name.hasPrefix("__MSG_") ||
            (manifest.description?.hasPrefix("__MSG_") == true) else {
            return manifest
        }

        logger.debug("🌐 Processing i18n messages for extension")

        // Get system locale, fallback to "en"
        let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let localesToTry = [preferredLanguage, "en"] // Try preferred language, then English

        var localizedMessages: [String: [String: String]] = [:]

        // Try to load locale messages in order of preference
        let localesDir = extensionURL.appendingPathComponent("_locales")
        for locale in localesToTry {
            let localeDir = localesDir.appendingPathComponent(locale)
            let messagesFile = localeDir.appendingPathComponent("messages.json")

            if FileManager.default.fileExists(atPath: messagesFile.path) {
                do {
                    let messagesData = try Data(contentsOf: messagesFile)
                    if let messages = try JSONSerialization
                        .jsonObject(with: messagesData) as? [String: [String: String]] {
                        localizedMessages = messages
                        logger.debug("🌐 Loaded \(messages.count) localized messages for locale: \(locale)")
                        break // Use first available locale
                    }
                } catch {
                    logger.warning("⚠️ Failed to load locale file for \(locale): \(error)")
                    continue
                }
            }
        }

        // If no localization files found, return original
        guard !localizedMessages.isEmpty else {
            logger.debug("📁 No i18n messages found, keeping original strings")
            return manifest
        }

        // Helper function to process i18n strings
        func localizeString(_ input: String) -> String {
            if input.hasPrefix("__MSG_"), input.hasSuffix("__") {
                let key = String(input.dropFirst(6).dropLast(2)) // Remove __MSG_ and __
                if let message = localizedMessages[key]?["message"] {
                    logger.info("🌐 Localized '\(key)': \(message)")
                    return message
                } else {
                    logger.warning("⚠️ Missing localization for key: \(key)")
                }
            }
            return input
        }

        // Create localized manifest by encoding/decoding with modifications
        do {
            // Encode the original manifest to JSON
            let encoder = JSONEncoder()
            let originalData = try encoder.encode(manifest)

            // Parse as dictionary to modify specific fields
            guard var manifestDict = try JSONSerialization.jsonObject(with: originalData) as? [String: Any] else {
                logger.warning("⚠️ Failed to parse manifest as dictionary")
                return manifest
            }

            // Apply localizations
            manifestDict["name"] = localizeString(manifest.name)

            if let description = manifest.description {
                manifestDict["description"] = localizeString(description)
            }

            // Localize action title if present
            if var action = manifestDict["action"] as? [String: Any],
               let title = action["default_title"] as? String {
                action["default_title"] = localizeString(title)
                manifestDict["action"] = action
            }

            // Localize browser_action title if present (manifest v2)
            if var browserAction = manifestDict["browser_action"] as? [String: Any],
               let title = browserAction["default_title"] as? String {
                browserAction["default_title"] = localizeString(title)
                manifestDict["browser_action"] = browserAction
            }

            // Convert back to data and decode as ExtensionManifest
            let modifiedData = try JSONSerialization.data(withJSONObject: manifestDict)
            let decoder = JSONDecoder()
            let localizedManifest = try decoder.decode(ExtensionManifest.self, from: modifiedData)

            return localizedManifest

        } catch {
            logger.warning("⚠️ Failed to create localized manifest: \(error)")
            return manifest
        }
    }

    /// Process i18n messages for all loaded extensions
    private func processI18nMessages() {
        for (extensionId, var loadedExt) in loadedExtensions {
            do {
                let localizedManifest = try processI18nMessages(loadedExt.manifest, in: loadedExt.url)
                loadedExt.manifest = localizedManifest
                loadedExtensions[extensionId] = loadedExt // Reassign to dictionary since it's a struct
                logger.info("✅ Processed i18n messages for extension: \(loadedExt.manifest.name)")
            } catch {
                logger.error("❌ Failed to process i18n messages for extension: \(extensionId): \(error)")
            }
        }
    }
}

// MARK: - LoadedExtension

/// Represents a loaded extension
public struct LoadedExtension: Identifiable, Equatable {
    public let id: String
    public var manifest: ExtensionManifest // Changed from let to var for i18n updates
    public let url: URL
    public var isEnabled: Bool
    public let installDate: Date

    /// Original Chrome Web Store ID (if installed from Chrome Web Store)
    public let chromeWebStoreId: String?

    public init(
        id: String,
        manifest: ExtensionManifest,
        url: URL,
        isEnabled: Bool,
        installDate: Date = Date(),
        chromeWebStoreId: String? = nil
    ) {
        self.id = id
        self.manifest = manifest
        self.url = url
        self.isEnabled = isEnabled
        self.installDate = installDate
        self.chromeWebStoreId = chromeWebStoreId
    }

    public static func == (lhs: LoadedExtension, rhs: LoadedExtension) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ExtensionRuntimeConfiguration

/// Extension runtime configuration
public struct ExtensionRuntimeConfiguration {
    public let supportedManifestVersions: Set<Int>
    public let maxExtensions: Int
    public let developmentMode: Bool

    public init(supportedManifestVersions: Set<Int>, maxExtensions: Int, developmentMode: Bool) {
        self.supportedManifestVersions = supportedManifestVersions
        self.maxExtensions = maxExtensions
        self.developmentMode = developmentMode
    }

    public static let `default` = ExtensionRuntimeConfiguration(
        supportedManifestVersions: [2, 3],
        maxExtensions: 100,
        developmentMode: true
    )
}

// MARK: - ExtensionRuntimeError

/// Extension runtime errors
public enum ExtensionRuntimeError: Error, LocalizedError {
    case unsupportedManifestVersion(Int)
    case missingFile(String)
    case permissionDenied
    case extensionNotFound(String)
    case invalidManifest
    case installationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedManifestVersion(version):
            "Unsupported manifest version: \(version)"
        case let .missingFile(file):
            "Missing required file: \(file)"
        case .permissionDenied:
            "Permission denied by user"
        case let .extensionNotFound(id):
            "Extension not found: \(id)"
        case .invalidManifest:
            "Invalid extension manifest"
        case let .installationFailed(reason):
            "Installation failed: \(reason)"
        }
    }
}

// MARK: - ExtensionPageInfo

/// Information about an extension page
struct ExtensionPageInfo {
    let extensionId: String
    let pageType: ExtensionPageType
    let relativePath: String
    let loadedExtension: LoadedExtension
}

// MARK: - ExtensionPageType

/// Type of extension page
enum ExtensionPageType {
    case options
    case popup
    case other
}
