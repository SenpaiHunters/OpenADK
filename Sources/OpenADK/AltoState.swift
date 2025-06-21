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
open class GenaricState: StateProtocol {
    // MARK: - Peramaters

    public var id: UUID = .init()
    public var tabManager: TabManagerProtocol = TabsManager()
    public var window: AltoWindow?
    public var currentSpace: (any SpaceProtocol)?

    public var currentContent: [any Displayable]? {
        print(currentSpace?.currentTab?.activeContent)
        window?.title = currentSpace?.currentTab?.activeContent?.title ?? "WEIRD"
        return currentSpace?.currentTab?.content
    }

    // MARK: - Initilizer

    /// Automaticly asignes the managers state and sets up spaces
    public init() {
        tabManager.state = self // Feeds in the state for the tab manager
        if currentSpace == nil {
            let space = Space(localLocations: [TabLocation()])
            currentSpace = space
            Alto.shared.spaces.append(space)
        }

        currentSpace = Alto.shared.spaces[0]
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
    var currentSpace: (any SpaceProtocol)? { get set }
    var currentContent: [Displayable]? { get }

    func setup(webView: WKWebView)
}
