//
import Combine
import Observation
import WebKit

// MARK: - GenaricState

/// GenaricState handles the state for each window specificaly
///
/// Allows each window to display a diferent view of the tabs
@Observable
open class GenaricState: StateProtocol {
    public var id: UUID = .init()
    public var tabManager: TabManagerProtocol = TabsManager()
    public var window: AltoWindow?
    public var currentSpace: SpaceProtocol?
    public var currentContent: [any Displayable]? {
        currentSpace?.currentTab?.content
    }

    public init() {
        print("take that fucker")
        tabManager.state = self // Feeds in the state for the tab manager
        currentSpace = Alto.shared.spaces[0]
        print("HERE", Alto.shared.spaces[0])
    }

    public func setup(webView: WKWebView) {
        Alto.shared.cookieManager.setupCookies(for: webView)
    }
}

// MARK: - StateProtocol

public protocol StateProtocol: Observable {
    var id: UUID { get }
    // var spaceIndex: Int { get set }
    var tabManager: TabManagerProtocol { get }
    var window: AltoWindow? { get set }
    var currentSpace: SpaceProtocol? { get set }
    var currentContent: [Displayable]? { get }

    func setup(webView: WKWebView)
}
