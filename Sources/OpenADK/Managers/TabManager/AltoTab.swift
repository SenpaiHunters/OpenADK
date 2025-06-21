//
//  AltoTab.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit
import SwiftUI
import WebKit

// MARK: - TabProtocol

/// for a tab to be rendered in the browser it must conform to the tab protocol
/// The Tab can be a note, a swiftView like a canvas or a webpage
public protocol TabProtocol: NSObject, Identifiable {
    var id: UUID { get }
    var location: TabLocationProtocol? { get set }
    var content: [Displayable] { get set }
    var activeContent: Displayable? { get set }
    var state: any StateProtocol { get }
    var manager: TabManagerProtocol? { get }
    var isCurrentTab: Bool { get }
    var tabRepresentation: TabRepresentation? { get set }

    func setContent(content addedContent: any Displayable)
    func closeTab()
}

// MARK: - GenaricTab

/// A Genaric Tab class that can be subclassed for more specific browser use cases
@Observable
open class GenaricTab: NSObject, Identifiable, TabProtocol {
    public let id = UUID()

    public var tabRepresentation: TabRepresentation?

    public var location: (any TabLocationProtocol)?

    public var content: [any Displayable] = []

    public var activeContent: Displayable?

    public var state: any StateProtocol

    public var manager: (any TabManagerProtocol)? {
        state.tabManager
    }

    public var isCurrentTab: Bool {
        state.currentSpace?.currentTab?.id == id
    }

    init(state: any StateProtocol) {
        self.state = state
    }

    public func setContent(content addedContent: any Displayable) {
        if !content.isEmpty {
            content[0] = addedContent
            activeContent = addedContent
        } else {
            activeContent = addedContent
            content.append(addedContent)
        }
    }

    public func createNewTab(_: String, _: WKWebViewConfiguration, frame _: CGRect = .zero) {}

    public func closeTab() {
        location?.removeTab(id: id)
        state.tabManager.removeTab(id)
        activeContent = nil
        for c in content {
            c.removeWebView()
        }

        if isCurrentTab {
            state.currentSpace?.currentTab = nil
        }
    }
}
