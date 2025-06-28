//
//  ADKWebPage.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Displayable

/// A Protocol for what can be displayed as tab content
public protocol Displayable {
    var parent: ADKTab? { get set }

    var id: UUID { get }
    var title: String { get set }
    var favicon: NSImage? { get set }

    var canGoBack: Bool { get set }
    var canGoForward: Bool { get set }
    var isLoading: Bool { get set }

    func createNewTab(_ url: String, _ configuration: WKWebViewConfiguration, frame: CGRect)
    func goBack()
    func goForward()

    func removeWebView()

    func returnView() -> any View
}

// MARK: - ADKWebPage

/// A simple webpage that conforms to the Tab Displayable protocol

///
/// WebPage represents a single web page within a browser tab, handling navigation,
/// downloads, and web view lifecycle management. It acts as the bridge between
/// the browser's tab system and the underlying WKWebView.
@Observable
public class ADKWebPage: NSObject, Identifiable, Displayable {
    /// Reference to the parent tab containing this web page
    public var parent: ADKTab?

    /// The application state manager
    private var state: ADKState

    /// Unique identifier for this web page instance
    public let id = UUID()

    /// The title of the web page, automatically updates the window title when changed
    public var title = "Untitled" {
        didSet { state.window?.title = title }
    }

    /// The underlying web view instance
    public var webView: webViewProtocol

    /// The favicon image for this web page
    public var favicon: NSImage?

    /// The NSView representation of the web view
    public var view: NSView { webView }

    /// Whether the web view can navigate back
    public var canGoBack = false

    /// Whether the web view can navigate forward
    public var canGoForward = false

    /// Whether the web page is currently loading
    public var isLoading = false

    /// UI delegate for handling web view UI events
    public var uiDelegate: WKUIDelegate?

    /// Download delegate for handling download events
    public var uiDownloadDelegate: WKDownloadDelegate?

    /// Navigation delegate for handling navigation events
    public var navigationDelegate: WKNavigationDelegate?

    /// Initializes a new WebPage instance
    /// - Parameters:
    ///   - webView: The AltoWebView instance to wrap
    ///   - state: The application state manager
    ///   - parent: Optional parent tab reference
    public init(webView: ADKWebView, state: ADKState, parent: ADKTab? = nil) {
        self.webView = webView
        self.state = state
        super.init()

        state.setup(webView: webView)
        webView.ownerTab = self
        webView.uiDelegate = self
        webView.navigationDelegate = self

        setupContextMenuHandling()
    }

    /// Creates a new tab with the specified URL and configuration
    /// - Parameters:
    ///   - url: The URL to load in the new tab
    ///   - configuration: The web view configuration to use
    ///   - frame: The frame for the new web view
    public func createNewTab(_: String, _: WKWebViewConfiguration, frame _: CGRect) {}

    /// Handles mouse down events to activate this tab
    public func handleMouseDown() {
        guard parent?.activeContent?.id != id else { return }
        parent?.activeContent = self
    }

    /// Navigates the web view back in history
    public func goBack() { webView.goBack() }

    /// Navigates the web view forward in history
    public func goForward() { webView.goForward() }

    /// Removes and cleans up the web view

    public func removeWebView() {
        webView.stopLoading()
        webView.delegate = nil
        webView.navigationDelegate = nil
    }

    /// Returns the SwiftUI view representation of this web page
    /// - Returns: A SwiftUI view containing the web view or a Spacer if unavailable
    public func returnView() -> any View {
        guard let webview = webView as? ADKWebView else { return Spacer() }
        let contentview = NSViewContainerView(contentView: webview)
        return WebViewContainer(contentView: contentview, topContentInset: 0.0)
    }

    /// Sets up context menu handling for image downloads
    private func setupContextMenuHandling() {
        guard let altoWebView = webView as? ADKWebView else { return }

        // Add JavaScript to handle context menu events
        let contextMenuScript = """
        document.addEventListener('contextmenu', function(event) {
            var element = event.target;
            if (element.tagName === 'IMG') {
                var imageData = {
                    src: element.src,
                    alt: element.alt || '',
                    width: element.naturalWidth,
                    height: element.naturalHeight
                };
                window.webkit.messageHandlers.contextMenu.postMessage({
                    type: 'image',
                    data: imageData,
                    x: event.clientX,
                    y: event.clientY
                });
            }
        });
        """

        let userScript = WKUserScript(source: contextMenuScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        altoWebView.configuration.userContentController.addUserScript(userScript)
        altoWebView.configuration.userContentController.add(self, name: "contextMenu")
    }
}

// MARK: WKScriptMessageHandler

extension ADKWebPage: WKScriptMessageHandler {
    /// Handles JavaScript messages from the web view
    /// - Parameters:
    ///   - userContentController: The user content controller
    ///   - message: The script message received
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "contextMenu",
              let messageBody = message.body as? [String: Any],
              let type = messageBody["type"] as? String,
              type == "image",
              let data = messageBody["data"] as? [String: Any],
              let srcString = data["src"] as? String else { return }

        handleImageContextMenu(imageUrl: srcString, imageData: data)
    }

    /// Handles context menu actions for images
    /// - Parameters:
    ///   - imageUrl: The URL of the image
    ///   - imageData: Additional image metadata
    private func handleImageContextMenu(imageUrl: String, imageData: [String: Any]) {
        guard let url = URL(string: imageUrl) else { return }

        // Create filename from image data
        let alt = imageData["alt"] as? String ?? ""
        let filename = generateImageFilename(from: url, alt: alt)

        // Handle different types of image URLs
        if url.scheme == "data" {
            handleDataUrlImage(dataUrl: imageUrl, filename: filename)
        } else if url.scheme == "blob" {
            handleBlobUrlImage(blobUrl: imageUrl, filename: filename)
        } else {
            // Regular URL - use existing download mechanism
            handleDownload(url: url, filename: filename)
        }
    }

    /// Generates an appropriate filename for an image
    /// - Parameters:
    ///   - url: The image URL
    ///   - alt: The alt text of the image
    /// - Returns: A suitable filename for the image
    private func generateImageFilename(from url: URL, alt: String) -> String {
        // Try to get filename from URL
        let urlFilename = url.lastPathComponent
        if !urlFilename.isEmpty, urlFilename.contains(".") {
            return urlFilename
        }

        // Use alt text if available
        if !alt.isEmpty {
            let cleanAlt = alt.replacingOccurrences(of: "[^a-zA-Z0-9\\s]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)

            if !cleanAlt.isEmpty {
                return "\(cleanAlt).jpg" // Default to jpg for images without extension
            }
        }

        // Fallback to timestamp-based filename
        let timestamp = Int(Date().timeIntervalSince1970)
        return "image_\(timestamp).jpg"
    }

    /// Handles downloading images from data URLs
    /// - Parameters:
    ///   - dataUrl: The data URL string
    ///   - filename: The filename to use for the download
    private func handleDataUrlImage(dataUrl: String, filename: String) {
        guard dataUrl.hasPrefix("data:"),
              let commaIndex = dataUrl.firstIndex(of: ",") else { return }

        let dataString = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard let imageData = Data(base64Encoded: dataString) else { return }

        // Save the image data directly
        saveImageData(imageData, filename: filename)
    }

    /// Handles downloading images from blob URLs
    /// - Parameters:
    ///   - blobUrl: The blob URL string
    ///   - filename: The filename to use for the download
    private func handleBlobUrlImage(blobUrl: String, filename: String) {
        guard let altoWebView = webView as? ADKWebView else { return }

        // Use JavaScript to convert blob to base64
        let script = """
        (function() {
            fetch('\(blobUrl)')
                .then(response => response.blob())
                .then(blob => {
                    const reader = new FileReader();
                    reader.onload = function() {
                        window.webkit.messageHandlers.blobDownload.postMessage({
                            data: reader.result,
                            filename: '\(filename)'
                        });
                    };
                    reader.readAsDataURL(blob);
                })
                .catch(error => console.error('Error downloading blob:', error));
        })();
        """

        // Add handler for blob download
        altoWebView.configuration.userContentController.add(self, name: "blobDownload")
        altoWebView.evaluateJavaScript(script) { _, error in
            if let error {
                print("Error executing blob download script: \(error)")
            }
        }
    }

    /// Saves image data to the downloads folder
    /// - Parameters:
    ///   - imageData: The image data to save
    ///   - filename: The filename to use
    private func saveImageData(_ imageData: Data, filename: String) {
        // Get downloads directory
        guard let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            print("Could not access downloads directory")
            return
        }

        let fileUrl = downloadsUrl.appendingPathComponent(filename)

        do {
            try imageData.write(to: fileUrl)
            print("✅ Image saved to: \(fileUrl.path)")

            // Post notification for successful download
            NotificationCenter.default.post(
                name: NSNotification.Name("AltoDownloadCompleted"),
                object: nil,
                userInfo: ["url": fileUrl.absoluteString, "filename": filename]
            )
        } catch {
            print("❌ Error saving image: \(error)")
        }
    }
}

// MARK: WKNavigationDelegate, WKUIDelegate

extension ADKWebPage: WKNavigationDelegate, WKUIDelegate {
    /// Called when the web view finishes loading a page
    /// - Parameters:
    ///   - webView: The web view that finished loading
    ///   - navigation: The navigation object
    public func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        title = webView.title ?? "test"

        if let url = webView.url {
            FaviconManager.shared.fetchFaviconFromHTML(webView: webView, baseURL: url) { [weak self] image in
                DispatchQueue.main.async { self?.favicon = image }
            }

            // Notify extension runtime about navigation completion
            if let altoWebView = webView as? ADKWebView {
                altoWebView.notifyExtensionNavigationCompleted(to: url)
            }

            // Check if this is a Chrome Web Store page and inject Alto controls
            Task { @MainActor in
                await self.injectWebStoreControlsIfNeeded(webView: webView, url: url)
            }
        }

        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    /// Called when a provisional navigation fails
    /// - Parameters:
    ///   - webView: The web view that failed to load
    ///   - navigation: The failed navigation
    ///   - error: The error that occurred
    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let url = webView.url?.absoluteString ?? "unknown"
        print("❌ WebView failed provisional navigation: \(url), Error: \(error)")

        // Check if this is a WebKit content blocker error (code 104)
        let nsError = error as NSError
        if nsError.domain == "WebKitErrorDomain", nsError.code == 104 {
            print("🛡️ Content blocked by ad blocker: \(url)")

            // Get the blocked URL from multiple sources
            var blockedURL = webView.url
            if let errorURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
                blockedURL = errorURL
                print("🎯 Using blocked URL from error userInfo: \(errorURL)")
            } else if let errorURLString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String,
                      let parsedURL = URL(string: errorURLString) {
                blockedURL = parsedURL
                print("🎯 Using blocked URL from error string: \(parsedURL)")
            }

            // Post notification for the blocking manager to handle
            if let blockedURL {
                print("📢 Posting contentWasBlocked notification for: \(blockedURL)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .contentWasBlocked,
                        object: webView,
                        userInfo: [
                            "url": blockedURL,
                            "error": error,
                            "webPage": self
                        ]
                    )
                    print("📤 Notification posted successfully")
                }
            } else {
                print("⚠️ No blocked URL found to show popup for")
            }
        } else {
            // Handle other WebKit errors with the old retry logic
            print("🔧 Attempting to recover from WebKit error \(nsError.code)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let currentURL = webView.url {
                    print("🔄 Reloading page: \(currentURL)")
                    webView.reload()
                }
            }
        }
    }

    /// Called when a navigation fails after committing
    /// - Parameters:
    ///   - webView: The web view that failed to load
    ///   - navigation: The failed navigation
    ///   - error: The error that occurred
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let url = webView.url?.absoluteString ?? "unknown"
        print("❌ WebView navigation failed: \(url), Error: \(error)")

        // Update loading state
        isLoading = false

        // Could implement error page handling here
        title = "Error Loading Page"
    }

    /// Called when the web view is closed
    /// - Parameter webView: The web view that was closed
    public func webViewDidClose(_: WKWebView) {
        parent?.closeTab()
    }

    /// Decides whether to allow or cancel a navigation action
    /// - Parameters:
    ///   - webView: The web view requesting the navigation
    ///   - navigationAction: The navigation action to evaluate
    ///   - decisionHandler: The completion handler to call with the decision
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> ()
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Skip download check for blob and data URLs as they're handled differently
        if url.scheme == "blob" || url.scheme == "data" {
            decisionHandler(.allow)
            return
        }

        if isDownloadableFile(url: url) {
            handleDownload(url: url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    /// Decides whether to allow or cancel a navigation response
    /// - Parameters:
    ///   - webView: The web view that received the response
    ///   - navigationResponse: The navigation response to evaluate
    ///   - decisionHandler: The completion handler to call with the decision
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> ()
    ) {
        guard let response = navigationResponse.response as? HTTPURLResponse,
              let url = response.url else {
            decisionHandler(.allow)
            return
        }

        if shouldTriggerDownload(for: response) {
            let filename = extractFilename(from: response) ?? url.lastPathComponent
            handleDownload(url: url, filename: filename)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    /// Creates a new web view for handling new window requests
    /// - Parameters:
    ///   - webView: The web view requesting the new window
    ///   - configuration: The configuration for the new web view
    ///   - navigationAction: The navigation action that triggered the request
    ///   - windowFeatures: The window features for the new window
    /// - Returns: A new web view instance or nil if the request should be ignored

    public func webView(
        _: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        let newWebView = ADKWebView(frame: .zero, configuration: configuration)

        if navigationAction.navigationType != .other,
           let url = navigationAction.request.url {
            newWebView.load(URLRequest(url: url))
        }

        return createNewTab(with: newWebView)
    }

    // MARK: - Private Helper Methods

    /// Determines if a URL points to a downloadable file based on its extension
    /// Uses UniformTypeIdentifiers to dynamically categorize file types
    /// - Parameter url: The URL to check
    /// - Returns: True if the file should be downloaded, false otherwise
    private func isDownloadableFile(url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        guard !pathExtension.isEmpty else { return false }
        guard let utType = UTType(filenameExtension: pathExtension) else { return false }

        return utType.conforms(to: .archive) ||
            utType.conforms(to: .diskImage) ||
            utType.conforms(to: .executable) ||
            utType.conforms(to: .package) ||
            utType.conforms(to: .spreadsheet) ||
            utType.conforms(to: .presentation) ||
            (utType.conforms(to: .data) &&
                !utType.conforms(to: .text) &&
                !utType.conforms(to: .image) &&
                !utType.conforms(to: .audiovisualContent)
            ) ||
            utType == .pdf ||
            utType.identifier.hasPrefix("com.microsoft.") ||
            utType.identifier.hasPrefix("org.openxmlformats.") ||
            isInstallerType(utType)
    }

    /// Checks if the UTType represents an installer package
    /// - Parameter utType: The UTType to check
    /// - Returns: True if it's an installer type, false otherwise
    private func isInstallerType(_ utType: UTType) -> Bool {
        utType.identifier == "com.apple.installer-package-archive" ||
            utType.identifier == "com.microsoft.msi-installer" ||
            utType.identifier == "org.debian.deb-archive" ||
            utType.identifier == "com.redhat.rpm-archive" ||
            utType.identifier.contains("installer")
    }

    /// Initiates a download for the specified URL
    /// - Parameters:
    ///   - url: The URL to download
    ///   - filename: Optional filename override
    private func handleDownload(url: URL, filename: String? = nil) {
        let finalFilename = filename ?? url.lastPathComponent

        // Validate URL string to prevent sandbox extension errors
        let urlString = url.absoluteString
        guard !urlString.isEmpty, urlString != "about:blank" else {
            print("⚠️ Skipping download for invalid URL: \(urlString)")
            return
        }

        print("🚀 Detected download URL: \(urlString)")

        NotificationCenter.default.post(
            name: NSNotification.Name("AltoDownloadRequested"),
            object: nil,
            userInfo: ["url": urlString, "filename": finalFilename]
        )
    }

    /// Determines if an HTTP response should trigger a download
    /// - Parameter response: The HTTP response to evaluate
    /// - Returns: True if the response should trigger a download, false otherwise
    private func shouldTriggerDownload(for response: HTTPURLResponse) -> Bool {
        // Check Content-Disposition header first
        if let contentDisposition = response.allHeaderFields["Content-Disposition"] as? String,
           contentDisposition.lowercased().contains("attachment") {
            return true
        }

        // Check Content-Type dynamically
        if let contentType = response.allHeaderFields["Content-Type"] as? String {
            return isDownloadableMimeType(contentType)
        }

        // Fallback to file extension check
        guard let url = response.url else { return false }
        return isDownloadableFile(url: url)
    }

    /// Determines if a MIME type represents a downloadable file
    /// Uses UniformTypeIdentifiers for dynamic type checking
    /// - Parameter mimeType: The MIME type to evaluate
    /// - Returns: True if the MIME type represents a downloadable file, false otherwise
    private func isDownloadableMimeType(_ mimeType: String) -> Bool {
        let cleanMimeType = mimeType.components(separatedBy: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        guard let utType = UTType(mimeType: cleanMimeType) else {
            // Handle common cases that might not have UTType mappings
            return cleanMimeType.hasPrefix("application/") &&
                !cleanMimeType.hasPrefix("application/json") &&
                !cleanMimeType.hasPrefix("application/xml") &&
                !cleanMimeType.hasPrefix("application/javascript")
        }

        return utType.conforms(to: .archive) ||
            utType.conforms(to: .diskImage) ||
            utType.conforms(to: .executable) ||
            utType.conforms(to: .package) ||
            utType.conforms(to: .spreadsheet) ||
            utType.conforms(to: .presentation) ||
            utType == .pdf ||
            (utType.conforms(to: .data) &&
                !utType.conforms(to: .text) &&
                !utType.conforms(to: .image) &&
                !utType.conforms(to: .audiovisualContent) &&
                !utType.conforms(to: .json) &&
                !utType.conforms(to: .xml)
            ) ||
            utType.identifier.hasPrefix("com.microsoft.") ||
            utType.identifier.hasPrefix("org.openxmlformats.") ||
            isInstallerType(utType)
    }

    /// Extracts the filename from an HTTP response's Content-Disposition header
    /// - Parameter response: The HTTP response to parse
    /// - Returns: The extracted filename or nil if not found
    private func extractFilename(from response: HTTPURLResponse) -> String? {
        guard let contentDisposition = response.allHeaderFields["Content-Disposition"] as? String else { return nil }

        return contentDisposition
            .components(separatedBy: ";")
            .first { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("filename=") }?
            .replacingOccurrences(of: "filename=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// Creates a new tab with the provided web view
    /// - Parameter webView: The web view to use for the new tab
    /// - Returns: The created web view instance
    private func createNewTab(with webView: ADKWebView) -> WKWebView {
        let newWebPage = ADKWebPage(webView: webView, state: state)
        let newTab = ADKTab(state: state)
        newTab.location = parent?.location
        newTab.setContent(content: newWebPage)
        newWebPage.parent = newTab

        let newTabIndex = parent?.tabRepresentation?.index ?? 0
        let tabRep = TabRepresentation(id: newTab.id, index: newTabIndex)
        newTab.tabRepresentation = tabRep

        state.tabManager.addTab(newTab)
        parent?.location?.appendTabRep(tabRep)

        CookiesManager.shared.setupCookies(for: webView)
        state.tabManager.setActiveTab(newTab)

        return webView
    }

    // MARK: - Chrome Web Store Integration

    /// Inject Alto controls into Chrome Web Store pages if needed
    /// - Parameters:
    ///   - webView: The web view displaying the page
    ///   - url: The current URL
    @MainActor
    private func injectWebStoreControlsIfNeeded(webView: WKWebView, url: URL) async {
        // Web Store controls are now handled centrally by ExtensionRuntime
        // This prevents duplicate injections
        print("🔗 Web Store control injection delegated to ExtensionRuntime")
    }
}
