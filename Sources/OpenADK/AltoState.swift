//
//  ADKState.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import Combine
import Observation
import WebKit

// MARK: - ADKState

/// ADKState provides a state for each window specificaly
/// Allows each window to display a diferent view of the tabs
@Observable
open class ADKState: ADKStateRepresentable {
    // MARK: - Peramaters

    public var id = UUID()
    public var tabManager: ADKTabManager

    public weak var window: ADKWindow?
    public var currentContent: [any Displayable]? {
        window?.setTitle("No Title") // TODO: handle nil case
        return tabManager.currentTab?.content // TODO: Move current tab to tab manager
    }

    // MARK: - Initilizer

    /// Automaticly asignes the managers state and sets up spaces
    public init(tabManager: ADKTabManager = ADKTabManager()) {
        self.tabManager = tabManager
        tabManager.state = self // Feeds in the state for the tab manager
    }

    public func setup(webView: WKWebView) {
        CookiesManager.shared.setupCookies(for: webView)
    }
}

// MARK: - ADKStateRepresentable

public protocol ADKStateRepresentable: AnyObject {
    var id: UUID { get }
    var tabManager: ADKTabManager { get set }
    var window: ADKWindow? { get set }
    var currentContent: [any Displayable]? { get }

    func setup(webView: WKWebView)
}
