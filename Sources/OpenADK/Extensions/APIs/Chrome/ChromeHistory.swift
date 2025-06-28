//
//  ChromeHistory.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ChromeHistory

/// Chrome History API implementation
/// Provides chrome.history functionality for accessing and managing browser history
public class ChromeHistory {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeHistory")

    private let extensionId: String
    private var visitedListeners: [(ChromeHistoryItem) -> ()] = []
    private var visitRemovedListeners: [(ChromeHistoryRemovedResult) -> ()] = []

    public init(extensionId: String) {
        self.extensionId = extensionId
        logger.info("📚 ChromeHistory initialized for extension: \(extensionId)")
    }

    // MARK: - Public API

    /// Search browser history
    /// - Parameters:
    ///   - query: Search query
    ///   - callback: Callback with search results
    public func search(
        _ query: ChromeHistoryQuery,
        callback: @escaping ([ChromeHistoryItem]) -> ()
    ) {
        // Mock implementation - would search actual browser history
        let mockResults: [ChromeHistoryItem] = []

        callback(mockResults)
        logger.debug("🔍 Searched history with query: \(query.text)")
    }

    /// Get visits for a URL
    /// - Parameters:
    ///   - details: URL details
    ///   - callback: Callback with visit results
    public func getVisits(
        _ details: ChromeHistoryUrlDetails,
        callback: @escaping ([ChromeHistoryVisitItem]) -> ()
    ) {
        // Mock implementation - would get actual visits
        let mockVisits: [ChromeHistoryVisitItem] = []

        callback(mockVisits)
        logger.debug("📊 Retrieved visits for URL: \(details.url)")
    }

    /// Add URL to history
    /// - Parameters:
    ///   - details: URL details to add
    ///   - callback: Completion callback
    public func addUrl(
        _ details: ChromeHistoryUrlDetails,
        callback: (() -> ())? = nil
    ) {
        let historyItem = ChromeHistoryItem(
            id: UUID().uuidString,
            url: details.url,
            title: "Added via Extension",
            lastVisitTime: Date().timeIntervalSince1970 * 1000,
            visitCount: 1,
            typedCount: 0
        )

        // Trigger visited event
        for listener in visitedListeners {
            listener(historyItem)
        }

        callback?()
        logger.info("✅ Added URL to history: \(details.url)")
    }

    /// Delete URL from history
    /// - Parameters:
    ///   - details: URL details to delete
    ///   - callback: Completion callback
    public func deleteUrl(
        _ details: ChromeHistoryUrlDetails,
        callback: (() -> ())? = nil
    ) {
        let removedResult = ChromeHistoryRemovedResult(
            allHistory: false,
            urls: [details.url]
        )

        // Trigger visit removed event
        for listener in visitRemovedListeners {
            listener(removedResult)
        }

        callback?()
        logger.info("🗑️ Deleted URL from history: \(details.url)")
    }

    /// Delete range of history
    /// - Parameters:
    ///   - range: Time range to delete
    ///   - callback: Completion callback
    public func deleteRange(
        _ range: ChromeHistoryRange,
        callback: (() -> ())? = nil
    ) {
        let removedResult = ChromeHistoryRemovedResult(
            allHistory: false,
            urls: []
        )

        // Trigger visit removed event
        for listener in visitRemovedListeners {
            listener(removedResult)
        }

        callback?()
        logger.info("🗑️ Deleted history range: \(range.startTime) to \(range.endTime)")
    }

    /// Delete all history
    /// - Parameter callback: Completion callback
    public func deleteAll(callback: (() -> ())? = nil) {
        let removedResult = ChromeHistoryRemovedResult(
            allHistory: true,
            urls: []
        )

        // Trigger visit removed event
        for listener in visitRemovedListeners {
            listener(removedResult)
        }

        callback?()
        logger.info("🧹 Deleted all history")
    }

    // MARK: - Event Listeners

    /// Add visited event listener
    /// - Parameter listener: Visited event listener
    public func addVisitedListener(_ listener: @escaping (ChromeHistoryItem) -> ()) {
        visitedListeners.append(listener)
        logger.debug("👂 Added history visited listener")
    }

    /// Add visit removed event listener
    /// - Parameter listener: Visit removed event listener
    public func addVisitRemovedListener(_ listener: @escaping (ChromeHistoryRemovedResult) -> ()) {
        visitRemovedListeners.append(listener)
        logger.debug("👂 Added history visit removed listener")
    }

    /// Remove visited event listener
    /// - Parameter listener: Visited event listener to remove
    public func removeVisitedListener(_ listener: @escaping (ChromeHistoryItem) -> ()) {
        // Note: Function comparison is complex in Swift
        // In production, use a listener ID system
        logger.debug("🗑️ Removed history visited listener")
    }

    /// Remove visit removed event listener
    /// - Parameter listener: Visit removed event listener to remove
    public func removeVisitRemovedListener(_ listener: @escaping (ChromeHistoryRemovedResult) -> ()) {
        // Note: Function comparison is complex in Swift
        // In production, use a listener ID system
        logger.debug("🗑️ Removed history visit removed listener")
    }
}

// MARK: - ChromeHistoryItem

/// Chrome history item
public struct ChromeHistoryItem {
    public let id: String
    public let url: String
    public let title: String?
    public let lastVisitTime: Double
    public let visitCount: Int
    public let typedCount: Int

    public init(
        id: String,
        url: String,
        title: String?,
        lastVisitTime: Double,
        visitCount: Int,
        typedCount: Int
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.lastVisitTime = lastVisitTime
        self.visitCount = visitCount
        self.typedCount = typedCount
    }
}

// MARK: - ChromeHistoryVisitItem

/// Chrome history visit item
public struct ChromeHistoryVisitItem {
    public let id: String
    public let visitId: String
    public let visitTime: Double
    public let referringVisitId: String?
    public let transition: ChromeHistoryTransitionType

    public init(
        id: String,
        visitId: String,
        visitTime: Double,
        referringVisitId: String?,
        transition: ChromeHistoryTransitionType
    ) {
        self.id = id
        self.visitId = visitId
        self.visitTime = visitTime
        self.referringVisitId = referringVisitId
        self.transition = transition
    }
}

// MARK: - ChromeHistoryQuery

/// Chrome history query
public struct ChromeHistoryQuery {
    public let text: String
    public let startTime: Double?
    public let endTime: Double?
    public let maxResults: Int?

    public init(text: String, startTime: Double? = nil, endTime: Double? = nil, maxResults: Int? = nil) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.maxResults = maxResults
    }
}

// MARK: - ChromeHistoryUrlDetails

/// Chrome history URL details
public struct ChromeHistoryUrlDetails {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}

// MARK: - ChromeHistoryRange

/// Chrome history time range
public struct ChromeHistoryRange {
    public let startTime: Double
    public let endTime: Double

    public init(startTime: Double, endTime: Double) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

// MARK: - ChromeHistoryRemovedResult

/// Chrome history removed result
public struct ChromeHistoryRemovedResult {
    public let allHistory: Bool
    public let urls: [String]

    public init(allHistory: Bool, urls: [String]) {
        self.allHistory = allHistory
        self.urls = urls
    }
}

// MARK: - ChromeHistoryTransitionType

/// Chrome history transition types
public enum ChromeHistoryTransitionType: String, CaseIterable {
    case link
    case typed
    case autoBookmark = "auto_bookmark"
    case autoSubframe = "auto_subframe"
    case manualSubframe = "manual_subframe"
    case generated
    case startPage = "start_page"
    case formSubmit = "form_submit"
    case reload
    case keyword
    case keywordGenerated = "keyword_generated"
}
