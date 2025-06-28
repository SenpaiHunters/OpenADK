//
//  ChromeTabs.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog
import WebKit

// MARK: - ChromeTabs

/// Implementation of chrome.tabs API
@MainActor
public class ChromeTabs {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeTabs")

    /// Extension this API belongs to
    public let extensionId: String

    /// Permission manager for checking extension permissions
    private let permissionManager: ExtensionPermissionManager

    /// Tab event listeners
    private var activatedListeners: [(ChromeTabActiveInfo) -> ()] = []
    private var attachedListeners: [(Int, ChromeTabAttachInfo) -> ()] = []
    private var createdListeners: [(ChromeTab) -> ()] = []
    private var detachedListeners: [(Int, ChromeTabDetachInfo) -> ()] = []
    private var highlightedListeners: [(ChromeTabHighlightInfo) -> ()] = []
    private var movedListeners: [(Int, ChromeTabMoveInfo) -> ()] = []
    private var removedListeners: [(Int, ChromeTabRemoveInfo) -> ()] = []
    private var replacedListeners: [(Int, Int) -> ()] = []
    private var updatedListeners: [(Int, ChromeTabChangeInfo, ChromeTab) -> ()] = []
    private var zoomChangeListeners: [(ChromeTabZoomChangeInfo) -> ()] = []

    public init(extensionId: String, permissionManager: ExtensionPermissionManager) {
        self.extensionId = extensionId
        self.permissionManager = permissionManager
        logger.info("🔧 Chrome tabs API initialized for extension \(extensionId)")
    }

    // MARK: - Tab Management

    /// Get information about a specific tab
    /// - Parameters:
    ///   - tabId: Tab identifier
    ///   - callback: Callback with tab information
    public func get(_ tabId: Int, callback: @escaping (ChromeTab?) -> ()) {
        guard hasPermission("tabs") else {
            logger.warning("❌ No tabs permission for extension \(self.extensionId)")
            callback(nil)
            return
        }

        // Get tab from ADK tab manager
        if let tab = getADKTab(by: tabId) {
            let chromeTab = convertToChromeTab(tab, tabId: tabId)
            callback(chromeTab)
        } else {
            callback(nil)
        }

        logger.debug("📱 Retrieved tab \(tabId)")
    }

    /// Get current active tab
    /// - Parameter callback: Callback with active tab
    public func getCurrent(_ callback: @escaping (ChromeTab?) -> ()) {
        // Get current tab from tab manager
        if let currentTab = getCurrentADKTab() {
            let chromeTab = convertToChromeTab(currentTab, tabId: 1) // Would use real tab ID
            callback(chromeTab)
        } else {
            callback(nil)
        }

        logger.debug("📱 Retrieved current tab")
    }

    /// Query for tabs matching specified properties
    /// - Parameters:
    ///   - queryInfo: Query parameters
    ///   - callback: Callback with matching tabs
    public func query(_ queryInfo: ChromeTabQueryInfo, callback: @escaping ([ChromeTab]) -> ()) {
        var matchingTabs: [ChromeTab] = []

        // Get all tabs from ADK
        let allTabs = getAllADKTabs()

        for (index, tab) in allTabs.enumerated() {
            let chromeTab = convertToChromeTab(tab, tabId: index + 1)

            if tabMatchesQuery(chromeTab, queryInfo: queryInfo) {
                matchingTabs.append(chromeTab)
            }
        }

        callback(matchingTabs)
        logger.debug("📱 Queried tabs: found \(matchingTabs.count) matches")
    }

    /// Create a new tab
    /// - Parameters:
    ///   - createProperties: Tab creation properties
    ///   - callback: Callback with created tab
    public func create(_ createProperties: ChromeTabCreateProperties, callback: @escaping (ChromeTab?) -> ()) {
        guard hasPermission("tabs") else {
            logger.warning("❌ No tabs permission for extension \(self.extensionId)")
            callback(nil)
            return
        }

        // Create tab through ADK tab manager
        Task {
            let url = createProperties.url ?? "about:blank"
            let windowId = createProperties.windowId ?? 1

            // This would integrate with ADKTabManager
            // For now, create a mock tab
            let newTab = ChromeTab(
                id: Int.random(in: 1000...9999),
                index: createProperties.index ?? 0,
                windowId: windowId,
                selected: createProperties.selected ?? false,
                active: createProperties.active ?? true,
                pinned: createProperties.pinned ?? false,
                url: url,
                title: "New Tab",
                favIconUrl: nil,
                status: "loading",
                incognito: false,
                width: nil,
                height: nil,
                sessionId: nil
            )

            // Trigger created event
            triggerCreatedEvent(newTab)

            callback(newTab)
            logger.info("✅ Created new tab with URL: \(url)")
        }
    }

    /// Update properties of a tab
    /// - Parameters:
    ///   - tabId: Tab to update (nil for current tab)
    ///   - updateProperties: Properties to update
    ///   - callback: Callback with updated tab
    public func update(
        _ tabId: Int? = nil,
        updateProperties: ChromeTabUpdateProperties,
        callback: @escaping (ChromeTab?) -> ()
    ) {
        let targetTabId = tabId ?? getCurrentTabId()

        guard hasPermission("tabs") else {
            logger.warning("❌ No tabs permission for extension \(self.extensionId)")
            callback(nil)
            return
        }

        // Update tab through ADK
        if let tab = getADKTab(by: targetTabId) {
            if let url = updateProperties.url {
                // Navigate tab to new URL
                if let webView = getWebView(for: tab) {
                    if let urlObj = URL(string: url) {
                        webView.load(URLRequest(url: urlObj))
                    }
                }
            }

            let updatedTab = convertToChromeTab(tab, tabId: targetTabId)

            // Trigger updated event
            let changeInfo = ChromeTabChangeInfo(
                status: updateProperties.url != nil ? "loading" : nil,
                url: updateProperties.url,
                pinned: updateProperties.pinned,
                audible: nil,
                discarded: nil,
                autoDiscardable: nil,
                mutedInfo: nil,
                favIconUrl: nil,
                title: nil
            )
            triggerUpdatedEvent(targetTabId, changeInfo: changeInfo, tab: updatedTab)

            callback(updatedTab)
        } else {
            callback(nil)
        }

        logger.debug("🔄 Updated tab \(targetTabId)")
    }

    /// Remove/close tabs
    /// - Parameters:
    ///   - tabIds: Tab IDs to remove (single ID or array)
    ///   - callback: Completion callback
    public func remove(_ tabIds: Either<Int, [Int]>, callback: (() -> ())? = nil) {
        guard hasPermission("tabs") else {
            logger.warning("❌ No tabs permission for extension \(self.extensionId)")
            callback?()
            return
        }

        let idsToRemove: [Int] = switch tabIds {
        case let .left(singleId):
            [singleId]
        case let .right(multipleIds):
            multipleIds
        }

        for tabId in idsToRemove {
            if let tab = getADKTab(by: tabId) {
                // Close tab through ADK
                // tab.closeTab() - would call this

                // Trigger removed event
                let removeInfo = ChromeTabRemoveInfo(
                    windowId: 1, // Would get real window ID
                    isWindowClosing: false
                )
                triggerRemovedEvent(tabId, removeInfo: removeInfo)
            }
        }

        callback?()
        logger.info("🗑️ Removed \(idsToRemove.count) tabs")
    }

    /// Duplicate a tab
    /// - Parameters:
    ///   - tabId: Tab to duplicate
    ///   - callback: Callback with duplicated tab
    public func duplicate(_ tabId: Int, callback: @escaping (ChromeTab?) -> ()) {
        guard hasPermission("tabs") else {
            logger.warning("❌ No tabs permission for extension \(self.extensionId)")
            callback(nil)
            return
        }

        if let originalTab = getADKTab(by: tabId) {
            // Get current URL and duplicate
            if let webView = getWebView(for: originalTab),
               let currentURL = webView.url {
                let createProperties = ChromeTabCreateProperties(
                    windowId: nil,
                    index: nil,
                    url: currentURL.absoluteString,
                    active: false,
                    selected: nil,
                    pinned: false,
                    openerTabId: tabId
                )

                create(createProperties, callback: callback)
                return
            }
        }

        callback(nil)
        logger.debug("📄 Duplicated tab \(tabId)")
    }

    /// Reload a tab
    /// - Parameters:
    ///   - tabId: Tab to reload (nil for current tab)
    ///   - reloadProperties: Reload options
    ///   - callback: Completion callback
    public func reload(
        _ tabId: Int? = nil,
        reloadProperties: ChromeTabReloadProperties? = nil,
        callback: (() -> ())? = nil
    ) {
        let targetTabId = tabId ?? getCurrentTabId()

        if let tab = getADKTab(by: targetTabId),
           let webView = getWebView(for: tab) {
            if reloadProperties?.bypassCache == true {
                // Hard reload - clear cache first
                webView.reloadFromOrigin()
            } else {
                // Normal reload
                webView.reload()
            }
        }

        callback?()
        logger.debug("🔄 Reloaded tab \(targetTabId)")
    }

    // MARK: - Tab Movement

    /// Move tabs to new positions
    /// - Parameters:
    ///   - tabIds: Tab IDs to move
    ///   - moveProperties: Move properties
    ///   - callback: Callback with moved tabs
    public func move(
        _ tabIds: Either<Int, [Int]>,
        moveProperties: ChromeTabMoveProperties,
        callback: @escaping (Either<ChromeTab, [ChromeTab]>) -> ()
    ) {
        guard hasPermission("tabs") else {
            logger.warning("❌ No tabs permission for extension \(self.extensionId)")
            return
        }

        // Implementation would move tabs in ADK tab manager
        logger.debug("🔄 Moving tabs - not fully implemented")

        // For now, return original tabs
        switch tabIds {
        case let .left(singleId):
            get(singleId) { tab in
                if let tab {
                    callback(.left(tab))
                }
            }
        case let .right(multipleIds):
            var movedTabs: [ChromeTab] = []
            let group = DispatchGroup()

            for tabId in multipleIds {
                group.enter()
                get(tabId) { tab in
                    if let tab {
                        movedTabs.append(tab)
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                callback(.right(movedTabs))
            }
        }
    }

    // MARK: - Event Listeners

    /// Add activated event listener
    /// - Parameter listener: Event listener
    public func addActivatedListener(_ listener: @escaping (ChromeTabActiveInfo) -> ()) {
        activatedListeners.append(listener)
        logger.debug("📝 Added activated listener")
    }

    /// Add created event listener
    /// - Parameter listener: Event listener
    public func addCreatedListener(_ listener: @escaping (ChromeTab) -> ()) {
        createdListeners.append(listener)
        logger.debug("📝 Added created listener")
    }

    /// Add updated event listener
    /// - Parameter listener: Event listener
    public func addUpdatedListener(_ listener: @escaping (Int, ChromeTabChangeInfo, ChromeTab) -> ()) {
        updatedListeners.append(listener)
        logger.debug("📝 Added updated listener")
    }

    /// Add removed event listener
    /// - Parameter listener: Event listener
    public func addRemovedListener(_ listener: @escaping (Int, ChromeTabRemoveInfo) -> ()) {
        removedListeners.append(listener)
        logger.debug("📝 Added removed listener")
    }

    // MARK: - Event Triggering

    /// Trigger activated event
    /// - Parameter activeInfo: Activation info
    public func triggerActivatedEvent(_ activeInfo: ChromeTabActiveInfo) {
        for listener in activatedListeners {
            listener(activeInfo)
        }
    }

    /// Trigger created event
    /// - Parameter tab: Created tab
    private func triggerCreatedEvent(_ tab: ChromeTab) {
        for listener in createdListeners {
            listener(tab)
        }
    }

    /// Trigger updated event
    /// - Parameters:
    ///   - tabId: Updated tab ID
    ///   - changeInfo: Change information
    ///   - tab: Updated tab
    private func triggerUpdatedEvent(_ tabId: Int, changeInfo: ChromeTabChangeInfo, tab: ChromeTab) {
        for listener in updatedListeners {
            listener(tabId, changeInfo, tab)
        }
    }

    /// Trigger removed event
    /// - Parameters:
    ///   - tabId: Removed tab ID
    ///   - removeInfo: Remove information
    private func triggerRemovedEvent(_ tabId: Int, removeInfo: ChromeTabRemoveInfo) {
        for listener in removedListeners {
            listener(tabId, removeInfo)
        }
    }

    // MARK: - Helper Methods

    /// Check if extension has permission for tabs API
    private func hasPermission(_ permission: String) -> Bool {
        permissionManager.hasPermission(permission, for: extensionId)
    }

    /// Get ADK tab by ID
    /// - Parameter tabId: Tab ID
    /// - Returns: ADK tab if found
    private func getADKTab(by tabId: Int) -> ADKTab? {
        // This would integrate with actual ADK tab management
        // For now, return mock data
        nil
    }

    /// Get current ADK tab
    /// - Returns: Current ADK tab
    private func getCurrentADKTab() -> ADKTab? {
        // Get current tab from ADK tab manager
        nil
    }

    /// Get all ADK tabs
    /// - Returns: All ADK tabs
    private func getAllADKTabs() -> [ADKTab] {
        // Get all tabs from ADK
        []
    }

    /// Get current tab ID
    /// - Returns: Current tab ID
    private func getCurrentTabId() -> Int {
        1 // Would get real current tab ID
    }

    /// Get WebView for ADK tab
    /// - Parameter tab: ADK tab
    /// - Returns: WebView if available
    private func getWebView(for tab: ADKTab) -> WKWebView? {
        // For now, return nil - would need proper integration with ADKTab
        nil
    }

    /// Convert ADK tab to Chrome tab
    /// - Parameters:
    ///   - adkTab: ADK tab
    ///   - tabId: Tab ID
    /// - Returns: Chrome tab
    private func convertToChromeTab(_ adkTab: ADKTab, tabId: Int) -> ChromeTab {
        let webView = getWebView(for: adkTab)

        return ChromeTab(
            id: tabId,
            index: 0, // Would get real index
            windowId: 1, // Would get real window ID
            selected: false, // Would check if selected
            active: true, // Would check if active
            pinned: false, // Would check if pinned
            url: webView?.url?.absoluteString ?? "",
            title: webView?.title ?? "Tab",
            favIconUrl: nil, // Would get favicon
            status: "complete", // Would get real status
            incognito: false, // Would check incognito mode
            width: Int(webView?.frame.width ?? 0),
            height: Int(webView?.frame.height ?? 0),
            sessionId: nil
        )
    }

    /// Check if tab matches query
    /// - Parameters:
    ///   - tab: Tab to check
    ///   - queryInfo: Query parameters
    /// - Returns: Whether tab matches
    private func tabMatchesQuery(_ tab: ChromeTab, queryInfo: ChromeTabQueryInfo) -> Bool {
        if let active = queryInfo.active, tab.active != active { return false }
        if let pinned = queryInfo.pinned, tab.pinned != pinned { return false }
        if let url = queryInfo.url, tab.url != url { return false }
        if let title = queryInfo.title, tab.title != title { return false }
        if let windowId = queryInfo.windowId, tab.windowId != windowId { return false }
        if let currentWindow = queryInfo.currentWindow, currentWindow, tab.windowId != 1 { return false }
        if let lastFocusedWindow = queryInfo.lastFocusedWindow, lastFocusedWindow, tab.windowId != 1 { return false }
        if let status = queryInfo.status, tab.status != status { return false }
        if let windowType = queryInfo.windowType, windowType != "normal" { return false }

        return true
    }
}

// MARK: - Either

/// Either type for parameters that can be single value or array
public enum Either<Left, Right> {
    case left(Left)
    case right(Right)
}

// MARK: - ChromeTab

/// Chrome tab representation
public struct ChromeTab {
    public let id: Int
    public let index: Int
    public let windowId: Int
    public let selected: Bool
    public let active: Bool
    public let pinned: Bool
    public let url: String
    public let title: String
    public let favIconUrl: String?
    public let status: String
    public let incognito: Bool
    public let width: Int?
    public let height: Int?
    public let sessionId: String?
}

// MARK: - ChromeTabQueryInfo

/// Tab query parameters
public struct ChromeTabQueryInfo {
    public let active: Bool?
    public let pinned: Bool?
    public let audible: Bool?
    public let muted: Bool?
    public let highlighted: Bool?
    public let discarded: Bool?
    public let autoDiscardable: Bool?
    public let currentWindow: Bool?
    public let lastFocusedWindow: Bool?
    public let status: String?
    public let title: String?
    public let url: String?
    public let windowId: Int?
    public let windowType: String?
    public let index: Int?

    public init(
        active: Bool? = nil,
        pinned: Bool? = nil,
        audible: Bool? = nil,
        muted: Bool? = nil,
        highlighted: Bool? = nil,
        discarded: Bool? = nil,
        autoDiscardable: Bool? = nil,
        currentWindow: Bool? = nil,
        lastFocusedWindow: Bool? = nil,
        status: String? = nil,
        title: String? = nil,
        url: String? = nil,
        windowId: Int? = nil,
        windowType: String? = nil,
        index: Int? = nil
    ) {
        self.active = active
        self.pinned = pinned
        self.audible = audible
        self.muted = muted
        self.highlighted = highlighted
        self.discarded = discarded
        self.autoDiscardable = autoDiscardable
        self.currentWindow = currentWindow
        self.lastFocusedWindow = lastFocusedWindow
        self.status = status
        self.title = title
        self.url = url
        self.windowId = windowId
        self.windowType = windowType
        self.index = index
    }
}

// MARK: - ChromeTabCreateProperties

/// Tab creation properties
public struct ChromeTabCreateProperties {
    public let windowId: Int?
    public let index: Int?
    public let url: String?
    public let active: Bool?
    public let selected: Bool?
    public let pinned: Bool?
    public let openerTabId: Int?

    public init(
        windowId: Int? = nil,
        index: Int? = nil,
        url: String? = nil,
        active: Bool? = nil,
        selected: Bool? = nil,
        pinned: Bool? = nil,
        openerTabId: Int? = nil
    ) {
        self.windowId = windowId
        self.index = index
        self.url = url
        self.active = active
        self.selected = selected
        self.pinned = pinned
        self.openerTabId = openerTabId
    }
}

// MARK: - ChromeTabUpdateProperties

/// Tab update properties
public struct ChromeTabUpdateProperties {
    public let url: String?
    public let active: Bool?
    public let highlighted: Bool?
    public let selected: Bool?
    public let pinned: Bool?
    public let muted: Bool?
    public let openerTabId: Int?
    public let autoDiscardable: Bool?

    public init(
        url: String? = nil,
        active: Bool? = nil,
        highlighted: Bool? = nil,
        selected: Bool? = nil,
        pinned: Bool? = nil,
        muted: Bool? = nil,
        openerTabId: Int? = nil,
        autoDiscardable: Bool? = nil
    ) {
        self.url = url
        self.active = active
        self.highlighted = highlighted
        self.selected = selected
        self.pinned = pinned
        self.muted = muted
        self.openerTabId = openerTabId
        self.autoDiscardable = autoDiscardable
    }
}

// MARK: - ChromeTabReloadProperties

/// Tab reload properties
public struct ChromeTabReloadProperties {
    public let bypassCache: Bool?

    public init(bypassCache: Bool? = nil) {
        self.bypassCache = bypassCache
    }
}

// MARK: - ChromeTabMoveProperties

/// Tab move properties
public struct ChromeTabMoveProperties {
    public let windowId: Int?
    public let index: Int

    public init(windowId: Int? = nil, index: Int) {
        self.windowId = windowId
        self.index = index
    }
}

// MARK: - ChromeTabActiveInfo

/// Tab activation info
public struct ChromeTabActiveInfo {
    public let tabId: Int
    public let windowId: Int

    public init(tabId: Int, windowId: Int) {
        self.tabId = tabId
        self.windowId = windowId
    }
}

// MARK: - ChromeTabChangeInfo

/// Tab change info
public struct ChromeTabChangeInfo {
    public let status: String?
    public let url: String?
    public let pinned: Bool?
    public let audible: Bool?
    public let discarded: Bool?
    public let autoDiscardable: Bool?
    public let mutedInfo: ChromeTabMutedInfo?
    public let favIconUrl: String?
    public let title: String?

    public init(
        status: String? = nil,
        url: String? = nil,
        pinned: Bool? = nil,
        audible: Bool? = nil,
        discarded: Bool? = nil,
        autoDiscardable: Bool? = nil,
        mutedInfo: ChromeTabMutedInfo? = nil,
        favIconUrl: String? = nil,
        title: String? = nil
    ) {
        self.status = status
        self.url = url
        self.pinned = pinned
        self.audible = audible
        self.discarded = discarded
        self.autoDiscardable = autoDiscardable
        self.mutedInfo = mutedInfo
        self.favIconUrl = favIconUrl
        self.title = title
    }
}

// MARK: - ChromeTabRemoveInfo

/// Tab remove info
public struct ChromeTabRemoveInfo {
    public let windowId: Int
    public let isWindowClosing: Bool

    public init(windowId: Int, isWindowClosing: Bool) {
        self.windowId = windowId
        self.isWindowClosing = isWindowClosing
    }
}

// MARK: - ChromeTabMutedInfo

/// Tab muted info
public struct ChromeTabMutedInfo {
    public let muted: Bool
    public let reason: String?
    public let extensionId: String?

    public init(muted: Bool, reason: String? = nil, extensionId: String? = nil) {
        self.muted = muted
        self.reason = reason
        self.extensionId = extensionId
    }
}

// MARK: - ChromeTabAttachInfo

/// Additional event info types
public struct ChromeTabAttachInfo {
    public let newWindowId: Int
    public let newPosition: Int
}

// MARK: - ChromeTabDetachInfo

public struct ChromeTabDetachInfo {
    public let oldWindowId: Int
    public let oldPosition: Int
}

// MARK: - ChromeTabHighlightInfo

public struct ChromeTabHighlightInfo {
    public let windowId: Int
    public let tabIds: [Int]
}

// MARK: - ChromeTabMoveInfo

public struct ChromeTabMoveInfo {
    public let windowId: Int
    public let fromIndex: Int
    public let toIndex: Int
}

// MARK: - ChromeTabZoomChangeInfo

public struct ChromeTabZoomChangeInfo {
    public let tabId: Int
    public let oldZoomFactor: Double
    public let newZoomFactor: Double
    public let zoomSettings: ChromeTabZoomSettings
}

// MARK: - ChromeTabZoomSettings

public struct ChromeTabZoomSettings {
    public let mode: String
    public let scope: String
    public let defaultZoomFactor: Double
}
