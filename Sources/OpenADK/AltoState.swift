//
import Observation
import WebKit
import Combine

/// AltoState handles the state for each window specificaly
///
/// Allows each window to display a diferent view of the tabs
@Observable
public class AltoState: StateProtocol {
    public var tabManager: TabManagerProtocol = TabsManager()
    
    public var currentSpace: SpaceProtocol?
    
    public init() {
        self.tabManager.state = self // Feeds in the state for the tab manager
    }
    
    public func setup(webView: WKWebView) {
        Alto.shared.cookieManager.setupCookies(for: webView)
    }
}


public protocol StateProtocol: ObservableObject {
    var tabManager: TabManagerProtocol { get }
    var currentSpace: SpaceProtocol? { get set }
    
    func setup(webView: WKWebView)
}
