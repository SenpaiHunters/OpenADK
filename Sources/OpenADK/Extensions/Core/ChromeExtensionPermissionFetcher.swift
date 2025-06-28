//
//  ChromeExtensionPermissionFetcher.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog
import WebKit

// MARK: - ChromeExtensionPermissionFetcher

/// Fetches extension permissions from Chrome Web Store by scraping the extension page
public class ChromeExtensionPermissionFetcher: NSObject {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "PermissionFetcher")
    private var webView: WKWebView?
    private var completion: (([String]) -> ())?

    /// Fetch permissions for a Chrome Web Store extension
    /// - Parameters:
    ///   - extensionId: Chrome Web Store extension ID
    ///   - completion: Completion handler with extracted permissions
    public func fetchPermissions(extensionId: String, completion: @escaping ([String]) -> ()) {
        logger.info("🔍 Fetching permissions for extension: \(extensionId)")

        self.completion = completion

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "permissionsHandler")

        // Configure WebView to act like Chrome
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptEnabled = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self

        // Set Chrome-like user agent
        webView?
            .customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

        // Use the new Chrome Web Store URL format
        let urlString = "https://chromewebstore.google.com/detail/\(extensionId)"
        logger.debug("📥 Loading URL: \(urlString)")

        if let url = URL(string: urlString) {
            webView?.load(URLRequest(url: url))
        } else {
            logger.error("❌ Invalid URL for extension ID: \(extensionId)")
            completion([])
        }
    }
}

// MARK: WKNavigationDelegate

extension ChromeExtensionPermissionFetcher: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.debug("📄 Page loaded, extracting permissions...")

        // Updated JavaScript for the new Chrome Web Store layout
        let script = """
        function extractPermissions() {
            console.log('🔍 Starting permission extraction...');
            const permissions = [];

            // New Chrome Web Store selectors (as of 2024)
            const selectors = [
                '[data-test-id="permissions-section"]',
                '[aria-label*="permission"]',
                '.permission-item',
                '[data-automation-id="permission"]',
                // Look for sections containing "This extension can"
                '*:contains("This extension can")',
                // Look for permission lists
                'ul li:contains("Read")',
                'ul li:contains("Access")',
                'ul li:contains("Modify")',
            ];

            // Try to find permissions section
            let permissionSection = null;

            // Look for text content that indicates permissions
            const walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                null,
                false
            );

            let node;
            const permissionKeywords = [
                'This extension can:',
                'Permissions:',
                'This extension has access to:',
                'Required permissions:'
            ];

            while (node = walker.nextNode()) {
                const text = node.textContent.trim();
                for (const keyword of permissionKeywords) {
                    if (text.includes(keyword)) {
                        permissionSection = node.parentElement;
                        console.log('✅ Found permission section:', keyword);
                        break;
                    }
                }
                if (permissionSection) break;
            }

            if (permissionSection) {
                // Look for list items or divs after the permission header
                const nextElements = [];
                let current = permissionSection.nextElementSibling;
                let count = 0;

                while (current && count < 10) {
                    if (current.tagName === 'UL' || current.tagName === 'OL') {
                        const items = current.querySelectorAll('li');
                        items.forEach(item => {
                            const text = item.textContent.trim();
                            if (text && text.length > 5) {
                                permissions.push(text);
                                console.log('📋 Found permission:', text);
                            }
                        });
                        break;
                    } else if (current.tagName === 'DIV') {
                        const text = current.textContent.trim();
                        if (text && text.length > 5 && !text.includes('Learn more')) {
                            permissions.push(text);
                            console.log('📋 Found permission:', text);
                        }
                    }
                    current = current.nextElementSibling;
                    count++;
                }
            }

            // Fallback: Look for common permission patterns in the entire page
            if (permissions.length === 0) {
                console.log('🔄 Using fallback permission detection...');
                const allText = document.body.textContent;
                const permissionPatterns = [
                    /Read and change all your data on the websites you visit/g,
                    /Access your tabs and browsing activity/g,
                    /Read your browsing history/g,
                    /Access your data for all websites/g,
                    /Modify data you copy and paste/g,
                    /Read and modify your bookmarks/g,
                    /Access browser tabs/g,
                    /Storage/g
                ];

                permissionPatterns.forEach(pattern => {
                    const matches = allText.match(pattern);
                    if (matches) {
                        matches.forEach(match => {
                            if (!permissions.includes(match)) {
                                permissions.push(match);
                                console.log('📋 Found permission (fallback):', match);
                            }
                        });
                    }
                });
            }

            console.log('✅ Extracted', permissions.length, 'permissions:', permissions);
            return permissions.filter(p => p.length > 0);
        }

        // Execute and return results
        const result = extractPermissions();
        window.webkit.messageHandlers.permissionsHandler.postMessage(result);
        """

        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.logger.error("❌ JavaScript error: \(error)")
                self?.completion?([])
                self?.cleanup()
            }
        }
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        logger.error("❌ Navigation failed: \(error)")
        completion?([])
        cleanup()
    }
}

// MARK: WKScriptMessageHandler

extension ChromeExtensionPermissionFetcher: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if message.name == "permissionsHandler" {
            if let permissions = message.body as? [String] {
                logger.info("✅ Extracted \(permissions.count) permissions: \(permissions)")
                DispatchQueue.main.async {
                    self.completion?(permissions)
                    self.cleanup()
                }
            } else {
                logger.warning("⚠️ No permissions found")
                completion?([])
                cleanup()
            }
        }
    }

    /// Clean up resources
    private func cleanup() {
        logger.debug("🧹 Cleaning up permission fetcher resources")
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "permissionsHandler")
        webView = nil
        completion = nil
    }
}
