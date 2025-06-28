//
//  ChromeStorage.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ChromeStorage

/// Chrome Storage API implementation
/// Provides chrome.storage.local, chrome.storage.sync, and chrome.storage.session APIs
public class ChromeStorage {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeStorage")

    // Storage areas
    public let local: ChromeStorageArea
    public let sync: ChromeStorageArea
    public let session: ChromeStorageArea

    // Storage change listeners
    private var changeListeners: [(_ changes: [String: ChromeStorageChange], _ areaName: String) -> ()] = []

    // Storage quotas (bytes)
    public static let localQuota = 10 * 1024 * 1024 // 10MB
    public static let syncQuota = 100 * 1024 // 100KB
    public static let sessionQuota = 10 * 1024 * 1024 // 10MB

    public init(extensionId: String) {
        local = ChromeStorageArea(
            type: .local,
            extensionId: extensionId,
            quota: Self.localQuota
        )
        sync = ChromeStorageArea(
            type: .sync,
            extensionId: extensionId,
            quota: Self.syncQuota
        )
        session = ChromeStorageArea(
            type: .session,
            extensionId: extensionId,
            quota: Self.sessionQuota
        )

        logger.info("🗄️ ChromeStorage initialized for extension: \(extensionId)")
    }

    /// Add storage change listener
    /// - Parameter listener: Callback function for storage changes
    public func addChangeListener(_ listener: @escaping (([String: ChromeStorageChange], String) -> ())) {
        changeListeners.append(listener)
        logger.debug("👂 Added storage change listener")
    }

    /// Remove storage change listener
    /// - Parameter listener: Listener to remove
    public func removeChangeListener(_ listener: @escaping (([String: ChromeStorageChange], String) -> ())) {
        // TODO: Implementation, you'd use a listener ID system
        // Note: Function comparison is not straightforward in Swift
        logger.debug("🗑️ Removed storage change listener")
    }

    /// Notify all listeners of storage changes
    /// - Parameters:
    ///   - changes: Dictionary of storage changes
    ///   - areaName: Name of storage area that changed
    func notifyListeners(changes: [String: ChromeStorageChange], areaName: String) {
        for listener in changeListeners {
            listener(changes, areaName)
        }
    }
}

// MARK: - ChromeStorageArea

/// Chrome Storage Area (local, sync, session)
public class ChromeStorageArea {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeStorageArea")

    public let type: ChromeStorageType
    public let extensionId: String
    public let quota: Int

    private let userDefaults: UserDefaults
    private let keyPrefix: String

    public init(type: ChromeStorageType, extensionId: String, quota: Int) {
        self.type = type
        self.extensionId = extensionId
        self.quota = quota
        keyPrefix = "ChromeStorage_\(extensionId)_\(type.rawValue)_"

        // Use different UserDefaults suites for different storage types
        switch type {
        case .local,
             .session:
            userDefaults = UserDefaults.standard
        case .sync:
            // TODO: Implementation, sync storage would use CloudKit or similar
            // However, for the time being, we'll just use the standard UserDefaults.
            userDefaults = UserDefaults.standard
        }

        logger.info("🗄️ ChromeStorageArea initialized: \(type.rawValue) for \(extensionId)")
    }

    /// Get items from storage
    /// - Parameters:
    ///   - keys: Keys to retrieve (nil = all keys, String = single key, [String] = multiple keys, [String: Any] = keys
    /// with defaults)
    ///   - completion: Completion callback with retrieved items
    public func get(
        _ keys: Any?,
        completion: @escaping ([String: Any]) -> ()
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self._get(keys)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Set items in storage
    /// - Parameters:
    ///   - items: Dictionary of key-value pairs to store
    ///   - completion: Completion callback
    public func set(
        _ items: [String: Any],
        completion: ((ChromeStorageError?) -> ())? = nil
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let error = self._set(items)
            DispatchQueue.main.async {
                completion?(error)
            }
        }
    }

    /// Remove items from storage
    /// - Parameters:
    ///   - keys: Keys to remove (String or [String])
    ///   - completion: Completion callback
    public func remove(
        _ keys: Any,
        completion: ((ChromeStorageError?) -> ())? = nil
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let error = self._remove(keys)
            DispatchQueue.main.async {
                completion?(error)
            }
        }
    }

    /// Clear all items from storage
    /// - Parameter completion: Completion callback
    public func clear(completion: ((ChromeStorageError?) -> ())? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let error = self._clear()
            DispatchQueue.main.async {
                completion?(error)
            }
        }
    }

    /// Get storage usage information
    /// - Parameters:
    ///   - keys: Keys to get usage for (nil = all keys)
    ///   - completion: Completion callback with usage in bytes
    public func getBytesInUse(
        _ keys: Any? = nil,
        completion: @escaping (Int) -> ()
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let usage = self._getBytesInUse(keys)
            DispatchQueue.main.async {
                completion(usage)
            }
        }
    }

    // MARK: - Private Implementation

    private func _get(_ keys: Any?) -> [String: Any] {
        var result: [String: Any] = [:]

        if keys == nil {
            // Get all keys
            let allKeys = getAllStorageKeys()
            for key in allKeys {
                if let value = userDefaults.object(forKey: keyPrefix + key) {
                    result[key] = value
                }
            }
        } else if let singleKey = keys as? String {
            // Get single key
            if let value = userDefaults.object(forKey: keyPrefix + singleKey) {
                result[singleKey] = value
            }
        } else if let keyArray = keys as? [String] {
            // Get multiple keys
            for key in keyArray {
                if let value = userDefaults.object(forKey: keyPrefix + key) {
                    result[key] = value
                }
            }
        } else if let keyDefaults = keys as? [String: Any] {
            // Get keys with default values
            for (key, defaultValue) in keyDefaults {
                let value = userDefaults.object(forKey: keyPrefix + key) ?? defaultValue
                result[key] = value
            }
        }

        logger.debug("📖 Retrieved \(result.count) items from \(self.type.rawValue) storage")
        return result
    }

    private func _set(_ items: [String: Any]) -> ChromeStorageError? {
        // Check quota
        let currentUsage = _getBytesInUse(nil)
        let newDataSize = calculateDataSize(items)

        if currentUsage + newDataSize > quota {
            logger.warning("💾 Storage quota exceeded for \(self.type.rawValue): \(currentUsage + newDataSize) > \(self.quota)")
            return .quotaExceeded
        }

        var changes: [String: ChromeStorageChange] = [:]

        for (key, value) in items {
            let fullKey = keyPrefix + key
            let oldValue = userDefaults.object(forKey: fullKey)

            userDefaults.set(value, forKey: fullKey)

            changes[key] = ChromeStorageChange(
                oldValue: oldValue,
                newValue: value
            )
        }

        userDefaults.synchronize()

        // Notify listeners (would need reference to ChromeStorage instance)
        logger.debug("💾 Stored \(items.count) items in \(self.type.rawValue) storage")

        return nil
    }

    private func _remove(_ keys: Any) -> ChromeStorageError? {
        var keysToRemove: [String] = []

        if let singleKey = keys as? String {
            keysToRemove = [singleKey]
        } else if let keyArray = keys as? [String] {
            keysToRemove = keyArray
        }

        for key in keysToRemove {
            userDefaults.removeObject(forKey: keyPrefix + key)
        }

        userDefaults.synchronize()
        logger.debug("🗑️ Removed \(keysToRemove.count) items from \(self.type.rawValue) storage")

        return nil
    }

    private func _clear() -> ChromeStorageError? {
        let allKeys = getAllStorageKeys()

        for key in allKeys {
            userDefaults.removeObject(forKey: keyPrefix + key)
        }

        userDefaults.synchronize()
        logger.debug("🧹 Cleared all items from \(self.type.rawValue) storage")

        return nil
    }

    private func _getBytesInUse(_ keys: Any?) -> Int {
        let data = _get(keys)
        return calculateDataSize(data)
    }

    private func getAllStorageKeys() -> [String] {
        userDefaults.dictionaryRepresentation().keys.compactMap { key in
            if key.hasPrefix(keyPrefix) {
                return String(key.dropFirst(keyPrefix.count))
            }
            return nil
        }
    }

    private func calculateDataSize(_ data: [String: Any]) -> Int {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            return jsonData.count
        } catch {
            logger.error("❌ Failed to calculate data size: \(error)")
            return 0
        }
    }
}

// MARK: - ChromeStorageType

/// Chrome storage types
public enum ChromeStorageType: String, CaseIterable {
    case local
    case sync
    case session
}

// MARK: - ChromeStorageChange

/// Storage change information
public struct ChromeStorageChange {
    public let oldValue: Any?
    public let newValue: Any?

    public init(oldValue: Any?, newValue: Any?) {
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

// MARK: - ChromeStorageError

/// Chrome storage errors
public enum ChromeStorageError: Error {
    case quotaExceeded
    case invalidKey
    case serializationError
    case unknown(String)

    public var localizedDescription: String {
        switch self {
        case .quotaExceeded:
            "Storage quota exceeded"
        case .invalidKey:
            "Invalid storage key"
        case .serializationError:
            "Failed to serialize data"
        case let .unknown(message):
            "Storage error: \(message)"
        }
    }
}
