//
//  ADKWebView.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit
import OSLog
import SwiftUI
import WebKit

// MARK: - ADKWebView

/// Custom version of WKWebView to avoid needing an extra class for management
@Observable
public class ADKWebView: WKWebView, webViewProtocol {
    public var ownerTab: ADKWebPage?
    public var currentConfiguration: WKWebViewConfiguration
    public var delegate: WKUIDelegate?
    public var navDelegate: WKNavigationDelegate?

    /// Whether this WebView is registered with extensions
    private var isRegisteredWithExtensions = false

    /// Logger for debugging
    private let logger = Logger(subsystem: "com.alto.webkit", category: "ADKWebView")

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        currentConfiguration = configuration
        super.init(frame: frame, configuration: configuration)
        setup()
        registerWithExtensionRuntime()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        if isRegisteredWithExtensions {
            Task { @MainActor in
                ExtensionRuntime.shared.unregisterWebView(self)
            }
        }
    }

    public override func mouseDown(with theEvent: NSEvent) {
        super.mouseDown(with: theEvent)
        ownerTab?.handleMouseDown()
    }

    /// Setup the WebView
    private func setup() {
        logger.info("🔧 Setting up ADKWebView")

        // Set Chrome user agent for Chrome Web Store compatibility
        setupChromeUserAgent()

        // Setup Chrome Web Store navigation delegate
        setupChromeWebStoreNavigation()

        // Verify user agent was set
        verifyUserAgent()
    }

    /// Setup Chrome Web Store compatible navigation
    private func setupChromeWebStoreNavigation() {
        logger.debug("🔧 Setting up Chrome Web Store navigation delegate")

        // Wrap existing navigation delegate with Chrome Web Store compatibility
        let chromeNavDelegate = ChromeWebStoreNavigationDelegate(originalDelegate: navigationDelegate)
        navigationDelegate = chromeNavDelegate

        logger.info("✅ Chrome Web Store navigation delegate configured")
    }

    /// Set Chrome user agent to bypass Web Store restrictions
    private func setupChromeUserAgent() {
        // Use latest Chrome user agent for maximum compatibility
        let chromeUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

        logger.info("🕵️ Setting Chrome user agent: \(chromeUserAgent)")

        // Set custom user agent
        customUserAgent = chromeUserAgent

        // Also set application name to Chrome for additional compatibility
        setValue("Google Chrome", forKey: "applicationNameForUserAgent")

        logger.info("✅ Chrome user agent configured")
    }

    /// Verify the user agent was properly set
    private func verifyUserAgent() {
        // Wait a moment for the user agent to be applied
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.evaluateJavaScript("navigator.userAgent") { result, error in
                if let userAgent = result as? String {
                    self.logger.info("🕵️ Verified user agent: \(userAgent)")

                    // Check if it contains Chrome
                    if userAgent.contains("Chrome") {
                        self.logger.info("✅ User agent contains Chrome - Web Store compatibility OK")
                    } else {
                        self.logger.warning("⚠️ User agent does not contain Chrome - may cause Web Store issues")
                    }
                } else if let error {
                    self.logger.error("❌ Failed to verify user agent: \(error)")
                }
            }
        }
    }

    /// Register this WebView with the extension runtime
    private func registerWithExtensionRuntime() {
        Task { @MainActor in
            logger.debug("📱 Registering WebView with extension runtime")
            await ExtensionRuntime.shared.registerWebView(self)
            isRegisteredWithExtensions = true
            logger.info("✅ WebView registered with extension runtime")

            // Post notification that WebView was created
            NotificationCenter.default.post(
                name: NSNotification.Name("AltoWebViewCreated"),
                object: self
            )
        }
    }

    /// Handle navigation for extension content script injection
    /// - Parameter navigation: Navigation object
    func handleNavigationForExtensions(_ navigation: WKNavigation?) {
        guard let url else { return }

        Task { @MainActor in
            // Register with extension runtime and handle navigation
            await ExtensionRuntime.shared.handleNavigation(in: self, to: url)
        }
    }

    /// Force Chrome user agent for specific URLs (like Chrome Web Store)
    /// - Parameter url: URL being loaded
    public func ensureChromeUserAgentForURL(_ url: URL) {
        let host = url.host?.lowercased() ?? ""

        if host.contains("chromewebstore.google.com") || host.contains("chrome.google.com") {
            logger.info("🌐 Ensuring Chrome user agent for Web Store URL: \(url)")

            // Re-apply Chrome user agent to be sure
            let chromeUserAgent =
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
            customUserAgent = chromeUserAgent

            // Inject comprehensive Chrome client hints and user agent override
            let chromeCompatibilityScript = """
            (function() {
                console.log('🕵️ Applying comprehensive Chrome compatibility for Web Store');

                if (typeof window !== 'undefined' && window.navigator) {
                    // Override navigator properties to match Chrome exactly
                    Object.defineProperty(navigator, 'userAgent', {
                        get: function() { return '\(chromeUserAgent)'; },
                        configurable: false
                    });

                    Object.defineProperty(navigator, 'appName', {
                        get: function() { return 'Netscape'; },
                        configurable: false
                    });

                    Object.defineProperty(navigator, 'appVersion', {
                        get: function() { return '5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'; },
                        configurable: false
                    });

                    Object.defineProperty(navigator, 'vendor', {
                        get: function() { return 'Google Inc.'; },
                        configurable: false
                    });

                    Object.defineProperty(navigator, 'product', {
                        get: function() { return 'Gecko'; },
                        configurable: false
                    });

                    Object.defineProperty(navigator, 'platform', {
                        get: function() { return 'MacIntel'; },
                        configurable: false
                    });

                    // Override User-Agent Client Hints (Critical for Chrome Web Store)
                    Object.defineProperty(navigator, 'userAgentData', {
                        get: function() { 
                            return {
                                brands: [
                                    { brand: "Not?A_Brand", version: "99" },
                                    { brand: "Chromium", version: "131" },
                                    { brand: "Google Chrome", version: "131" }
                                ],
                                mobile: false,
                                platform: "macOS",
                                getHighEntropyValues: function(hints) {
                                    return Promise.resolve({
                                        architecture: "arm",
                                        bitness: "64",
                                        model: "",
                                        platform: "macOS",
                                        platformVersion: "15.5.0",
                                        uaFullVersion: "131.0.6778.86",
                                        wow64: false,
                                        fullVersionList: [
                                            { brand: "Not?A_Brand", version: "99.0.0.0" },
                                            { brand: "Chromium", version: "131.0.6778.86" },
                                            { brand: "Google Chrome", version: "131.0.6778.86" }
                                        ],
                                        formFactors: ["Desktop"]
                                    });
                                }
                            };
                        },
                        configurable: false
                    });

                    // Override Chrome detection properties
                    if (!window.chrome) {
                        window.chrome = {};
                    }

                    // Enhanced chrome.runtime API
                    window.chrome.runtime = {
                        onConnect: { 
                            addListener: function(callback) {
                                console.log('📡 chrome.runtime.onConnect.addListener called');
                            }
                        },
                        onMessage: { 
                            addListener: function(callback) {
                                console.log('📡 chrome.runtime.onMessage.addListener called');
                            }
                        },
                        sendMessage: function(extensionId, message, options, responseCallback) {
                            console.log('📡 chrome.runtime.sendMessage called');
                            if (typeof extensionId === 'object') {
                                // First parameter is message
                                responseCallback = options;
                                options = message;
                                message = extensionId;
                                extensionId = undefined;
                            }
                            // TODO: Implement actual message passing
                        },
                        id: 'chrome-extension-id',
                        getManifest: function() {
                            return { version: '1.0', name: 'Extension' };
                        },
                        getURL: function(path) {
                            return 'chrome-extension://extension-id/' + path;
                        }
                    };

                    // Enhanced chrome.storage API
                    window.chrome.storage = {
                        local: {
                            get: function(keys, callback) {
                                console.log('💾 chrome.storage.local.get called with keys:', keys);
                                // Send message to native Swift implementation
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.local.get',
                                    keys: keys,
                                    callbackId: 'storage_' + Date.now()
                                });
                                // TODO: Handle callback with actual data
                                if (callback) callback({});
                            },
                            set: function(items, callback) {
                                console.log('💾 chrome.storage.local.set called with items:', items);
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.local.set',
                                    items: items,
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback();
                            },
                            remove: function(keys, callback) {
                                console.log('💾 chrome.storage.local.remove called with keys:', keys);
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.local.remove',
                                    keys: keys,
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback();
                            },
                            clear: function(callback) {
                                console.log('💾 chrome.storage.local.clear called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.local.clear',
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback();
                            },
                            getBytesInUse: function(keys, callback) {
                                console.log('💾 chrome.storage.local.getBytesInUse called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.local.getBytesInUse',
                                    keys: keys,
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback(0);
                            }
                        },
                        sync: {
                            get: function(keys, callback) {
                                console.log('☁️ chrome.storage.sync.get called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.sync.get',
                                    keys: keys,
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback({});
                            },
                            set: function(items, callback) {
                                console.log('☁️ chrome.storage.sync.set called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.sync.set',
                                    items: items,
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback();
                            },
                            remove: function(keys, callback) {
                                console.log('☁️ chrome.storage.sync.remove called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.sync.remove',
                                    keys: keys,
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback();
                            },
                            clear: function(callback) {
                                console.log('☁️ chrome.storage.sync.clear called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.sync.clear',
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback();
                            }
                        },
                        session: {
                            get: function(keys, callback) {
                                console.log('🔄 chrome.storage.session.get called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.session.get',
                                    keys: keys,
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback({});
                            },
                            set: function(items, callback) {
                                console.log('🔄 chrome.storage.session.set called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.session.set',
                                    items: items,
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback();
                            },
                            remove: function(keys, callback) {
                                console.log('🔄 chrome.storage.session.remove called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.session.remove',
                                    keys: keys,
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback();
                            },
                            clear: function(callback) {
                                console.log('🔄 chrome.storage.session.clear called');
                                window.webkit.messageHandlers.extensionMessage.postMessage({
                                    action: 'storage.session.clear',
                                    callbackId: 'storage_' + Date.now()
                                });
                                if (callback) callback();
                            }
                        },
                        onChanged: {
                            addListener: function(callback) {
                                console.log('👂 chrome.storage.onChanged.addListener called');
                                // TODO: Implement storage change notifications
                            }
                        }
                    };

                    // Enhanced chrome.tabs API
                    window.chrome.tabs = {
                        query: function(queryInfo, callback) {
                            console.log('📑 chrome.tabs.query called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'tabs.query',
                                queryInfo: queryInfo,
                                callbackId: 'tabs_' + Date.now()
                            });
                            if (callback) callback([]);
                        },
                        create: function(createProperties, callback) {
                            console.log('📑 chrome.tabs.create called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'tabs.create',
                                createProperties: createProperties,
                                callbackId: 'tabs_' + Date.now()
                            });
                            if (callback) callback({});
                        },
                        update: function(tabId, updateProperties, callback) {
                            console.log('📑 chrome.tabs.update called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'tabs.update',
                                tabId: tabId,
                                updateProperties: updateProperties,
                                callbackId: 'tabs_' + Date.now()
                            });
                            if (callback) callback({});
                        },
                        remove: function(tabIds, callback) {
                            console.log('📑 chrome.tabs.remove called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'tabs.remove',
                                tabIds: Array.isArray(tabIds) ? tabIds : [tabIds],
                                callbackId: 'tabs_' + Date.now()
                            });
                            if (callback) callback();
                        }
                    };

                    // chrome.alarms API
                    window.chrome.alarms = {
                        create: function(name, alarmInfo, callback) {
                            console.log('⏰ chrome.alarms.create called');
                            if (typeof name === 'object') {
                                callback = alarmInfo;
                                alarmInfo = name;
                                name = undefined;
                            }
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'alarms.create',
                                name: name,
                                alarmInfo: alarmInfo,
                                callbackId: 'alarms_' + Date.now()
                            });
                            if (callback) callback();
                        },
                        get: function(name, callback) {
                            console.log('⏰ chrome.alarms.get called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'alarms.get',
                                name: name,
                                callbackId: 'alarms_' + Date.now()
                            });
                            if (callback) callback(null);
                        },
                        getAll: function(callback) {
                            console.log('⏰ chrome.alarms.getAll called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'alarms.getAll',
                                callbackId: 'alarms_' + Date.now()
                            });
                            if (callback) callback([]);
                        },
                        clear: function(name, callback) {
                            console.log('⏰ chrome.alarms.clear called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'alarms.clear',
                                name: name,
                                callbackId: 'alarms_' + Date.now()
                            });
                            if (callback) callback(false);
                        },
                        clearAll: function(callback) {
                            console.log('⏰ chrome.alarms.clearAll called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'alarms.clearAll',
                                callbackId: 'alarms_' + Date.now()
                            });
                            if (callback) callback(false);
                        },
                        onAlarm: {
                            addListener: function(callback) {
                                console.log('👂 chrome.alarms.onAlarm.addListener called');
                                // TODO: Implement alarm event notifications
                            }
                        }
                    };

                    // chrome.notifications API
                    window.chrome.notifications = {
                        create: function(notificationId, options, callback) {
                            console.log('🔔 chrome.notifications.create called');
                            if (typeof notificationId === 'object') {
                                callback = options;
                                options = notificationId;
                                notificationId = undefined;
                            }
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'notifications.create',
                                notificationId: notificationId,
                                options: options,
                                callbackId: 'notifications_' + Date.now()
                            });
                            if (callback) callback('notification-id');
                        },
                        update: function(notificationId, options, callback) {
                            console.log('🔔 chrome.notifications.update called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'notifications.update',
                                notificationId: notificationId,
                                options: options,
                                callbackId: 'notifications_' + Date.now()
                            });
                            if (callback) callback(true);
                        },
                        clear: function(notificationId, callback) {
                            console.log('🔔 chrome.notifications.clear called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'notifications.clear',
                                notificationId: notificationId,
                                callbackId: 'notifications_' + Date.now()
                            });
                            if (callback) callback(true);
                        },
                        getAll: function(callback) {
                            console.log('🔔 chrome.notifications.getAll called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'notifications.getAll',
                                callbackId: 'notifications_' + Date.now()
                            });
                            if (callback) callback([]);
                        },
                        getPermissionLevel: function(callback) {
                            console.log('🔔 chrome.notifications.getPermissionLevel called');
                            window.webkit.messageHandlers.extensionMessage.postMessage({
                                action: 'notifications.getPermissionLevel',
                                callbackId: 'notifications_' + Date.now()
                            });
                            if (callback) callback('granted');
                        }
                    };

                    // chrome.webRequest API (limited implementation for content scripts)
                    window.chrome.webRequest = {
                        onBeforeRequest: {
                            addListener: function(callback, filter, extraInfoSpec) {
                                console.log('🌐 chrome.webRequest.onBeforeRequest.addListener called');
                                // Note: webRequest API is typically only available in background scripts
                                // with proper permissions
                            }
                        },
                        onBeforeSendHeaders: {
                            addListener: function(callback, filter, extraInfoSpec) {
                                console.log('🌐 chrome.webRequest.onBeforeSendHeaders.addListener called');
                            }
                        },
                        onResponseStarted: {
                            addListener: function(callback, filter, extraInfoSpec) {
                                console.log('🌐 chrome.webRequest.onResponseStarted.addListener called');
                            }
                        },
                        onCompleted: {
                            addListener: function(callback, filter, extraInfoSpec) {
                                console.log('🌐 chrome.webRequest.onCompleted.addListener called');
                            }
                        }
                    };

                    console.log('✅ Chrome compatibility applied successfully');
                    console.log('🕵️ Navigator user agent:', navigator.userAgent);
                    console.log('🕵️ Navigator vendor:', navigator.vendor);
                    console.log('🕵️ Navigator platform:', navigator.platform);
                    console.log('🕵️ Chrome object:', !!window.chrome);

                    // Test User-Agent Client Hints
                    if (navigator.userAgentData) {
                        console.log('🕵️ User-Agent Client Hints available');
                        navigator.userAgentData.getHighEntropyValues(['architecture', 'bitness', 'model', 'platform', 'platformVersion', 'uaFullVersion', 'wow64', 'fullVersionList', 'formFactors'])
                            .then(data => console.log('🕵️ High entropy values:', data))
                            .catch(err => console.log('⚠️ High entropy values error:', err));
                    } else {
                        console.log('⚠️ User-Agent Client Hints not available');
                    }
                }
            })();
            """

            let userScript = WKUserScript(
                source: chromeCompatibilityScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )

            // Remove any existing user agent scripts to avoid duplicates
            let existingScripts = configuration.userContentController.userScripts
            for script in existingScripts {
                if script.source.contains("Chrome compatibility applied successfully") {
                    configuration.userContentController.removeAllUserScripts()
                    break
                }
            }

            configuration.userContentController.addUserScript(userScript)
            logger.info("✅ Chrome compatibility script injected")
        }
    }

    /// Add Chrome client hints to network requests for Web Store compatibility
    public func addChromeClientHintsForWebStore() {
        // This will be handled by the navigation delegate to add proper headers
        logger.debug("🔧 Chrome client hints setup prepared")
    }
}

extension WKWebView {
    /// WKWebView's `configuration` is marked with @NSCopying.
    /// So everytime you try to access it, it creates a copy of it, which is most likely not what we want.
    var configurationWithoutMakingCopy: WKWebViewConfiguration {
        (self as? ADKWebView)?.currentConfiguration ?? configuration
    }
}

public protocol webViewProtocol: WKWebView {
    var currentConfiguration: WKWebViewConfiguration { get set }
    var delegate: WKUIDelegate? { get set }
    var navDelegate: WKNavigationDelegate? { get set }
}

// MARK: - Extension Integration

extension ADKWebView {
    /// Handle navigation completion for extension integration
    func notifyExtensionNavigationCompleted(to url: URL) {
        logger.info("🧭 Navigation completed to: \(url.absoluteString)")

        Task { @MainActor in
            // Post notification that can be caught by AltoState
            NotificationCenter.default.post(
                name: .webViewDidFinishNavigation,
                object: self,
                userInfo: ["url": url]
            )

            // Handle normal extension navigation
            if let extensionRuntime = ExtensionRuntime.shared as? ExtensionRuntime {
                logger.debug("🔌 Proceeding with extension navigation handling")
                await extensionRuntime.handleNavigation(in: self, to: url)
            } else {
                logger.warning("⚠️ Extension runtime not available")
            }
        }
    }
}

// MARK: - Chrome Web Store Navigation Delegate

/// Custom navigation delegate to add Chrome client hints for Web Store compatibility
public class ChromeWebStoreNavigationDelegate: NSObject, WKNavigationDelegate {
    private let logger = Logger(subsystem: "com.alto.webkit", category: "ChromeWebStoreNav")
    private weak var originalDelegate: WKNavigationDelegate?

    init(originalDelegate: WKNavigationDelegate?) {
        self.originalDelegate = originalDelegate
        super.init()
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> ()
    ) {
        let url = navigationAction.request.url
        let host = url?.host?.lowercased() ?? ""

        // Intercept Chrome Web Store requests to add proper headers
        if host.contains("chromewebstore.google.com") || host.contains("chrome.google.com") {
            logger.info("🌐 Intercepting Chrome Web Store request: \(url?.absoluteString ?? "")")

            // Create new request with Chrome client hints
            let originalRequest = navigationAction.request
            let mutableRequest = (originalRequest as NSURLRequest).mutableCopy() as! NSMutableURLRequest

            // Add Chrome client hint headers (Critical for Web Store compatibility)
            mutableRequest.setValue(
                "\"Not?A_Brand\";v=\"99\", \"Chromium\";v=\"131\", \"Google Chrome\";v=\"131\"",
                forHTTPHeaderField: "sec-ch-ua"
            )
            mutableRequest.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
            mutableRequest.setValue("\"131.0.6778.86\"", forHTTPHeaderField: "sec-ch-ua-full-version")
            mutableRequest.setValue("\"arm\"", forHTTPHeaderField: "sec-ch-ua-arch")
            mutableRequest.setValue("\"macOS\"", forHTTPHeaderField: "sec-ch-ua-platform")
            mutableRequest.setValue("\"15.5.0\"", forHTTPHeaderField: "sec-ch-ua-platform-version")
            mutableRequest.setValue("\"\"", forHTTPHeaderField: "sec-ch-ua-model")
            mutableRequest.setValue("\"64\"", forHTTPHeaderField: "sec-ch-ua-bitness")
            mutableRequest.setValue("?0", forHTTPHeaderField: "sec-ch-ua-wow64")
            mutableRequest.setValue(
                "\"Not?A_Brand\";v=\"99.0.0.0\", \"Chromium\";v=\"131.0.6778.86\", \"Google Chrome\";v=\"131.0.6778.86\"",
                forHTTPHeaderField: "sec-ch-ua-full-version-list"
            )
            mutableRequest.setValue("\"Desktop\"", forHTTPHeaderField: "sec-ch-ua-form-factors")

            // Add additional Chrome headers
            mutableRequest.setValue("1", forHTTPHeaderField: "DNT")
            mutableRequest.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
            mutableRequest.setValue(
                "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
                forHTTPHeaderField: "Accept"
            )
            mutableRequest.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
            mutableRequest.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
            mutableRequest.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
            mutableRequest.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
            mutableRequest.setValue("gzip, deflate, br, zstd", forHTTPHeaderField: "Accept-Encoding")
            mutableRequest.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

            // Ensure Chrome user agent
            let chromeUserAgent =
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
            mutableRequest.setValue(chromeUserAgent, forHTTPHeaderField: "User-Agent")

            logger.info("✅ Added Chrome client hints to Web Store request")
            logger.debug("🔍 Headers added: sec-ch-ua, sec-ch-ua-mobile, sec-ch-ua-platform, etc.")

            // Load the modified request
            webView.load(mutableRequest as URLRequest)
            decisionHandler(.cancel)
            return
        }

        // Forward to original delegate or allow by default
        if let originalDelegate {
            originalDelegate.webView?(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
        } else {
            decisionHandler(.allow)
        }
    }

    // Forward other delegate methods to original delegate
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didStartProvisionalNavigation: navigation)
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didCommit: navigation)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didFinish: navigation)

        // Handle extension navigation when navigation finishes
        if let adkWebView = webView as? ADKWebView, let url = webView.url {
            adkWebView.handleNavigationForExtensions(navigation)
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        originalDelegate?.webView?(webView, didFail: navigation, withError: error)
    }
}
