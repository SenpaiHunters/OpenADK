//
//  ChromeNotifications.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog
import UniformTypeIdentifiers
import UserNotifications

// MARK: - ChromeNotifications

/// Chrome Notifications API implementation
/// Provides chrome.notifications functionality for system notifications
public class ChromeNotifications: NSObject {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeNotifications")

    private let extensionId: String
    private var notificationListeners: [(String, ChromeNotificationEventType) -> ()] = []
    private var pendingNotifications: [String: ChromeNotificationOptions] = [:]

    public init(extensionId: String) {
        self.extensionId = extensionId
        super.init()

        // Request notification permissions
        requestNotificationPermissions()

        logger.info("🔔 ChromeNotifications initialized for extension: \(extensionId)")
    }

    // MARK: - Public API

    /// Create a notification
    /// - Parameters:
    ///   - notificationId: Unique identifier for the notification (optional)
    ///   - options: Notification options
    /// - Returns: The notification ID
    public func create(
        _ notificationId: String? = nil,
        options: ChromeNotificationOptions
    ) async throws -> String {
        let finalId = notificationId ?? UUID().uuidString

        // Store notification options for event handling
        pendingNotifications[finalId] = options

        // Create and schedule the notification
        let content = await createNotificationContent(from: options)
        let request = UNNotificationRequest(
            identifier: "\(extensionId)_\(finalId)",
            content: content,
            trigger: nil // Immediate delivery
        )

        try await UNUserNotificationCenter.current().add(request)
        logger.info("🔔 Created notification: \(finalId)")

        return finalId
    }

    /// Update an existing notification
    /// - Parameters:
    ///   - notificationId: ID of notification to update
    ///   - options: New notification options
    ///   - completion: Completion callback with success status
    public func update(
        _ notificationId: String,
        options: ChromeNotificationOptions,
        completion: @escaping (Bool) -> ()
    ) {
        // Clear existing notification using the completion-based version
        clear(notificationId) { [weak self] wasCleared in
            if wasCleared {
                // Create new notification with same ID
                Task {
                    do {
                        _ = try await self?.create(notificationId, options: options)
                        await MainActor.run {
                            completion(true)
                        }
                    } catch {
                        self?.logger.error("❌ Failed to update notification: \(error)")
                        await MainActor.run {
                            completion(false)
                        }
                    }
                }
            } else {
                completion(false)
            }
        }
    }

    /// Clear a notification
    /// - Parameters:
    ///   - notificationId: ID of notification to clear
    ///   - completion: Completion callback with success status
    public func clear(
        _ notificationId: String,
        completion: @escaping (Bool) -> ()
    ) {
        let fullId = "\(extensionId)_\(notificationId)"

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [fullId])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [fullId])

        let wasCleared = pendingNotifications.removeValue(forKey: notificationId) != nil

        logger.info("🗑️ Cleared notification: \(notificationId)")

        DispatchQueue.main.async {
            completion(wasCleared)
        }
    }

    /// Get all notification IDs
    /// - Parameter completion: Completion callback with array of notification IDs
    public func getAll(completion: @escaping ([String]) -> ()) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { [weak self] requests in
            guard let self else {
                completion([])
                return
            }

            let extensionNotifications = requests.compactMap { request -> String? in
                let prefix = "\(self.extensionId)_"
                if request.identifier.hasPrefix(prefix) {
                    return String(request.identifier.dropFirst(prefix.count))
                }
                return nil
            }

            DispatchQueue.main.async {
                completion(extensionNotifications)
            }
        }
    }

    /// Get permission level
    /// - Parameter completion: Completion callback with permission level
    public func getPermissionLevel(completion: @escaping (ChromeNotificationPermissionLevel) -> ()) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let permissionLevel: ChromeNotificationPermissionLevel = switch settings.authorizationStatus {
            case .authorized,
                 .provisional:
                .granted
            case .denied:
                .denied
            case .notDetermined,
                 .ephemeral:
                .denied
            @unknown default:
                .denied
            }

            DispatchQueue.main.async {
                completion(permissionLevel)
            }
        }
    }

    /// Add notification event listener
    /// - Parameter listener: Callback function for notification events
    public func addNotificationListener(_ listener: @escaping (String, ChromeNotificationEventType) -> ()) {
        notificationListeners.append(listener)
        logger.debug("👂 Added notification listener")
    }

    /// Remove notification event listener
    /// - Parameter listener: Listener to remove
    public func removeNotificationListener(_ listener: @escaping (String, ChromeNotificationEventType) -> ()) {
        // Function comparison is complex in Swift
        // In production, use a listener ID system
        logger.debug("🗑️ Removed notification listener")
    }

    // MARK: - Private Implementation

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert,
            .sound,
            .badge
        ]) { [weak self] granted, error in
            if let error {
                self?.logger.error("❌ Failed to request notification permissions: \(error)")
            } else {
                self?.logger.info("🔔 Notification permissions granted: \(granted)")
            }
        }

        // Set delegate to handle notification events
        UNUserNotificationCenter.current().delegate = self
    }

    private func createNotificationContent(from options: ChromeNotificationOptions) async
    -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()

        content.title = options.title
        content.body = options.message

        // Download and attach icon if provided
        if let iconUrl = options.iconUrl {
            logger.debug("🖼️ Icon URL specified: \(iconUrl)")
            if let iconAttachment = await downloadAndCreateAttachment(from: iconUrl, identifier: "icon") {
                content.attachments = [iconAttachment]
            }
        }

        // Handle different notification types
        switch options.type {
        case .basic:
            // Standard notification - content already set
            break
        case .image:
            if let imageUrl = options.imageUrl {
                logger.debug("🖼️ Image URL specified: \(imageUrl)")
                if let imageAttachment = await downloadAndCreateAttachment(from: imageUrl, identifier: "image") {
                    // If we already have an icon attachment, append the image
                    if content.attachments.isEmpty {
                        content.attachments = [imageAttachment]
                    } else {
                        content.attachments.append(imageAttachment)
                    }
                }
            }
        case .list:
            if !options.items.isEmpty {
                let itemsText = options.items.map { "\(options.title): \($0.message)" }.joined(separator: "\n")
                content.body = itemsText
            }
        case .progress:
            if let progress = options.progress {
                content.body += " (\(progress)%)"
            }
        }

        // Add custom data for event handling
        content.userInfo = [
            "extensionId": extensionId,
            "notificationId": options.title, // Will be replaced with actual ID
            "type": options.type.rawValue
        ]

        return content
    }

    // Helper method to download and create notification attachments
    private func downloadAndCreateAttachment(
        from urlString: String,
        identifier: String
    ) async -> UNNotificationAttachment? {
        guard let url = URL(string: urlString) else {
            logger.error("❌ Invalid URL: \(urlString)")
            return nil
        }

        do {
            // Download the image data
            let (data, response) = try await URLSession.shared.data(from: url)

            // Validate response
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.error("❌ Failed to download image from \(urlString)")
                return nil
            }

            // Get file info using system APIs
            let fileInfo = getFileInfo(from: response, url: url)

            // Create temporary file
            let tempDirectory = FileManager.default.temporaryDirectory
            let fileName = "\(identifier)_\(UUID().uuidString).\(fileInfo.fileExtension)"
            let fileURL = tempDirectory.appendingPathComponent(fileName)

            // Write data to temporary file
            try data.write(to: fileURL)

            // Create notification attachment
            let attachment = try UNNotificationAttachment(
                identifier: identifier,
                url: fileURL,
                options: [
                    UNNotificationAttachmentOptionsTypeHintKey: fileInfo.utType
                ]
            )

            logger.debug("✅ Successfully created attachment for \(urlString)")
            return attachment

        } catch {
            logger.error("❌ Error downloading/creating attachment: \(error)")
            return nil
        }
    }

    // Helper to determine file extension and UTType using system APIs
    private func getFileInfo(from response: URLResponse, url: URL) -> (fileExtension: String, utType: String) {
        // Try to get UTType from content type
        if let mimeType = response.mimeType,
           let utType = UTType(mimeType: mimeType) {
            let fileExtension = utType.preferredFilenameExtension ?? url.pathExtension.lowercased()
            return (fileExtension.isEmpty ? "jpg" : fileExtension, utType.identifier)
        }

        // Fall back to URL extension
        let pathExtension = url.pathExtension.lowercased()
        let fileExtension = pathExtension.isEmpty ? "jpg" : pathExtension
        let utType = UTType(filenameExtension: fileExtension)?.identifier ?? UTType.image.identifier

        return (fileExtension, utType)
    }

    private func handleNotificationEvent(_ identifier: String, eventType: ChromeNotificationEventType) {
        let prefix = "\(extensionId)_"
        guard identifier.hasPrefix(prefix) else { return }

        let notificationId = String(identifier.dropFirst(prefix.count))

        // Notify listeners
        for listener in notificationListeners {
            listener(notificationId, eventType)
        }

//        logger.debug("🔔 Notification event: \(eventType) for \(notificationId)")
    }
}

// MARK: UNUserNotificationCenterDelegate

extension ChromeNotifications: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> ()
    ) {
        let identifier = response.notification.request.identifier

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            handleNotificationEvent(identifier, eventType: .clicked)
        case UNNotificationDismissActionIdentifier:
            handleNotificationEvent(identifier, eventType: .closed)
        default:
            handleNotificationEvent(identifier, eventType: .buttonClicked)
        }

        completionHandler()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> ()
    ) {
        // Show notification even when app is in foreground

        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - ChromeNotificationOptions

/// Chrome notification options
public struct ChromeNotificationOptions {
    public let type: ChromeNotificationType
    public let iconUrl: String?
    public let title: String
    public let message: String
    public let contextMessage: String?
    public let priority: Int?
    public let eventTime: Double?
    public let buttons: [ChromeNotificationButton]
    public let imageUrl: String?
    public let items: [ChromeNotificationItem]
    public let progress: Int?
    public let isClickable: Bool?

    public init(
        type: ChromeNotificationType = .basic,
        iconUrl: String? = nil,
        title: String,
        message: String,
        contextMessage: String? = nil,
        priority: Int? = nil,
        eventTime: Double? = nil,
        buttons: [ChromeNotificationButton] = [],
        imageUrl: String? = nil,
        items: [ChromeNotificationItem] = [],
        progress: Int? = nil,
        isClickable: Bool? = nil
    ) {
        self.type = type
        self.iconUrl = iconUrl
        self.title = title
        self.message = message
        self.contextMessage = contextMessage
        self.priority = priority
        self.eventTime = eventTime
        self.buttons = buttons
        self.imageUrl = imageUrl
        self.items = items
        self.progress = progress
        self.isClickable = isClickable
    }
}

// MARK: - ChromeNotificationType

/// Chrome notification types
public enum ChromeNotificationType: String, CaseIterable {
    case basic
    case image
    case list
    case progress
}

// MARK: - ChromeNotificationButton

/// Chrome notification button
public struct ChromeNotificationButton {
    public let title: String
    public let iconUrl: String?

    public init(title: String, iconUrl: String? = nil) {
        self.title = title
        self.iconUrl = iconUrl
    }
}

// MARK: - ChromeNotificationItem

/// Chrome notification list item
public struct ChromeNotificationItem {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

// MARK: - ChromeNotificationPermissionLevel

/// Chrome notification permission levels
public enum ChromeNotificationPermissionLevel: String {
    case granted
    case denied
}

// MARK: - ChromeNotificationEventType

/// Chrome notification event types
public enum ChromeNotificationEventType: String {
    case clicked
    case buttonClicked
    case closed
    case shown
}
