//
//  ChromeBookmarks.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ChromeBookmarks

/// Chrome Bookmarks API implementation
/// Provides chrome.bookmarks functionality for accessing and managing bookmarks
public class ChromeBookmarks {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeBookmarks")

    private let extensionId: String
    private var createdListeners: [(ChromeBookmarkTreeNode) -> ()] = []
    private var removedListeners: [(String, ChromeBookmarkRemoveInfo) -> ()] = []
    private var changedListeners: [(String, ChromeBookmarkChangeInfo) -> ()] = []
    private var movedListeners: [(String, ChromeBookmarkMoveInfo) -> ()] = []

    public init(extensionId: String) {
        self.extensionId = extensionId
        logger.info("🔖 ChromeBookmarks initialized for extension: \(extensionId)")
    }

    // MARK: - Public API

    /// Get bookmark tree
    /// - Parameter callback: Callback with bookmark tree
    public func getTree(_ callback: @escaping ([ChromeBookmarkTreeNode]) -> ()) {
        // TODO: This would integrate with browser bookmarks
        /// However, i'm unsure how or if we'd do this with Alto.
        /// so for the time being, we'll just return a mock root node.
        let mockRootNode = ChromeBookmarkTreeNode(
            id: "0",
            parentId: nil,
            title: "",
            url: nil,
            dateAdded: Date().timeIntervalSince1970 * 1000,
            dateGroupModified: nil,
            children: [
                ChromeBookmarkTreeNode(
                    id: "1",
                    parentId: "0",
                    title: "Bookmarks Bar",
                    url: nil,
                    dateAdded: Date().timeIntervalSince1970 * 1000,
                    dateGroupModified: nil,
                    children: []
                ),
                ChromeBookmarkTreeNode(
                    id: "2",
                    parentId: "0",
                    title: "Other Bookmarks",
                    url: nil,
                    dateAdded: Date().timeIntervalSince1970 * 1000,
                    dateGroupModified: nil,
                    children: []
                )
            ]
        )

        callback([mockRootNode])
        logger.debug("📖 Retrieved bookmark tree")
    }

    /// Get bookmark subtree
    /// - Parameters:
    ///   - id: Root bookmark ID
    ///   - callback: Callback with bookmark subtree
    public func getSubTree(_ id: String, callback: @escaping ([ChromeBookmarkTreeNode]) -> ()) {
        // Mock implementation - would fetch actual subtree
        callback([])
        logger.debug("📖 Retrieved bookmark subtree for: \(id)")
    }

    /// Search bookmarks
    /// - Parameters:
    ///   - query: Search query (string or object)
    ///   - callback: Callback with search results
    public func search(_ query: Any, callback: @escaping ([ChromeBookmarkTreeNode]) -> ()) {
        // Mock implementation - would perform actual search
        callback([])
        logger.debug("🔍 Searched bookmarks")
    }

    /// Get recent bookmarks
    /// - Parameters:
    ///   - numberOfItems: Number of recent bookmarks to get
    ///   - callback: Callback with recent bookmarks
    public func getRecent(_ numberOfItems: Int, callback: @escaping ([ChromeBookmarkTreeNode]) -> ()) {
        // Mock implementation - would fetch recent bookmarks
        callback([])
        logger.debug("📅 Retrieved \(numberOfItems) recent bookmarks")
    }

    /// Create bookmark
    /// - Parameters:
    ///   - bookmark: Bookmark creation properties
    ///   - callback: Callback with created bookmark
    public func create(
        _ bookmark: ChromeBookmarkCreateDetails,
        callback: @escaping (ChromeBookmarkTreeNode?) -> ()
    ) {
        let newBookmark = ChromeBookmarkTreeNode(
            id: UUID().uuidString,
            parentId: bookmark.parentId ?? "1",
            title: bookmark.title ?? "",
            url: bookmark.url,
            dateAdded: Date().timeIntervalSince1970 * 1000,
            dateGroupModified: nil,
            children: bookmark.url == nil ? [] : nil // Folders have children, bookmarks don't
        )

        // Trigger created event
        for listener in createdListeners {
            listener(newBookmark)
        }

        callback(newBookmark)
        logger.info("✅ Created bookmark: \(bookmark.title ?? "Untitled")")
    }

    /// Update bookmark
    /// - Parameters:
    ///   - id: Bookmark ID to update
    ///   - changes: Changes to apply
    ///   - callback: Callback with updated bookmark
    public func update(
        _ id: String,
        changes: ChromeBookmarkUpdateChanges,
        callback: @escaping (ChromeBookmarkTreeNode?) -> ()
    ) {
        // Mock implementation - would update actual bookmark
        let changeInfo = ChromeBookmarkChangeInfo(
            title: changes.title,
            url: changes.url
        )

        // Trigger changed event
        for listener in changedListeners {
            listener(id, changeInfo)
        }

        callback(nil)
        logger.debug("🔄 Updated bookmark: \(id)")
    }

    /// Remove bookmark
    /// - Parameters:
    ///   - id: Bookmark ID to remove
    ///   - callback: Completion callback
    public func remove(_ id: String, callback: (() -> ())? = nil) {
        let removeInfo = ChromeBookmarkRemoveInfo(
            parentId: "1",
            index: 0,
            node: ChromeBookmarkTreeNode(
                id: id,
                parentId: "1",
                title: "Removed Bookmark",
                url: "https://example.com",
                dateAdded: Date().timeIntervalSince1970 * 1000,
                dateGroupModified: nil,
                children: nil
            )
        )

        // Trigger removed event
        for listener in removedListeners {
            listener(id, removeInfo)
        }

        callback?()
        logger.info("🗑️ Removed bookmark: \(id)")
    }

    /// Remove bookmark tree
    /// - Parameters:
    ///   - id: Root bookmark ID to remove
    ///   - callback: Completion callback
    public func removeTree(_ id: String, callback: (() -> ())? = nil) {
        // Mock implementation - would remove entire subtree
        remove(id, callback: callback)
        logger.info("🌳 Removed bookmark tree: \(id)")
    }

    /// Move bookmark
    /// - Parameters:
    ///   - id: Bookmark ID to move
    ///   - destination: Move destination
    ///   - callback: Callback with moved bookmark
    public func move(
        _ id: String,
        destination: ChromeBookmarkMoveDestination,
        callback: @escaping (ChromeBookmarkTreeNode?) -> ()
    ) {
        let moveInfo = ChromeBookmarkMoveInfo(
            parentId: destination.parentId ?? "1",
            index: destination.index ?? 0,
            oldParentId: "1",
            oldIndex: 0
        )

        // Trigger moved event
        for listener in movedListeners {
            listener(id, moveInfo)
        }

        callback(nil)
        logger.debug("📦 Moved bookmark: \(id)")
    }

    // MARK: - Event Listeners

    /// Add created event listener
    /// - Parameter listener: Created event listener
    public func addCreatedListener(_ listener: @escaping (ChromeBookmarkTreeNode) -> ()) {
        createdListeners.append(listener)
        logger.debug("👂 Added bookmark created listener")
    }

    /// Add removed event listener
    /// - Parameter listener: Removed event listener
    public func addRemovedListener(_ listener: @escaping (String, ChromeBookmarkRemoveInfo) -> ()) {
        removedListeners.append(listener)
        logger.debug("👂 Added bookmark removed listener")
    }

    /// Add changed event listener
    /// - Parameter listener: Changed event listener
    public func addChangedListener(_ listener: @escaping (String, ChromeBookmarkChangeInfo) -> ()) {
        changedListeners.append(listener)
        logger.debug("👂 Added bookmark changed listener")
    }

    /// Add moved event listener
    /// - Parameter listener: Moved event listener
    public func addMovedListener(_ listener: @escaping (String, ChromeBookmarkMoveInfo) -> ()) {
        movedListeners.append(listener)
        logger.debug("👂 Added bookmark moved listener")
    }
}

// MARK: - ChromeBookmarkTreeNode

/// Chrome bookmark tree node
public struct ChromeBookmarkTreeNode {
    public let id: String
    public let parentId: String?
    public let title: String
    public let url: String?
    public let dateAdded: Double
    public let dateGroupModified: Double?
    public let children: [ChromeBookmarkTreeNode]?

    public init(
        id: String,
        parentId: String?,
        title: String,
        url: String?,
        dateAdded: Double,
        dateGroupModified: Double?,
        children: [ChromeBookmarkTreeNode]?
    ) {
        self.id = id
        self.parentId = parentId
        self.title = title
        self.url = url
        self.dateAdded = dateAdded
        self.dateGroupModified = dateGroupModified
        self.children = children
    }
}

// MARK: - ChromeBookmarkCreateDetails

/// Bookmark creation details
public struct ChromeBookmarkCreateDetails {
    public let parentId: String?
    public let index: Int?
    public let title: String?
    public let url: String?

    public init(parentId: String? = nil, index: Int? = nil, title: String? = nil, url: String? = nil) {
        self.parentId = parentId
        self.index = index
        self.title = title
        self.url = url
    }
}

// MARK: - ChromeBookmarkUpdateChanges

/// Bookmark update changes
public struct ChromeBookmarkUpdateChanges {
    public let title: String?
    public let url: String?

    public init(title: String? = nil, url: String? = nil) {
        self.title = title
        self.url = url
    }
}

// MARK: - ChromeBookmarkMoveDestination

/// Bookmark move destination
public struct ChromeBookmarkMoveDestination {
    public let parentId: String?
    public let index: Int?

    public init(parentId: String? = nil, index: Int? = nil) {
        self.parentId = parentId
        self.index = index
    }
}

// MARK: - ChromeBookmarkRemoveInfo

/// Bookmark remove info
public struct ChromeBookmarkRemoveInfo {
    public let parentId: String
    public let index: Int
    public let node: ChromeBookmarkTreeNode

    public init(parentId: String, index: Int, node: ChromeBookmarkTreeNode) {
        self.parentId = parentId
        self.index = index
        self.node = node
    }
}

// MARK: - ChromeBookmarkChangeInfo

/// Bookmark change info
public struct ChromeBookmarkChangeInfo {
    public let title: String?
    public let url: String?

    public init(title: String? = nil, url: String? = nil) {
        self.title = title
        self.url = url
    }
}

// MARK: - ChromeBookmarkMoveInfo

/// Bookmark move info
public struct ChromeBookmarkMoveInfo {
    public let parentId: String
    public let index: Int
    public let oldParentId: String
    public let oldIndex: Int

    public init(parentId: String, index: Int, oldParentId: String, oldIndex: Int) {
        self.parentId = parentId
        self.index = index
        self.oldParentId = oldParentId
        self.oldIndex = oldIndex
    }
}
