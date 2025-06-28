//
//  ChromeWebStoreIntegration.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog
import WebKit

// MARK: - ChromeWebStoreIntegration

/// Handles Chrome Web Store integration and page manipulation
@MainActor
public class ChromeWebStoreIntegration {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeWebStoreIntegration")

    /// Shared instance
    public static let shared = ChromeWebStoreIntegration()

    /// Extension runtime reference
    private weak var extensionRuntime: ExtensionRuntime?

    private init() {
        logger.info("🌐 Chrome Web Store integration initialized")
    }

    /// Set extension runtime reference
    /// - Parameter runtime: Extension runtime instance
    public func setExtensionRuntime(_ runtime: ExtensionRuntime) {
        extensionRuntime = runtime
        logger.info("🔗 Extension runtime connected to Chrome Web Store integration")
    }

    // MARK: - Web Store Detection

    /// Detect and extract extension information from Chrome Web Store URL
    /// - Parameter url: URL to analyze
    /// - Returns: Extension info if detected, nil otherwise
    public func detectExtensionPage(_ url: URL) -> WebStoreExtensionInfo? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path

        logger.debug("🔍 Checking extension URL - Host: \(host), Path: \(path)")

        // Check if it's a Chrome Web Store URL
        guard host.contains("chromewebstore.google.com") else {
            logger.debug("❌ Not a Chrome Web Store URL")
            return nil
        }

        logger.debug("📋 Is extension URL: true")

        // Extract extension ID using regex patterns
        let patterns = [
            "chromewebstore\\.google\\.com/detail/[^/]+/([a-z]{32})", // /detail/extension-name/ID
            "chromewebstore\\.google\\.com/detail/([a-z]{32})", // /detail/ID
            "chrome\\.google\\.com/webstore/detail/[^/]+/([a-z]{32})", // Legacy format
            "chrome\\.google\\.com/webstore/detail/([a-z]{32})" // Legacy direct ID
        ]

        for (index, pattern) in patterns.enumerated() {
            logger.debug("🔍 Trying pattern \(index + 1): \(pattern)")

            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: url.absoluteString.count)
                if let match = regex.firstMatch(in: url.absoluteString, options: [], range: range) {
                    let extensionIdRange = match.range(at: 1)
                    if extensionIdRange.location != NSNotFound {
                        let extensionId = (url.absoluteString as NSString).substring(with: extensionIdRange)

                        logger.info("🎯 Detected Chrome Web Store extension page!")
                        logger.info("🆔 Extension ID: \(extensionId)")
                        logger.info("🔗 URL: \(url.absoluteString)")

                        // Check if extension is already installed by checking against ExtensionRuntime
                        let isInstalled = checkIfExtensionInstalled(extensionId: extensionId)
                        logger.info("📱 Extension installed: \(isInstalled)")

                        return WebStoreExtensionInfo(
                            extensionId: extensionId,
                            url: url.absoluteString,
                            isInstalled: isInstalled
                        )
                    }
                }
            }
        }

        logger.debug("❌ Could not extract extension ID from URL")
        return nil
    }

    /// Check if an extension is already installed
    /// - Parameter extensionId: Chrome Web Store extension ID
    /// - Returns: true if installed, false otherwise
    private func checkIfExtensionInstalled(extensionId: String) -> Bool {
        // Check against loaded extensions in ExtensionRuntime
        let extensionRuntime = ExtensionRuntime.shared
        let loadedExtensions = extensionRuntime.loadedExtensions

        // Check if any loaded extension matches this Chrome Web Store ID
        // We need to check both the generated ID and potential mapping
        for loadedExtension in loadedExtensions.values {
            // Check if the loaded extension has metadata about its Chrome Web Store origin
            if let metadata = ExtensionStorage.shared.getExtensionMetadata(loadedExtension.id),
               metadata.installationSource == .chromeWebStore,
               metadata.originalId == extensionId {
                return true
            }

            // Also check if the Chrome Web Store ID is stored in the LoadedExtension
            if let chromeId = loadedExtension.chromeWebStoreId,
               chromeId == extensionId {
                return true
            }
        }

        return false
    }

    /// Check if URL is a Chrome Web Store URL
    /// - Parameter url: URL to check
    /// - Returns: Whether it's a web store URL
    public func isWebStoreURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            logger.debug("🔍 URL has no host: \(url.absoluteString)")
            return false
        }

        let isWebStore = host.contains("chromewebstore.google.com") ||
            host.contains("chrome.google.com")

        logger.debug("🔍 Is Web Store URL (\(host)): \(isWebStore)")
        return isWebStore
    }

    // MARK: - Page Manipulation

    /// Inject Alto extension management into Chrome Web Store page
    /// - Parameters:
    ///   - webView: WebView displaying the page
    ///   - extensionInfo: Extension information
    public func injectAltoControls(into webView: WKWebView, extensionInfo: WebStoreExtensionInfo) {
        logger.info("💉 Injecting Alto controls into Chrome Web Store page")
        logger.debug("💉 Extension ID: \(extensionInfo.extensionId)")
        logger.debug("💉 Is installed: \(extensionInfo.isInstalled)")

        // Check if already injected to prevent duplicates
        webView.evaluateJavaScript("window.altoControlsInjected") { [weak self] result, error in
            guard let self else { return }

            if let alreadyInjected = result as? Bool, alreadyInjected {
                logger.info("ℹ️ Alto controls already injected, skipping duplicate injection")
                return
            }

            // First check current user agent
            webView.evaluateJavaScript("navigator.userAgent") { result, error in
                if let userAgent = result as? String {
                    self.logger.info("🕵️ Current user agent: \(userAgent)")
                } else if let error {
                    self.logger.error("❌ Failed to get user agent: \(error)")
                }
            }

            // Ensure message handlers are set up first
            setupMessageHandlers(for: webView)

            // Proceed with injection
            performActualInjection(webView: webView, extensionInfo: extensionInfo)
        }
    }

    /// Perform the actual injection after duplicate check
    private func performActualInjection(webView: WKWebView, extensionInfo: WebStoreExtensionInfo) {
        let script = generateInjectionScript(for: extensionInfo)

        // Execute the injection script
        webView.evaluateJavaScript(script, completionHandler: handleInjectionResult)
    }

    private func handleInjectionResult(result: Any?, error: Error?) {
        if let error {
            logger.error("❌ Failed to inject Alto controls: \(error)")

            if let jsError = error as NSError? {
                logger.error("❌ Error domain: \(jsError.domain)")
                logger.error("❌ Error code: \(jsError.code)")
                logger.error("❌ Error info: \(jsError.userInfo)")
            }
        } else {
            logger.info("✅ Alto controls injected successfully")
            if let result {
//                self.logger.debug("✅ Script result: \(result)")
            }
        }
    }

    /// Generate JavaScript injection script for Web Store pages
    /// - Parameter extensionInfo: Extension information
    /// - Returns: JavaScript code to inject
    private func generateInjectionScript(for extensionInfo: WebStoreExtensionInfo) -> String {
        let isInstalled = extensionInfo.isInstalled
        let extensionId = extensionInfo.extensionId

        logger.debug("🔧 Generating injection script for extension: \(extensionId)")
        logger.debug("🔧 Extension is installed: \(isInstalled)")

        return """
        (function() {
            // Mark as injected to prevent duplicates
            window.altoControlsInjected = true;

            console.log('🔌 Alto Extension Manager - Starting immediate injection into Chrome Web Store');
            console.log('🆔 Target extension ID: \(extensionId)');
            console.log('📱 Extension installed: \(isInstalled)');
            console.log('🕵️ User agent:', navigator.userAgent);

            try {
                // First, modify the user agent warning message immediately
                modifyUserAgentWarning();

                // Inject button immediately, then set up observer for dynamic content
                injectButtonImmediately();

                // Set up observer for any dynamic content changes
                setupDynamicContentObserver();

                console.log('✅ Alto injection completed successfully');
                return 'injection_success';
            } catch (error) {
                console.error('❌ Alto injection failed:', error);
                return 'injection_failed: ' + error.message;
            }
        })();

        function modifyUserAgentWarning() {
            console.log('🔧 Starting user agent warning modification...');

            // Find and hide "Switch to Chrome" messages
            const allElements = document.querySelectorAll('*');
            let warningsFound = 0;

            allElements.forEach(element => {
                const textContent = element.textContent || '';
                const innerHTML = element.innerHTML || '';

                if (textContent.includes('Switch to Chrome') || 
                    textContent.includes('Chrome Web Store') ||
                    innerHTML.includes('Switch to Chrome')) {

                    console.log('🔧 Found Chrome warning element:', {
                        tag: element.tagName,
                        text: textContent.substring(0, 100),
                        classes: element.className
                    });

                    element.innerHTML = element.innerHTML.replace(
                        /Switch to Chrome to install extensions/gi,
                        'Install extensions directly in Alto Browser'
                    );
                    element.innerHTML = element.innerHTML.replace(
                        /Switch to Chrome/gi,
                        'Use Alto Browser'
                    );

                    warningsFound++;
                }
            });

            console.log('🔧 Modified ' + warningsFound + ' Chrome warning messages');
        }

        function injectButtonImmediately() {
            console.log('🚀 Starting immediate button injection...');

            // Try to find install buttons in the current DOM state
            const buttonSelectors = [
                'button[jscontroller="O626Fe"][jsname="wQO0od"]',
                'button.UywwFc-LgbsSe[jscontroller="O626Fe"]',
                'button:has(.UywwFc-vQzf8d)',
                'button:has(span[jsname="V67aGc"])'
            ];

            let buttonFound = false;

            for (const selector of buttonSelectors) {
                if (buttonFound) break;

                try {
                    const buttons = document.querySelectorAll(selector);
                    console.log('🔍 Found ' + buttons.length + ' elements with selector: ' + selector);

                    for (const button of buttons) {
                        if (buttonFound) break;

                        const text = (button.textContent || '').trim().toLowerCase();
                        const hasInstallText = text.includes('add to chrome') || 
                                             text.includes('remove from chrome') ||
                                             text.includes('added to chrome');

                        if (hasInstallText && !button.classList.contains('alto-hijacked-button')) {
                            console.log('✅ Found install button to hijack immediately:', {
                                text: button.textContent ? button.textContent.trim() : '',
                                selector: selector
                            });

                            replaceInstallButton(button);
                            buttonFound = true;
                            break;
                        }
                    }
                } catch (error) {
                    console.error('❌ Error with immediate selector ' + selector + ':', error);
                }
            }

            if (!buttonFound) {
                console.log('⚠️ No install button found immediately, will check dynamically...');
            }
        }

        function setupDynamicContentObserver() {
            console.log('👁️ Setting up dynamic content observer...');

            // Set up MutationObserver to watch for new buttons
            const observer = new MutationObserver((mutations) => {
                let shouldCheck = false;

                mutations.forEach((mutation) => {
                    if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                        // Check if any added nodes contain button elements
                        for (const node of mutation.addedNodes) {
                            if (node.nodeType === Node.ELEMENT_NODE) {
                                const element = node;
                                if (element.tagName === 'BUTTON' || element.querySelector('button')) {
                                    shouldCheck = true;
                                    break;
                                }
                            }
                        }
                    }
                });

                if (shouldCheck) {
                    console.log('🔄 New buttons detected, checking for install buttons...');
                    // Debounce the checks
                    clearTimeout(window.altoButtonCheckTimeout);
                    window.altoButtonCheckTimeout = setTimeout(() => {
                        findAndReplaceNewButtons();
                    }, 500);
                }
            });

            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
        }

        function findAndReplaceNewButtons() {
            console.log('🔍 Checking for newly added install buttons...');

            const buttonSelectors = [
                'button[jscontroller="O626Fe"][jsname="wQO0od"]:not(.alto-hijacked-button)',
                'button.UywwFc-LgbsSe[jscontroller="O626Fe"]:not(.alto-hijacked-button)',
                'button:has(.UywwFc-vQzf8d):not(.alto-hijacked-button)'
            ];

            for (const selector of buttonSelectors) {
                try {
                    const buttons = document.querySelectorAll(selector);

                    buttons.forEach((button) => {
                        const text = (button.textContent || '').trim().toLowerCase();
                        const hasInstallText = text.includes('add to chrome') || 
                                             text.includes('remove from chrome') ||
                                             text.includes('added to chrome');

                        if (hasInstallText) {
                            console.log('✅ Found new install button to hijack:', {
                                text: button.textContent ? button.textContent.trim() : '',
                                selector: selector
                            });

                            replaceInstallButton(button);
                        }
                    });
                } catch (error) {
                    console.error('❌ Error checking new buttons with selector ' + selector + ':', error);
                }
            }
        }

        function replaceInstallButton(originalButton) {
            console.log('🔄 Completely replacing install button:', originalButton.textContent ? originalButton.textContent.trim() : '');

            // Mark as processed to prevent duplicate processing
            originalButton.classList.add('alto-hijacked-button');

            // Get the original button's parent and position
            const parent = originalButton.parentNode;
            const nextSibling = originalButton.nextSibling;

            // Create our Alto button with Chrome styling
            const altoButton = document.createElement('button');

            // Copy all classes from original button to maintain styling
            altoButton.className = originalButton.className;

            // Remove the Chrome-specific controllers and add our identifier
            altoButton.removeAttribute('jscontroller');
            altoButton.removeAttribute('jsname');
            altoButton.setAttribute('data-alto-button', 'true');

            // Create the button content structure matching Chrome's layout
            const buttonContent = originalButton.innerHTML;
            altoButton.innerHTML = buttonContent;

            // Determine button state and appearance
            const isInstalled = \(isInstalled ? "true" : "false");

            // Update the text span to Alto version
            const textSpan = altoButton.querySelector('.UywwFc-vQzf8d') || 
                           altoButton.querySelector('span[jsname="V67aGc"]') ||
                           altoButton.querySelector('span');

            if (textSpan) {
                const originalText = (originalButton.textContent || '').trim().toLowerCase();

                if (isInstalled) {
                    // Show "Added to Alto" for installed extensions
                    textSpan.textContent = 'Added to Alto';

                    // Make button look disabled/different for installed state
                    altoButton.style.opacity = '0.7';
                    altoButton.style.cursor = 'default';
                    altoButton.disabled = true;

                    // Add checkmark icon if possible
                    const checkmark = document.createElement('span');
                    checkmark.innerHTML = '✓ ';
                    checkmark.style.marginRight = '4px';
                    textSpan.insertBefore(checkmark, textSpan.firstChild);

                } else {
                    // Show "Add to Alto" for uninstalled extensions
                    if (originalText.includes('add to chrome')) {
                        textSpan.textContent = 'Add to Alto';
                    } else if (originalText.includes('remove from chrome')) {
                        textSpan.textContent = 'Remove from Alto';
                    } else if (originalText.includes('added to chrome')) {
                        textSpan.textContent = 'Added to Alto';
                    } else {
                        textSpan.textContent = 'Add to Alto';
                    }
                }

                console.log('✅ Updated button text to:', textSpan.textContent);
            }

            // Add our click handler only for uninstalled extensions
            if (!isInstalled) {
                altoButton.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    e.stopImmediatePropagation();

                    console.log('🔌 Alto button clicked for extension: \(extensionId)');

                    try {
                        console.log('📦 Requesting extension installation with confirmation...');
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.altoExtension) {
                            window.webkit.messageHandlers.altoExtension.postMessage({
                                action: 'requestInstall',
                                extensionId: '\(extensionId)',
                                url: window.location.href
                            });
                        } else {
                            console.error('❌ Message handler not available');
                        }
                    } catch (error) {
                        console.error('❌ Error handling button click:', error);
                    }
                });
            } else {
                // For installed extensions, add click handler to open settings
                altoButton.addEventListener('click', function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    e.stopImmediatePropagation();

                    console.log('⚙️ Opening extension settings for: \(extensionId)');

                    try {
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.altoExtension) {
                            window.webkit.messageHandlers.altoExtension.postMessage({
                                action: 'settings',
                                extensionId: '\(extensionId)'
                            });
                        } else {
                            console.error('❌ Message handler not available');
                        }
                    } catch (error) {
                        console.error('❌ Error handling settings click:', error);
                    }
                });
            }

            // Hide the original button completely
            originalButton.style.display = 'none';

            // Insert our button in the same position
            if (nextSibling) {
                parent.insertBefore(altoButton, nextSibling);
            } else {
                parent.appendChild(altoButton);
            }

            console.log('✅ Successfully replaced install button with Alto button (installed: ' + isInstalled + ')');
        }
        """
    }

    // MARK: - Message Handling

    /// Setup WebView message handler for Alto extension actions
    /// - Parameter webView: WebView to setup handlers for
    public func setupMessageHandlers(for webView: WKWebView) {
        // Check if handler already exists to avoid duplicates
        let userContentController = webView.configuration.userContentController
        let existingHandlers = userContentController.userScripts

        // Remove existing altoExtension handler if present
        userContentController.removeScriptMessageHandler(forName: "altoExtension")

        // Add fresh handler
        let handler = AltoExtensionMessageHandler()
        userContentController.add(handler, name: "altoExtension")

        logger.debug("📨 Message handlers setup for WebView")
    }

    // MARK: - Extension Actions

    /// Handle extension installation from Web Store
    /// - Parameters:
    ///   - extensionId: Extension ID to install
    ///   - webStoreURL: Chrome Web Store URL
    public func installExtension(extensionId: String, from webStoreURL: URL) {
        logger.info("📦 Installing extension from Web Store: \(extensionId)")
        logger.info("🔗 Install URL: \(webStoreURL.absoluteString)")

        Task {
            do {
                guard let runtime = extensionRuntime else {
                    logger.error("❌ Extension runtime not available")
                    return
                }

                _ = try await runtime.installExtension(from: webStoreURL)
                logger.info("✅ Extension installed successfully: \(extensionId)")

                // Update the page to reflect installation
                await updatePageInstallationStatus(extensionId: extensionId, isInstalled: true)

            } catch {
                logger.error("❌ Failed to install extension: \(error)")
            }
        }
    }

    /// Handle extension uninstallation
    /// - Parameter extensionId: Extension ID to uninstall
    public func uninstallExtension(extensionId: String) {
        logger.info("🗑️ Uninstalling extension: \(extensionId)")

        do {
            try ExtensionStorage.shared.uninstallExtension(extensionId)
            logger.info("✅ Extension uninstalled successfully: \(extensionId)")

            // Update the page to reflect uninstallation
            Task {
                await updatePageInstallationStatus(extensionId: extensionId, isInstalled: false)
            }

        } catch {
            logger.error("❌ Failed to uninstall extension: \(error)")
        }
    }

    /// Open extension settings for a specific extension
    /// - Parameter extensionId: Extension ID
    public func openExtensionSettings(extensionId: String) {
        logger.info("⚙️ Opening extension settings for Chrome Web Store extension: \(extensionId)")

        // Find the corresponding loaded extension by Chrome Web Store ID
        let extensionRuntime = ExtensionRuntime.shared
        let loadedExtensions = extensionRuntime.loadedExtensions

        var targetExtensionId: String?

        // Find extension by Chrome Web Store ID
        for (loadedId, loadedExtension) in loadedExtensions {
            if let chromeId = loadedExtension.chromeWebStoreId, chromeId == extensionId {
                targetExtensionId = loadedId
                break
            }

            // Also check metadata if available
            if let metadata = ExtensionStorage.shared.getExtensionMetadata(loadedId),
               metadata.originalId == extensionId {
                targetExtensionId = loadedId
                break
            }
        }

        guard let foundExtensionId = targetExtensionId else {
            logger.warning("⚠️ Could not find loaded extension for Chrome Web Store ID: \(extensionId)")
            return
        }

        logger.info("🎯 Found corresponding extension: \(foundExtensionId)")

        // Check for duplicate calls
        let currentTime = Date().timeIntervalSince1970
        let deduplicationKey = "openExtensionSettings_\(foundExtensionId)"

        if let lastCallTime = UserDefaults.standard.object(forKey: deduplicationKey) as? TimeInterval,
           currentTime - lastCallTime < 1.0 {
            logger
                .info(
                    "🔄 Skipping duplicate openExtensionSettings call from ChromeWebStoreIntegration for \(foundExtensionId)"
                )
            return
        }

        UserDefaults.standard.set(currentTime, forKey: deduplicationKey)

        // Send notification to open extension settings
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenExtensionSettings"),
                object: nil,
                userInfo: [
                    "extensionId": foundExtensionId,
                    "source": "chrome-web-store",
                    "handledByRuntime": true
                ]
            )
        }
    }

    /// Update page installation status
    /// - Parameters:
    ///   - extensionId: Extension ID
    ///   - isInstalled: New installation status
    private func updatePageInstallationStatus(extensionId: String, isInstalled: Bool) async {
        // This would update the current Web Store page to reflect the new status
        logger.debug("🔄 Updating page installation status: \(extensionId) -> \(isInstalled)")
    }

    /// Handle install request by showing confirmation dialog
    /// - Parameters:
    ///   - extensionId: Extension ID to install
    ///   - url: Chrome Web Store URL
    public func handleInstallRequest(extensionId: String, from url: URL) {
        logger.info("📦 Handling install request for extension: \(extensionId)")
        logger.info("🔗 Install request URL: \(url.absoluteString)")

        Task { @MainActor in
            do {
                // Get extension info from Chrome Web Store
                let (extensionName, permissions) = try await fetchExtensionInfo(extensionId: extensionId, url: url)

                // Show confirmation dialog
                showInstallConfirmation(
                    extensionId: extensionId,
                    extensionName: extensionName,
                    permissions: permissions,
                    url: url
                )

            } catch {
                logger.error("❌ Failed to fetch extension info: \(error)")
                // Fallback to direct installation if we can't get info
                installExtension(extensionId: extensionId, from: url)
            }
        }
    }

    /// Fetch extension information from Chrome Web Store
    /// - Parameters:
    ///   - extensionId: Extension ID
    ///   - url: Chrome Web Store URL
    /// - Returns: Extension name and permissions
    private func fetchExtensionInfo(extensionId: String, url: URL) async throws -> (String, [String]) {
        logger.info("🔍 Fetching extension info from Chrome Web Store: \(extensionId)")

        return try await withCheckedThrowingContinuation { continuation in
            let permissionFetcher = ChromeExtensionPermissionFetcher()

            permissionFetcher.fetchPermissions(extensionId: extensionId) { permissions in
                // For now, we'll extract the extension name from the URL or use a placeholder
                // In a future version, we could also scrape the extension name from the same page
                let extensionName = self.extractExtensionNameFromURL(url) ?? "Extension"

                self.logger.info("✅ Fetched extension info - Name: \(extensionName), Permissions: \(permissions.count)")

                continuation.resume(returning: (extensionName, permissions))
            }
        }
    }

    /// Extract extension name from Chrome Web Store URL
    /// - Parameter url: Chrome Web Store URL
    /// - Returns: Extension name if found
    private func extractExtensionNameFromURL(_ url: URL) -> String? {
        // Extract name from URLs like:
        // https://chromewebstore.google.com/detail/random-user-agent-switche/einpaelgookohagofgnnkcfjbkkgepnp
        let pathComponents = url.pathComponents

        if pathComponents.count >= 3,
           pathComponents[1] == "detail",
           !pathComponents[2].isEmpty,
           pathComponents[2] != "/" {
            // Convert URL-friendly name back to readable format
            let urlName = pathComponents[2]
            let readableName = urlName
                .replacingOccurrences(of: "-", with: " ")
                .components(separatedBy: " ")
                .map(\.capitalized)
                .joined(separator: " ")

            logger.debug("📛 Extracted extension name from URL: \(readableName)")
            return readableName
        }

        return nil
    }

    /// Show installation confirmation dialog
    /// - Parameters:
    ///   - extensionId: Extension ID
    ///   - extensionName: Extension name
    ///   - permissions: Required permissions
    ///   - url: Chrome Web Store URL
    private func showInstallConfirmation(
        extensionId: String,
        extensionName: String,
        permissions: [String],
        url: URL
    ) {
        logger.info("🔔 Showing installation confirmation for: \(extensionName)")

        DispatchQueue.main.async {
            // Get the main window to present the dialog
            guard let mainWindow = NSApplication.shared.mainWindow else {
                self.logger.error("❌ No main window available for dialog")
                // Fallback to direct installation
                self.installExtension(extensionId: extensionId, from: url)
                return
            }

            // Create the confirmation dialog
            let dialog = NSAlert()
            dialog.messageText = "Add the \"\(extensionName)\" extension to Alto?"

            if permissions.isEmpty {
                dialog.informativeText = "This extension requires no special permissions."
            } else {
                let permissionList = permissions.map { "• \($0)" }.joined(separator: "\n")
                dialog.informativeText = "This extension requires the following permissions:\n\n\(permissionList)"
            }

            dialog.addButton(withTitle: "Add Extension")
            dialog.addButton(withTitle: "Cancel")
            dialog.alertStyle = .informational

            // Show the dialog
            dialog.beginSheetModal(for: mainWindow) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    // User confirmed installation
                    self?.logger.info("✅ User confirmed extension installation")
                    self?.installExtension(extensionId: extensionId, from: url)
                } else {
                    // User cancelled
                    self?.logger.info("🚫 User cancelled extension installation")
                }
            }
        }
    }
}

// MARK: - WebStoreExtensionInfo

/// Information about a Chrome Web Store extension page
public struct WebStoreExtensionInfo {
    public let extensionId: String
    public let url: String
    public let isInstalled: Bool

    public init(extensionId: String, url: String, isInstalled: Bool) {
        self.extensionId = extensionId
        self.url = url
        self.isInstalled = isInstalled
    }
}

// MARK: - AltoExtensionMessageHandler

/// Message handler for Alto extension actions from JavaScript
public class AltoExtensionMessageHandler: NSObject, WKScriptMessageHandler {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "MessageHandler")

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let messageBody = message.body as? [String: Any],
              let action = messageBody["action"] as? String else {
            logger.warning("⚠️ Invalid message format received")
            return
        }

        logger.info("📨 Received message: \(action)")

        switch action {
        case "requestInstall":
            if let extensionId = messageBody["extensionId"] as? String,
               let urlString = messageBody["url"] as? String,
               let url = URL(string: urlString) {
                ChromeWebStoreIntegration.shared.handleInstallRequest(extensionId: extensionId, from: url)
            }

        case "install":
            if let extensionId = messageBody["extensionId"] as? String,
               let urlString = messageBody["url"] as? String,
               let url = URL(string: urlString) {
                ChromeWebStoreIntegration.shared.installExtension(extensionId: extensionId, from: url)
            }

        case "uninstall":
            if let extensionId = messageBody["extensionId"] as? String {
                ChromeWebStoreIntegration.shared.uninstallExtension(extensionId: extensionId)
            }

        case "settings":
            if let extensionId = messageBody["extensionId"] as? String {
                ChromeWebStoreIntegration.shared.openExtensionSettings(extensionId: extensionId)
            }

        default:
            logger.warning("⚠️ Unknown action: \(action)")
        }
    }
}
