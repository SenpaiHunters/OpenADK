//
import Observation
import WebKit
import Combine

/// AltoState handles the state for each window specificaly
///
/// Allows each window to display a diferent view of the tabs
@Observable
public class AltoState: StateProtocol {
    public var id: UUID = UUID()
    public var tabManager: TabManagerProtocol = TabsManager()
    public var window: AltoWindow?
    public var currentSpace: SpaceProtocol?
    public var currentContent: [(any Displayable)]? {
        self.currentSpace?.currentTab?.content
    }
    
    public init() {
        print("take that fucker")
        self.tabManager.state = self // Feeds in the state for the tab manager
        self.currentSpace = Alto.shared.spaces[0]
        print("HERE", Alto.shared.spaces[0])
    }
    
    public func setup(webView: WKWebView) {
        Alto.shared.cookieManager.setupCookies(for: webView)
    }
}


public protocol StateProtocol: ObservableObject {
    var id: UUID { get}
    // var spaceIndex: Int { get set }
    var tabManager: TabManagerProtocol { get }
    var window: AltoWindow? { get set }
    var currentSpace: SpaceProtocol? { get set }
    var currentContent: [Displayable]? { get }

    func setup(webView: WKWebView)
}
