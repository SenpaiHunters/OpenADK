//

import AppKit
import SwiftUI
import WebKit

// MARK: - TabProtocol

// for a tab to be rendered in the browser it must conform to the tab protocol
// The Tab can be a note, a swiftView like a canvas or a webpage
public protocol TabProtocol: NSObject, Identifiable {
    var id: UUID { get }
    var location: TabLocationProtocol? { get set }
    var content: [Displayable] { get set }
    var state: any StateProtocol { get set }
    var manager: TabManagerProtocol? { get }
    var isCurrentTab: Bool { get }
    var tabRepresentation: TabRepresentation? { get set }

    func setContent(content addedContent: any Displayable)
    func closeTab()
}

// MARK: - GenaricTab

@Observable
open class GenaricTab: NSObject, Identifiable, TabProtocol {
    public let id = UUID()

    public var tabRepresentation: TabRepresentation?

    public var location: (any TabLocationProtocol)?

    public var content: [any Displayable] = []

    public var state: any StateProtocol

    public var manager: (any TabManagerProtocol)? {
        state.tabManager
    }

    public var isCurrentTab: Bool {
        state.currentSpace?.currentTab?.id == id
    }

    init(state: any StateProtocol) {
        self.state = state
    }

    public func setContent(content addedContent: any Displayable) {
        if !content.isEmpty {
            content[0] = addedContent
        } else {
            content.append(addedContent)
        }
    }

    public func createNewTab(_: String, _: WKWebViewConfiguration, frame _: CGRect = .zero) {}

    public func closeTab() {
        location?.removeTab(id: id)
        state.tabManager.removeTab(id)

        for c in content {
            c.removeWebView()
        }

        if isCurrentTab {
            state.currentSpace?.currentTab = nil
        }
    }
}

// MARK: - Displayable

/// This can be the content inside a tab
public protocol Displayable {
    var parent: (any TabProtocol)? { get set }

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

// MARK: - WebPage

@Observable
public class WebPage: NSObject, Identifiable, Displayable {
    public var parent: (any TabProtocol)?

    private var state: any StateProtocol

    public let id = UUID()

    public var title = "Untitled"

    public var webView: webViewProtocol

    public var favicon: NSImage?

    public var view: NSView {
        webView
    }

    public var canGoBack = false

    public var canGoForward = false

    public var isLoading = false

    public var uiDelegate: WKUIDelegate?
    public var uiDownloadDelegate: WKDownloadDelegate?
    public var navigationDelegate: WKNavigationDelegate?

    init(webView: AltoWebView, state: any StateProtocol, parent _: (any TabProtocol)? = nil) {
        self.webView = webView
        self.state = state

        super.init()

        state.setup(webView: self.webView)
        webView.uiDelegate = self
        webView.navigationDelegate = self
    }

    public func createNewTab(_: String, _: WKWebViewConfiguration, frame _: CGRect) {}

    public func goBack() {
        webView.goBack()
    }

    public func goForward() {
        webView.goForward()
    }

    // This will deinit the webview and remove it from its parent
    public func removeWebView() {
        webView.stopLoading()
        webView.delegate = nil
        webView.navigationDelegate = nil
    }

    public func returnView() -> any View {
        if let webview = webView as? AltoWebView {
            let contentview = NSViewContainerView(contentView: webview)
            return WebViewContainer(contentView: contentview, topContentInset: CGFloat(0.0))
        }
        return Text("no")
    }
}

// MARK: WKNavigationDelegate, WKUIDelegate

extension WebPage: WKNavigationDelegate, WKUIDelegate {
    public func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        title = webView.title ?? "test"

        // Instead of guessing the favicon URL, let's find the actual favicon from the HTML
        if let url = webView.url {
            Alto.shared.faviconManager.fetchFaviconFromHTML(webView: webView, baseURL: url) { [weak self] image in
                DispatchQueue.main.async {
                    self?.favicon = image
                }
            }
        }

        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward

        print(title)
    }

    public func webViewDidClose(_: WKWebView) {
        parent?.closeTab()
    }

    // This checks for new Window Requests from tabs
    public func webView(
        _: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        // If targetFrame is nil, this means the navigation action is targeting a new frame
        // that doesn't exist (otherwise the frame wouldnt be nil) in the current web view.
        // This happens when the web content tries to open a new window or tab.
        if navigationAction.targetFrame == nil {
            let newWebView = AltoWebView(frame: .zero, configuration: configuration) // We need to make this swapable

            // The navigation type is .other when it is like a login otherwise its just a normal open request
            if navigationAction.navigationType == .other {
                print("Opened a login tab")
            } else if let url = navigationAction.request.url?.absoluteString {
                if let url = URL(string: url) {
                    let request = URLRequest(url: url)
                    newWebView.load(request)
                }
            }

            let newWebPage = WebPage(webView: newWebView, state: state)
            let newTab = GenaricTab(state: state)
            newTab.location = parent?.location
            newTab.setContent(content: newWebPage)
            newWebPage.parent = newTab

            let newTabIndex = parent?.tabRepresentation?.index ?? 0 // TODO: Make some better solution
            let tabRep = TabRepresentation(id: newTab.id, index: newTabIndex)
            newTab.tabRepresentation = tabRep

            state.tabManager.addTab(newTab)

            if let loc = parent?.location {
                loc.appendTabRep(tabRep)
            } else {
                print("failed to get location")
            }

            Alto.shared.cookieManager.setupCookies(for: newWebView)

            state.tabManager.setActiveTab(newTab)

            return newWebView
        }
        return nil
    }

    /*
     public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
         let urlCredential = URLCredential(user: "email", password: "my pasword", persistence: .forSession)
         completionHandler(.useCredential, urlCredential)
         print(urlCredential)
     }
      */
}

/*
 class NavigationDelegate: NSObject, WKNavigationDelegate {

     func webView(WKWebView, didStartProvisionalNavigation: WKNavigation!) {

     }

     func webView(WKWebView, didCommit: WKNavigation!) {

     }

     func webView(WKWebView, didFinish: WKNavigation!) {

     }

     func webView(WKWebView, didReceive: URLAuthenticationChallenge, completionHandler: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {

     }

 }
 */
