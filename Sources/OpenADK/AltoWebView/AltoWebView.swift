//
import AppKit
import WebKit

/// Custom verson of WKWebView to avoid needing an extra class for managment
@Observable
public class AltoWebView: WKWebView, webViewProtocol {
    public var currentConfiguration: WKWebViewConfiguration
    public var delegate: WKUIDelegate?
    public var navDelegate: WKNavigationDelegate?
    
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        currentConfiguration = configuration
        super.init(frame: frame, configuration: configuration)
        
        allowsMagnification = true
        customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    deinit {
        
    }
}

extension WKWebView {
    /// WKWebView's `configuration` is marked with @NSCopying.
    /// So everytime you try to access it, it creates a copy of it, which is most likely not what we want.
    var configurationWithoutMakingCopy: WKWebViewConfiguration {
        (self as? AltoWebView)?.currentConfiguration ?? configuration
    }
}


public protocol webViewProtocol: WKWebView {
    var currentConfiguration: WKWebViewConfiguration { get set }
    var delegate: WKUIDelegate? { get set }
    var navDelegate: WKNavigationDelegate? { get set }
    
}
