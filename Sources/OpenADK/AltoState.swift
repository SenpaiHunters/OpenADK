//
//  AltoState.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import Combine
import Observation
import WebKit

// MARK: - GenaricState

/// GenaricState provides a state for each window specificaly
/// Allows each window to display a diferent view of the tabs
@Observable
open class GenaricState {
    // MARK: - Peramaters

    public var id: UUID = .init()
    public var tabManager = TabsManager()
  
    public var window: AltoWindow?
    public var currentSpace: Space?
    public var profile: Profile?
    public var currentContent: [any Displayable]? {
        window?.title = currentSpace?.currentTab?.activeContent?.title ?? "WEIRD"
        return currentSpace?.currentTab?.content
    }

    // MARK: - Initilizer

    /// Automaticly asignes the managers state and sets up spaces
    public init() {
        tabManager.state = self // Feeds in the state for the tab manager

        currentSpace = Alto.shared.spaces[0]
    }

    public func setup(webView: WKWebView) {
        Alto.shared.cookieManager.setupCookies(for: webView)
    }

    public func setCurrentSpace() {}
}
