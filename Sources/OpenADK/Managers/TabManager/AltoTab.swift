//
//  AltoTab.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit
import SwiftUI
import WebKit

// MARK: - GenaricTab

/// A Genaric Tab class that can be subclassed for more specific browser use cases
@Observable
open class GenaricTab: NSObject, Identifiable {
    public let id = UUID()

    public var tabRepresentation: TabRepresentation?

    public var location: TabLocation?

    public var content: [any Displayable] = []

    public var activeContent: Displayable?

    public var state: GenaricState

    public var manager: TabsManager? {
        state.tabManager
    }

    public var isCurrentTab: Bool {
        state.currentSpace?.currentTab?.id == id
    }

    init(state: GenaricState) {
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
