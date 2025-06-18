//



import AppKit
import WebKit
import SwiftUI


// for a tab to be rendered in the browser it must conform to the tab protocol
// The Tab can be a note, a swiftView like a canvas or a webpage
public protocol TabProtocol: NSObject, Identifiable {
    var id: UUID { get }
    var location: TabLocationProtocol? { get set }
    var content: [Displayable] { get set }
    var state: any StateProtocol { get set }
    var mannager: TabManagerProtocol? { get }
    
    func setContent(content addedContent: any Displayable)
    func closeTab()
}


public class Tab: NSObject, Identifiable, TabProtocol {
    public let id = UUID()
    
    public var location: (any TabLocationProtocol)?
    
    public var content: [any Displayable] = []
    
    public var state: any StateProtocol
    
    public var mannager: (any TabManagerProtocol)? {
        state.tabManager
    }
    
    init(state: any StateProtocol) {
        self.state = state
        
    }
    
    public func setContent(content addedContent: any Displayable) {
        self.content.append(addedContent)
    }
    
    public func createNewTab(_ url: String, _ configuration: WKWebViewConfiguration, frame: CGRect = .zero) {
        
    }
    
    public func closeTab() {
        
    }
}

/*
public class Folder: NSObject, Identifiable, TabProtocol {
    public let id = UUID()
    
    public var location: (any TabLocationProtocol)?
    
    public var content: [any Displayable]?
    
    public var state: any StateProtocol
    
    public var mannager: (any TabManagerProtocol)? {
        state.tabManager
    }
    
    init(state: StateProtocol, ) {
        self.state = state
        
    }
    
    public func closeTab() {
        <#code#>
    }
}



public class splitView: NSObject, Identifiable, TabProtocol {
    public let id = UUID()
    
    public var location: (any TabLocationProtocol)?
    
    public var content: [any Displayable]?
    
    public var state: any StateProtocol
    
    public var mannager: (any TabManagerProtocol)? {
        state.tabManager
    }
    
    init(state: StateProtocol, ) {
        self.state = state
        
    }
    
    public func closeTab() {
        <#code#>
    }
}
 */

/// This can be the content inside a tab
public protocol Displayable {
    var id: UUID { get }
    var title: String { get set }
    var favicon: NSImage? { get set }
    
    var canGoBack: Bool { get set }
    var canGoForward: Bool { get set }
    var isLoading: Bool { get set }
    
    func createNewTab(_ url: String, _ configuration: WKWebViewConfiguration, frame: CGRect)
    
    func removeWebView()
    
    func returnView() -> any View
}


@Observable
public class WebPage: NSObject, Identifiable, Displayable {
    private var state: any StateProtocol
    
    public let id = UUID()
    
    public var title: String = "Untitled"
    
    public var webView: webViewProtocol
    
    public var favicon: NSImage?
    
    public var view: NSView {
        self.webView
    }
    
    public var canGoBack: Bool = false
    
    public var canGoForward: Bool = false
    
    public var isLoading: Bool = false
    
    public var uiDelegate: WKUIDelegate?
    public var uiDownloadDelegate: WKDownloadDelegate?
    public var navigationDelegate: WKNavigationDelegate?
    
    init(webView: AltoWebView, state: any StateProtocol) {
        self.webView = webView
        self.state = state
        
        super.init()
        
        state.setup(webView: self.webView)
        webView.uiDelegate = self
        webView.navigationDelegate = self
    }
    
    public func createNewTab(_ url: String, _ configuration: WKWebViewConfiguration, frame: CGRect) {
        print("Placeholder")
        #warning("add new tab logic")
    }
    
    // This will deinit the webview and remove it from its parent
    public func removeWebView() {
        
    }
    
    public func returnView() -> any View {
        return AnyView(NSWebView(webView: self.webView))
    }
}

extension WebPage: WKNavigationDelegate, WKUIDelegate {
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.title = webView.title ?? "Untitled"
        
        self.canGoBack = webView.canGoBack
        self.canGoForward = webView.canGoForward
        
        self.favicon = Alto.shared.faviconHandler.getFavicon(webView)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            print("start")
            // Alto.shared.contextManager.pullContextFromPage(for: webView)
        }
    }
    
    public func webViewDidClose(_ webView: WKWebView) {
        #warning("add close functionality")
    }
    
    // This checks for new Window Requests from tabs
    public func webView(_ webView: WKWebView,
                        createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction,
                        windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        // If targetFrame is nil, this means the navigation action is targeting a new frame
        // that doesn't exist (otherwise the frame wouldnt be nil) in the current web view.
        // This happens when the web content tries to open a new window or tab.
        if navigationAction.targetFrame == nil {
            let newWebView = AltoWebView(frame: .zero, configuration: configuration) // We need to make this swapable
            
            // The navigation type is .other when it is like a login otherwise its just a normal open request
            if navigationAction.navigationType == .other {
                
                
            } else if let url = navigationAction.request.url?.absoluteString {
                
            }
            Alto.shared.cookieManager.setupCookies(for: newWebView)
        }
        return nil
    }
}
