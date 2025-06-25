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
open class ADKTabManager {
    public var state: ADKState?
    public var currentTab: ADKTab?
    private var profile: Profile?

    private var defaultTabLocation: TabLocation {
        tabLocations[0]
    }

    public var tabLocations: [TabLocation] = []

    public init(state: ADKState? = nil, profile: Profile? = nil, tabLocations: [TabLocation]? = nil) {
        self.state = state
        self.profile = profile
        self.tabLocations = tabLocations ?? [
            TabLocation()
        ]
    }

    public func setupTabs(tabs: [ADKTab], location: TabLocation? = nil) {
        guard !tabs.isEmpty else {
            return
        }

        for tab in tabs {
            createNewTab(newTab: tab, location: location)
        }

        currentTab = tabs.last
    }

    public func setActiveTab(_ tab: ADKTab) {
        print("ran set active tab")
        currentTab = tab
    }

    public func closeActiveTab() {
        guard let currentTab else {
            return
        }
        currentTab.closeTab()
    }

    open func addTab(_ tab: ADKTab) {
        print("added tab")
        ADKData.shared.tabs[tab.id] = tab
    }

    public func removeTab(_ id: UUID) {
        let tab = ADKData.shared.getTab(id: id)
        tab?.location?.removeTab(id: id)
        ADKData.shared.tabs.removeValue(forKey: id)
    }

    open func getLocation(_ location: String) -> TabLocation? {
        tabLocations.first(where: { $0.title == location })
    }

    open func createNewTab(
        url: String = "https://www.google.com/",
        frame: CGRect = .zero,
        location: String
    ) {
        guard let state else {
            return
        }

        guard let tabLocation = getLocation(location) else {
            return
        }

        let profile = profile ?? ProfileManager.shared.defaultProfile
        let dataStore = WKWebsiteDataStore(forIdentifier: profile.id)
        let configuration = ADKWebViewConfigurationBase(dataStore: dataStore)

        let newWebView = ADKWebView(frame: frame, configuration: configuration)
        CookiesManager.shared.setupCookies(for: newWebView)

        if let url = URL(string: url) {
            let request = URLRequest(url: url)
            newWebView.load(request)
        }
        let newTab = ADKTab(state: state)
        newTab.location = tabLocation

        let newWebPage = ADKWebPage(webView: newWebView, state: state, parent: newTab)
        newWebPage.parent = newTab

        newTab.setContent(content: newWebPage)

        let tabRep = TabRepresentation(id: newTab.id, index: tabLocation.tabs.count)
        newTab.tabRepresentation = tabRep

        addTab(newTab)

        tabLocation.appendTabRep(tabRep)
        setActiveTab(newTab)
    }

    open func createNewTab(
        newTab: ADKTab,
        location: TabLocation? = nil
    ) {
        guard let state else {
            return
        }

        let tabLocation = location ?? defaultTabLocation

        let profile = profile ?? ProfileManager.shared.defaultProfile
        let dataStore = WKWebsiteDataStore(forIdentifier: profile.id)
        let configuration = ADKWebViewConfigurationBase(dataStore: dataStore)

        newTab.location = tabLocation

        var tabRep = newTab.tabRepresentation!
        tabRep.index = tabLocation.tabs.count

        newTab.tabRepresentation = tabRep

        addTab(newTab)

        tabLocation.appendTabRep(tabRep)
        setActiveTab(newTab)
    }
}
