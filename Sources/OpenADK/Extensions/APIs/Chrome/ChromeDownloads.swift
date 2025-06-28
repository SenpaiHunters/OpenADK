//
//  ChromeDownloads.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ChromeDownloads

/// Chrome Downloads API implementation
/// Provides chrome.downloads functionality for managing downloads
public class ChromeDownloads {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeDownloads")
    private let extensionId: String
    private var downloads: [Int: ChromeDownloadItem] = [:]
    private var nextDownloadId = 1
    private var listeners: [ChromeDownloadsEventType: [(ChromeDownloadItem) -> ()]] = [:]

    public init(extensionId: String) {
        self.extensionId = extensionId
        logger.info("📥 ChromeDownloads initialized for extension: \(extensionId)")
    }

    // MARK: - Public API

    /// Download a file
    /// - Parameters:
    ///   - options: Download options
    ///   - callback: Completion callback with download ID
    public func download(
        _ options: ChromeDownloadOptions,
        callback: @escaping (Int?) -> ()
    ) {
        let downloadId = nextDownloadId
        nextDownloadId += 1

        let downloadItem = ChromeDownloadItem(
            id: downloadId,
            url: options.url,
            referrer: options.referrer,
            filename: options.filename ?? URL(string: options.url)?.lastPathComponent ?? "download",
            incognito: options.incognito ?? false,
            danger: .safe,
            mime: options.saveAs != nil ? "application/octet-stream" : nil,
            startTime: Date().timeIntervalSince1970 * 1000,
            endTime: nil,
            estimatedEndTime: nil,
            state: .inProgress,
            paused: false,
            canResume: true,
            bytesReceived: 0,
            totalBytes: 0,
            fileSize: 0,
            exists: false,
            byExtensionId: extensionId,
            byExtensionName: nil
        )

        downloads[downloadId] = downloadItem

        logger.info("📥 Starting download: \(downloadId) - \(options.url)")

        // Trigger download started event
        notifyListeners(type: .onCreated, item: downloadItem)

        // Simulate download progress (in real implementation, integrate with system download manager)
        DispatchQueue.global().async {
            self.simulateDownloadProgress(downloadId: downloadId)
        }

        callback(downloadId)
    }

    /// Search for downloads
    /// - Parameters:
    ///   - query: Search query
    ///   - callback: Completion callback with matching downloads
    public func search(
        _ query: ChromeDownloadQuery,
        callback: @escaping ([ChromeDownloadItem]) -> ()
    ) {
        var results = Array(downloads.values)

        // Apply filters
        if let urlRegex = query.urlRegex {
            results = results.filter { item in
                item.url.range(of: urlRegex, options: .regularExpression) != nil
            }
        }

        if let filenameRegex = query.filenameRegex {
            results = results.filter { item in
                item.filename.range(of: filenameRegex, options: .regularExpression) != nil
            }
        }

        if let state = query.state {
            results = results.filter { $0.state == state }
        }

        if let danger = query.danger {
            results = results.filter { $0.danger == danger }
        }

        if let mime = query.mime {
            results = results.filter { $0.mime == mime }
        }

        if let startedBefore = query.startedBefore {
            results = results.filter { $0.startTime < startedBefore }
        }

        if let startedAfter = query.startedAfter {
            results = results.filter { $0.startTime > startedAfter }
        }

        if let endedBefore = query.endedBefore {
            results = results.filter { item in
                guard let endTime = item.endTime else { return false }
                return endTime < endedBefore
            }
        }

        if let endedAfter = query.endedAfter {
            results = results.filter { item in
                guard let endTime = item.endTime else { return false }
                return endTime > endedAfter
            }
        }

        if let totalBytesGreater = query.totalBytesGreater {
            results = results.filter { $0.totalBytes > totalBytesGreater }
        }

        if let totalBytesLess = query.totalBytesLess {
            results = results.filter { $0.totalBytes < totalBytesLess }
        }

        // Apply limit
        if let limit = query.limit {
            results = Array(results.prefix(limit))
        }

        // Sort by start time (most recent first)
        results.sort { $0.startTime > $1.startTime }

        logger.debug("🔍 Download search returned \(results.count) results")
        callback(results)
    }

    /// Pause a download
    /// - Parameters:
    ///   - downloadId: Download ID to pause
    ///   - callback: Completion callback
    public func pause(_ downloadId: Int, callback: (() -> ())? = nil) {
        guard var download = downloads[downloadId] else {
            logger.warning("⚠️ Download not found for pause: \(downloadId)")
            callback?()
            return
        }

        download.paused = true
        download.state = .interrupted
        downloads[downloadId] = download

        logger.info("⏸️ Paused download: \(downloadId)")
        notifyListeners(type: .onChanged, item: download)
        callback?()
    }

    /// Resume a download
    /// - Parameters:
    ///   - downloadId: Download ID to resume
    ///   - callback: Completion callback
    public func resume(_ downloadId: Int, callback: (() -> ())? = nil) {
        guard var download = downloads[downloadId] else {
            logger.warning("⚠️ Download not found for resume: \(downloadId)")
            callback?()
            return
        }

        guard download.canResume else {
            logger.warning("⚠️ Download cannot be resumed: \(downloadId)")
            callback?()
            return
        }

        download.paused = false
        download.state = .inProgress
        downloads[downloadId] = download

        logger.info("▶️ Resumed download: \(downloadId)")
        notifyListeners(type: .onChanged, item: download)
        callback?()
    }

    /// Cancel a download
    /// - Parameters:
    ///   - downloadId: Download ID to cancel
    ///   - callback: Completion callback
    public func cancel(_ downloadId: Int, callback: (() -> ())? = nil) {
        guard var download = downloads[downloadId] else {
            logger.warning("⚠️ Download not found for cancel: \(downloadId)")
            callback?()
            return
        }

        download.state = .interrupted
        download.paused = false
        downloads[downloadId] = download

        logger.info("❌ Cancelled download: \(downloadId)")
        notifyListeners(type: .onChanged, item: download)
        callback?()
    }

    /// Erase matching downloads from history
    /// - Parameters:
    ///   - query: Downloads to erase
    ///   - callback: Completion callback with erased download IDs
    public func erase(
        _ query: ChromeDownloadQuery,
        callback: @escaping ([Int]) -> ()
    ) {
        search(query) { [weak self] items in
            guard let self else { return }

            var erasedIds: [Int] = []

            for item in items {
                downloads.removeValue(forKey: item.id)
                erasedIds.append(item.id)
                notifyListeners(type: .onErased, item: item)
            }

            logger.info("🗑️ Erased \(erasedIds.count) downloads")
            callback(erasedIds)
        }
    }

    /// Remove downloaded file from disk
    /// - Parameters:
    ///   - downloadId: Download ID
    ///   - callback: Completion callback
    public func removeFile(_ downloadId: Int, callback: (() -> ())? = nil) {
        guard var download = downloads[downloadId] else {
            logger.warning("⚠️ Download not found for file removal: \(downloadId)")
            callback?()
            return
        }

        download.exists = false
        downloads[downloadId] = download

        logger.info("🗑️ Removed download file: \(downloadId)")
        notifyListeners(type: .onChanged, item: download)
        callback?()
    }

    /// Show download in system file manager
    /// - Parameter downloadId: Download ID to show
    public func show(_ downloadId: Int) {
        guard let download = downloads[downloadId] else {
            logger.warning("⚠️ Download not found for show: \(downloadId)")
            return
        }

        logger.info("👁️ Showing download in file manager: \(downloadId)")
        // In real implementation, this would open the file in Finder/Explorer
    }

    /// Open downloaded file
    /// - Parameter downloadId: Download ID to open
    public func open(_ downloadId: Int) {
        guard let download = downloads[downloadId] else {
            logger.warning("⚠️ Download not found for open: \(downloadId)")
            return
        }

        guard download.exists, download.state == .complete else {
            logger.warning("⚠️ Download not available for opening: \(downloadId)")
            return
        }

        logger.info("📂 Opening download: \(downloadId)")
        // In real implementation, this would open the file with default application
    }

    /// Get download shelf enabled state
    /// - Parameter callback: Completion callback with enabled state
    public func getFileIcon(_ downloadId: Int, callback: @escaping (String?) -> ()) {
        guard let download = downloads[downloadId] else {
            logger.warning("⚠️ Download not found for file icon: \(downloadId)")
            callback(nil)
            return
        }

        // Return mock file icon (in real implementation, get system file icon)
        let iconUrl =
            "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        callback(iconUrl)
    }

    // MARK: - Event Listeners

    /// Add event listener
    /// - Parameters:
    ///   - type: Event type
    ///   - listener: Event listener
    public func addEventListener(
        _ type: ChromeDownloadsEventType,
        listener: @escaping (ChromeDownloadItem) -> ()
    ) {
        if listeners[type] == nil {
            listeners[type] = []
        }
        listeners[type]?.append(listener)
        logger.debug("👂 Added \(type.rawValue) event listener")
    }

    /// Remove event listener
    /// - Parameters:
    ///   - type: Event type
    ///   - listener: Event listener to remove
    public func removeEventListener(
        _ type: ChromeDownloadsEventType,
        listener: @escaping (ChromeDownloadItem) -> ()
    ) {
        // Note: Function comparison is complex in Swift
        // In production, use a listener ID system
        logger.debug("🗑️ Removed \(type.rawValue) event listener")
    }

    // MARK: - Private Methods

    private func notifyListeners(type: ChromeDownloadsEventType, item: ChromeDownloadItem) {
        guard let eventListeners = listeners[type] else { return }

        for listener in eventListeners {
            listener(item)
        }
    }

    private func simulateDownloadProgress(downloadId: Int) {
        guard var download = downloads[downloadId] else { return }

        let totalBytes = Int.random(in: 100_000...10_000_000) // Random file size
        download.totalBytes = totalBytes
        downloads[downloadId] = download

        var bytesReceived = 0
        let chunkSize = totalBytes / 10

        for i in 1...10 {
            Thread.sleep(forTimeInterval: 0.5) // Simulate download time

            bytesReceived = min(bytesReceived + chunkSize, totalBytes)
            download.bytesReceived = bytesReceived

            if i == 10 {
                download.state = .complete
                download.endTime = Date().timeIntervalSince1970 * 1000
                download.fileSize = totalBytes
                download.exists = true
            }

            downloads[downloadId] = download

            DispatchQueue.main.async {
                self.notifyListeners(type: .onChanged, item: download)
            }
        }
    }
}

// MARK: - ChromeDownloadItem

/// Chrome download item
public struct ChromeDownloadItem {
    public let id: Int
    public let url: String
    public let referrer: String?
    public let filename: String
    public let incognito: Bool
    public let danger: ChromeDownloadDangerType
    public let mime: String?
    public let startTime: Double
    public var endTime: Double?
    public var estimatedEndTime: Double?
    public var state: ChromeDownloadState
    public var paused: Bool
    public let canResume: Bool
    public var bytesReceived: Int
    public var totalBytes: Int
    public var fileSize: Int
    public var exists: Bool
    public let byExtensionId: String?
    public let byExtensionName: String?
}

// MARK: - ChromeDownloadOptions

/// Download options for creating a download
public struct ChromeDownloadOptions {
    public let url: String
    public let filename: String?
    public let conflictAction: ChromeDownloadFilenameConflictAction?
    public let saveAs: Bool?
    public let method: String?
    public let headers: [String: String]?
    public let body: String?
    public let incognito: Bool?
    public let referrer: String?

    public init(
        url: String,
        filename: String? = nil,
        conflictAction: ChromeDownloadFilenameConflictAction? = nil,
        saveAs: Bool? = nil,
        method: String? = nil,
        headers: [String: String]? = nil,
        body: String? = nil,
        incognito: Bool? = nil,
        referrer: String? = nil
    ) {
        self.url = url
        self.filename = filename
        self.conflictAction = conflictAction
        self.saveAs = saveAs
        self.method = method
        self.headers = headers
        self.body = body
        self.incognito = incognito
        self.referrer = referrer
    }
}

// MARK: - ChromeDownloadQuery

/// Download query for searching downloads
public struct ChromeDownloadQuery {
    public let query: [String]?
    public let startedBefore: Double?
    public let startedAfter: Double?
    public let endedBefore: Double?
    public let endedAfter: Double?
    public let totalBytesGreater: Int?
    public let totalBytesLess: Int?
    public let filenameRegex: String?
    public let urlRegex: String?
    public let limit: Int?
    public let orderBy: [String]?
    public let id: Int?
    public let url: String?
    public let filename: String?
    public let danger: ChromeDownloadDangerType?
    public let mime: String?
    public let startTime: Double?
    public let endTime: Double?
    public let state: ChromeDownloadState?
    public let paused: Bool?
    public let error: String?
    public let bytesReceived: Int?
    public let totalBytes: Int?
    public let fileSize: Int?
    public let exists: Bool?

    public init(
        query: [String]? = nil,
        startedBefore: Double? = nil,
        startedAfter: Double? = nil,
        endedBefore: Double? = nil,
        endedAfter: Double? = nil,
        totalBytesGreater: Int? = nil,
        totalBytesLess: Int? = nil,
        filenameRegex: String? = nil,
        urlRegex: String? = nil,
        limit: Int? = nil,
        orderBy: [String]? = nil,
        id: Int? = nil,
        url: String? = nil,
        filename: String? = nil,
        danger: ChromeDownloadDangerType? = nil,
        mime: String? = nil,
        startTime: Double? = nil,
        endTime: Double? = nil,
        state: ChromeDownloadState? = nil,
        paused: Bool? = nil,
        error: String? = nil,
        bytesReceived: Int? = nil,
        totalBytes: Int? = nil,
        fileSize: Int? = nil,
        exists: Bool? = nil
    ) {
        self.query = query
        self.startedBefore = startedBefore
        self.startedAfter = startedAfter
        self.endedBefore = endedBefore
        self.endedAfter = endedAfter
        self.totalBytesGreater = totalBytesGreater
        self.totalBytesLess = totalBytesLess
        self.filenameRegex = filenameRegex
        self.urlRegex = urlRegex
        self.limit = limit
        self.orderBy = orderBy
        self.id = id
        self.url = url
        self.filename = filename
        self.danger = danger
        self.mime = mime
        self.startTime = startTime
        self.endTime = endTime
        self.state = state
        self.paused = paused
        self.error = error
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.fileSize = fileSize
        self.exists = exists
    }
}

// MARK: - ChromeDownloadState

/// Download states
public enum ChromeDownloadState: String, CaseIterable {
    case inProgress = "in_progress"
    case interrupted
    case complete
}

// MARK: - ChromeDownloadDangerType

/// Download danger types
public enum ChromeDownloadDangerType: String, CaseIterable {
    case file
    case url
    case content
    case uncommon
    case host
    case unwanted
    case safe
    case accepted
}

// MARK: - ChromeDownloadFilenameConflictAction

/// Filename conflict actions
public enum ChromeDownloadFilenameConflictAction: String, CaseIterable {
    case uniquify
    case overwrite
    case prompt
}

// MARK: - ChromeDownloadsEventType

/// Download event types
public enum ChromeDownloadsEventType: String, CaseIterable {
    case onCreated
    case onErased
    case onChanged
    case onDeterminingFilename
}
