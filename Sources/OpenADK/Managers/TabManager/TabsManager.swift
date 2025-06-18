//
import AppKit
import Observation
import WebKit

/// Manges Tabs for each Window
///
///  Tabs will be stored in Alto in future in order to support tabs being shared between windows (like Arc)
@Observable
public class TabsManager: TabManagerProtocol {
    public var state: (any StateProtocol)?

    public var globalLocations: [TabLocationProtocol] = [
        TabLocation(name: "Favorites"),
    ]

    public init(state: (any StateProtocol)? = nil) {
        self.state = state
    }

    public func setActiveTab(_ tab: any TabProtocol) {
        state?.currentSpace?.currentTab = tab
    }

    public func closeActiveTab() {
        if let currentTab = state?.currentSpace?.currentTab {
            currentTab.closeTab()
        }
    }

    public func addTab(_ tab: any TabProtocol) {
        Alto.shared.tabs[tab.id] = tab
    }

    public func removeTab(_ id: UUID) {
        let tab = Alto.shared.getTab(id: id)
        tab?.location?.removeTab(id: id)
        Alto.shared.tabs.removeValue(forKey: id)
    }

    public func getLocation(_ location: String) -> TabLocationProtocol? {
        var allLocations: [any TabLocationProtocol] = []
        allLocations = allLocations + globalLocations

        for space in Alto.shared.spaces {
            allLocations += space.localLocations
        }

        return allLocations.first(where: { $0.name == location })
    }

    public func createNewTab(url: String = "https://www.google.com/", frame: CGRect = .zero, configuration: WKWebViewConfiguration = AltoWebViewConfigurationBase(), location: String = "unpinned") {
        guard let state else {
            return
        }

        guard let tabLocation = getLocation(location) else {
            return
        }

        let newWebView = AltoWebView(frame: frame, configuration: configuration)
        Alto.shared.cookieManager.setupCookies(for: newWebView)

        if let url = URL(string: url) {
            let request = URLRequest(url: url)
            newWebView.load(request)
        }
        let newTab = Tab(state: state)
        newTab.location = tabLocation

        let newWebPage = WebPage(webView: newWebView, state: state, parent: newTab)
        newWebPage.parent = newTab

        newTab.setContent(content: newWebPage)

        let tabRep = TabRepresentation(id: newTab.id, index: tabLocation.tabs.count)

        addTab(newTab)

        tabLocation.appendTabRep(tabRep)
        setActiveTab(newTab)
    }
}

public class SearchEngine {
    var engineName: String
    var searchURL: String

    public init(_ name: String, url: String) {
        engineName = name
        searchURL = url
    }
}

public protocol TabManagerProtocol {
    var state: (any StateProtocol)? { get set }
    var globalLocations: [TabLocationProtocol] { get set }

    func createNewTab(url: String, frame: CGRect, configuration: WKWebViewConfiguration, location: String)
    func setActiveTab(_ tab: any TabProtocol)
    func addTab(_ tab: any TabProtocol)
    func removeTab(_ id: UUID)
    func getLocation(_ location: String) -> TabLocationProtocol?
    func closeActiveTab()
}
