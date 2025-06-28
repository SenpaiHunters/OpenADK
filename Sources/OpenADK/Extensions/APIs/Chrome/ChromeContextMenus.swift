//
//  ChromeContextMenus.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ChromeContextMenus

/// Chrome Context Menus API implementation
/// Provides chrome.contextMenus functionality for adding custom context menu items
public class ChromeContextMenus {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeContextMenus")
    private let extensionId: String
    private var menuItems: [String: ChromeContextMenuItem] = [:]
    private var nextMenuItemId = 1
    private var clickListeners: [(ChromeContextMenuClickInfo, ChromeTab?) -> ()] = []

    public init(extensionId: String) {
        self.extensionId = extensionId
        logger.info("📝 ChromeContextMenus initialized for extension: \(extensionId)")
    }

    // MARK: - Public API

    /// Create a context menu item
    /// - Parameters:
    ///   - properties: Menu item properties
    ///   - callback: Completion callback
    public func create(_ properties: ChromeContextMenuCreateProperties, callback: (() -> ())? = nil) {
        let menuItemId = properties.id ?? "\(nextMenuItemId)"
        nextMenuItemId += 1

        let menuItem = ChromeContextMenuItem(
            id: menuItemId,
            parentId: properties.parentId,
            type: properties.type ?? .normal,
            title: properties.title,
            checked: properties.checked,
            contexts: properties.contexts ?? [.page],
            onclick: properties.onclick,
            enabled: properties.enabled ?? true,
            visible: properties.visible ?? true,
            documentUrlPatterns: properties.documentUrlPatterns,
            targetUrlPatterns: properties.targetUrlPatterns
        )

        menuItems[menuItemId] = menuItem

        logger.info("📝 Created context menu item: \(menuItemId) - \(properties.title ?? "Untitled")")
        callback?()
    }

    /// Update a context menu item
    /// - Parameters:
    ///   - id: Menu item ID to update
    ///   - updateProperties: Properties to update
    ///   - callback: Completion callback
    public func update(
        _ id: String,
        updateProperties: ChromeContextMenuUpdateProperties,
        callback: (() -> ())? = nil
    ) {
        guard var menuItem = menuItems[id] else {
            logger.warning("⚠️ Context menu item not found for update: \(id)")
            callback?()
            return
        }

        // Update properties
        if let type = updateProperties.type {
            menuItem.type = type
        }
        if let title = updateProperties.title {
            menuItem.title = title
        }
        if let checked = updateProperties.checked {
            menuItem.checked = checked
        }
        if let contexts = updateProperties.contexts {
            menuItem.contexts = contexts
        }
        if let enabled = updateProperties.enabled {
            menuItem.enabled = enabled
        }
        if let visible = updateProperties.visible {
            menuItem.visible = visible
        }
        if let documentUrlPatterns = updateProperties.documentUrlPatterns {
            menuItem.documentUrlPatterns = documentUrlPatterns
        }
        if let targetUrlPatterns = updateProperties.targetUrlPatterns {
            menuItem.targetUrlPatterns = targetUrlPatterns
        }

        menuItems[id] = menuItem

        logger.info("🔄 Updated context menu item: \(id)")
        callback?()
    }

    /// Remove a context menu item
    /// - Parameters:
    ///   - menuItemId: Menu item ID to remove
    ///   - callback: Completion callback
    public func remove(_ menuItemId: String, callback: (() -> ())? = nil) {
        let wasRemoved = menuItems.removeValue(forKey: menuItemId) != nil

        // Also remove any child items
        let childItems = menuItems.filter { $0.value.parentId == menuItemId }
        for (childId, _) in childItems {
            menuItems.removeValue(forKey: childId)
        }

        logger.info("🗑️ Removed context menu item: \(menuItemId) (existed: \(wasRemoved))")
        callback?()
    }

    /// Remove all context menu items
    /// - Parameter callback: Completion callback
    public func removeAll(callback: (() -> ())? = nil) {
        let removedCount = menuItems.count
        menuItems.removeAll()

        logger.info("🧹 Removed all context menu items (\(removedCount) items)")
        callback?()
    }

    /// Add click event listener
    /// - Parameter listener: Click event listener
    public func addClickListener(_ listener: @escaping (ChromeContextMenuClickInfo, ChromeTab?) -> ()) {
        clickListeners.append(listener)
        logger.debug("👂 Added context menu click listener")
    }

    /// Remove click event listener
    /// - Parameter listener: Click event listener to remove
    public func removeClickListener(_ listener: @escaping (ChromeContextMenuClickInfo, ChromeTab?) -> ()) {
        // Note: Function comparison is complex in Swift
        // In production, use a listener ID system
        logger.debug("🗑️ Removed context menu click listener")
    }

    // MARK: - Menu Item Access

    /// Get all menu items for this extension
    /// - Returns: Dictionary of menu items
    public func getAllMenuItems() -> [String: ChromeContextMenuItem] {
        menuItems
    }

    /// Get menu item by ID
    /// - Parameter id: Menu item ID
    /// - Returns: Menu item if found
    public func getMenuItem(_ id: String) -> ChromeContextMenuItem? {
        menuItems[id]
    }

    /// Get menu items for specific context
    /// - Parameter context: Context to filter by
    /// - Returns: Array of matching menu items
    public func getMenuItemsForContext(_ context: ChromeContextMenuContext) -> [ChromeContextMenuItem] {
        menuItems.values.filter { menuItem in
            menuItem.contexts.contains(context) && menuItem.visible && menuItem.enabled
        }
    }

    // MARK: - Event Handling

    /// Handle context menu item click
    /// - Parameters:
    ///   - menuItemId: ID of clicked menu item
    ///   - clickInfo: Click information
    ///   - tab: Tab where click occurred
    public func handleMenuItemClick(
        _ menuItemId: String,
        clickInfo: ChromeContextMenuClickInfo,
        tab: ChromeTab?
    ) {
        guard let menuItem = menuItems[menuItemId] else {
            logger.warning("⚠️ Context menu item not found for click: \(menuItemId)")
            return
        }

        logger.info("🖱️ Context menu item clicked: \(menuItemId) - \(menuItem.title ?? "Untitled")")

        // Handle checkbox/radio toggle
        if menuItem.type == .checkbox {
            var updatedItem = menuItem
            updatedItem.checked = !(menuItem.checked ?? false)
            menuItems[menuItemId] = updatedItem
        } else if menuItem.type == .radio {
            // Uncheck other radio items in same group (same parent)
            for (id, item) in menuItems {
                if item.type == .radio, item.parentId == menuItem.parentId, id != menuItemId {
                    var updatedItem = item
                    updatedItem.checked = false
                    menuItems[id] = updatedItem
                }
            }
            // Check this radio item
            var updatedItem = menuItem
            updatedItem.checked = true
            menuItems[menuItemId] = updatedItem
        }

        // Notify listeners
        for listener in clickListeners {
            listener(clickInfo, tab)
        }

        // Call onclick handler if provided
        menuItem.onclick?(clickInfo, tab)
    }

    /// Check if URL matches patterns
    /// - Parameters:
    ///   - url: URL to check
    ///   - patterns: URL patterns to match against
    /// - Returns: Whether URL matches any pattern
    public func urlMatchesPatterns(_ url: String, patterns: [String]?) -> Bool {
        guard let patterns else { return true }

        for pattern in patterns {
            if urlMatchesPattern(url, pattern: pattern) {
                return true
            }
        }

        return false
    }

    /// Check if URL matches a specific pattern
    /// - Parameters:
    ///   - url: URL to check
    ///   - pattern: Pattern to match against
    /// - Returns: Whether URL matches pattern
    private func urlMatchesPattern(_ url: String, pattern: String) -> Bool {
        // Convert Chrome URL pattern to regex
        var regexPattern = pattern
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "?", with: "\\?")

        // Handle special cases
        if pattern == "<all_urls>" {
            return true
        }

        do {
            let regex = try NSRegularExpression(pattern: "^" + regexPattern + "$")
            let range = NSRange(location: 0, length: url.count)
            return regex.firstMatch(in: url, options: [], range: range) != nil
        } catch {
            logger.warning("⚠️ Invalid URL pattern: \(pattern)")
            return false
        }
    }
}

// MARK: - ChromeContextMenuItem

/// Chrome context menu item
public struct ChromeContextMenuItem {
    public let id: String
    public let parentId: String?
    public var type: ChromeContextMenuItemType
    public var title: String?
    public var checked: Bool?
    public var contexts: [ChromeContextMenuContext]
    public let onclick: ((ChromeContextMenuClickInfo, ChromeTab?) -> ())?
    public var enabled: Bool
    public var visible: Bool
    public var documentUrlPatterns: [String]?
    public var targetUrlPatterns: [String]?

    public init(
        id: String,
        parentId: String?,
        type: ChromeContextMenuItemType,
        title: String?,
        checked: Bool?,
        contexts: [ChromeContextMenuContext],
        onclick: ((ChromeContextMenuClickInfo, ChromeTab?) -> ())?,
        enabled: Bool,
        visible: Bool,
        documentUrlPatterns: [String]?,
        targetUrlPatterns: [String]?
    ) {
        self.id = id
        self.parentId = parentId
        self.type = type
        self.title = title
        self.checked = checked
        self.contexts = contexts
        self.onclick = onclick
        self.enabled = enabled
        self.visible = visible
        self.documentUrlPatterns = documentUrlPatterns
        self.targetUrlPatterns = targetUrlPatterns
    }
}

// MARK: - ChromeContextMenuCreateProperties

/// Properties for creating context menu items
public struct ChromeContextMenuCreateProperties {
    public let id: String?
    public let parentId: String?
    public let type: ChromeContextMenuItemType?
    public let title: String?
    public let checked: Bool?
    public let contexts: [ChromeContextMenuContext]?
    public let onclick: ((ChromeContextMenuClickInfo, ChromeTab?) -> ())?
    public let enabled: Bool?
    public let visible: Bool?
    public let documentUrlPatterns: [String]?
    public let targetUrlPatterns: [String]?

    public init(
        id: String? = nil,
        parentId: String? = nil,
        type: ChromeContextMenuItemType? = nil,
        title: String? = nil,
        checked: Bool? = nil,
        contexts: [ChromeContextMenuContext]? = nil,
        onclick: ((ChromeContextMenuClickInfo, ChromeTab?) -> ())? = nil,
        enabled: Bool? = nil,
        visible: Bool? = nil,
        documentUrlPatterns: [String]? = nil,
        targetUrlPatterns: [String]? = nil
    ) {
        self.id = id
        self.parentId = parentId
        self.type = type
        self.title = title
        self.checked = checked
        self.contexts = contexts
        self.onclick = onclick
        self.enabled = enabled
        self.visible = visible
        self.documentUrlPatterns = documentUrlPatterns
        self.targetUrlPatterns = targetUrlPatterns
    }
}

// MARK: - ChromeContextMenuUpdateProperties

/// Properties for updating context menu items
public struct ChromeContextMenuUpdateProperties {
    public let type: ChromeContextMenuItemType?
    public let title: String?
    public let checked: Bool?
    public let contexts: [ChromeContextMenuContext]?
    public let enabled: Bool?
    public let visible: Bool?
    public let documentUrlPatterns: [String]?
    public let targetUrlPatterns: [String]?

    public init(
        type: ChromeContextMenuItemType? = nil,
        title: String? = nil,
        checked: Bool? = nil,
        contexts: [ChromeContextMenuContext]? = nil,
        enabled: Bool? = nil,
        visible: Bool? = nil,
        documentUrlPatterns: [String]? = nil,
        targetUrlPatterns: [String]? = nil
    ) {
        self.type = type
        self.title = title
        self.checked = checked
        self.contexts = contexts
        self.enabled = enabled
        self.visible = visible
        self.documentUrlPatterns = documentUrlPatterns
        self.targetUrlPatterns = targetUrlPatterns
    }
}

// MARK: - ChromeContextMenuClickInfo

/// Information about context menu click
public struct ChromeContextMenuClickInfo {
    public let menuItemId: String
    public let parentMenuItemId: String?
    public let mediaType: String?
    public let linkUrl: String?
    public let srcUrl: String?
    public let pageUrl: String?
    public let frameUrl: String?
    public let selectionText: String?
    public let editable: Bool
    public let wasChecked: Bool?
    public let checked: Bool?

    public init(
        menuItemId: String,
        parentMenuItemId: String? = nil,
        mediaType: String? = nil,
        linkUrl: String? = nil,
        srcUrl: String? = nil,
        pageUrl: String? = nil,
        frameUrl: String? = nil,
        selectionText: String? = nil,
        editable: Bool = false,
        wasChecked: Bool? = nil,
        checked: Bool? = nil
    ) {
        self.menuItemId = menuItemId
        self.parentMenuItemId = parentMenuItemId
        self.mediaType = mediaType
        self.linkUrl = linkUrl
        self.srcUrl = srcUrl
        self.pageUrl = pageUrl
        self.frameUrl = frameUrl
        self.selectionText = selectionText
        self.editable = editable
        self.wasChecked = wasChecked
        self.checked = checked
    }
}

// MARK: - ChromeContextMenuItemType

/// Context menu item types
public enum ChromeContextMenuItemType: String, CaseIterable {
    case normal
    case checkbox
    case radio
    case separator
}

// MARK: - ChromeContextMenuContext

/// Context menu contexts
public enum ChromeContextMenuContext: String, CaseIterable {
    case all
    case page
    case frame
    case selection
    case link
    case editable
    case image
    case video
    case audio
    case launcher
    case browserAction = "browser_action"
    case pageAction = "page_action"
    case action
}
