//
//  TabsManager.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit
import Observation
import WebKit

// MARK: - TabsManager

/// Manges Tabs for each Window
///
///  Tabs will be stored in Alto in future in order to support tabs being shared between windows (like Arc)
@Observable
public class TabsManager {
    public var state: GenaricState?

    public var globalLocations: [TabLocation] = [
        TabLocation(title: "Favorites")
    ]

    public init(state: GenaricState? = nil) {
        self.state = state
    }

    public func setActiveTab(_ tab: GenaricTab) {
        state?.currentSpace?.currentTab = tab
    }

    public func closeActiveTab() {
        if let currentTab = state?.currentSpace?.currentTab {
            currentTab.closeTab()
        }
    }

    public func addTab(_ tab: GenaricTab) {
        Alto.shared.tabs[tab.id] = tab
    }

    public func removeTab(_ id: UUID) {
        let tab = Alto.shared.getTab(id: id)
        tab?.location?.removeTab(id: id)
        Alto.shared.tabs.removeValue(forKey: id)
    }

    public func getLocation(_ location: String) -> TabLocation? {
        guard let localLocations = state?.currentSpace?.localLocations else {
            return nil
        }
        var allLocations: [TabLocation] = []
        allLocations = localLocations + globalLocations

        return allLocations.first(where: { $0.title == location })
    }

    public func createNewTab(
        url: String = "https://www.google.com/",
        frame: CGRect = .zero,
        location: String = "unpinned"
    ) {
        guard let state else {
            return
        }

        guard let tabLocation = getLocation(location) else {
            return
        }

        let profileId = state.currentSpace?.profile?.id
        let dataStore = WKWebsiteDataStore(forIdentifier: profileId!)
        let configuration = AltoWebViewConfigurationBase(dataStore: dataStore)

        let newWebView = AltoWebView(frame: frame, configuration: configuration)
        Alto.shared.cookieManager.setupCookies(for: newWebView)

        if let url = URL(string: url) {
            let request = URLRequest(url: url)
            newWebView.load(request)
        }
        let newTab = GenaricTab(state: state)
        newTab.location = tabLocation

        let newWebPage = WebPage(webView: newWebView, state: state, parent: newTab)
        newWebPage.parent = newTab

        newTab.setContent(content: newWebPage)

        let tabRep = TabRepresentation(id: newTab.id, index: tabLocation.tabs.count)
        newTab.tabRepresentation = tabRep

        addTab(newTab)

        tabLocation.appendTabRep(tabRep)
        setActiveTab(newTab)
    }
}
