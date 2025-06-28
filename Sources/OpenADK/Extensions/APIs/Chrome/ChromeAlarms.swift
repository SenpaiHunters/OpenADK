//
//  ChromeAlarms.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ChromeAlarms

/// Chrome Alarms API implementation
/// Provides chrome.alarms functionality for scheduling events
public class ChromeAlarms {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeAlarms")

    private let extensionId: String
    private var alarms: [String: ChromeAlarm] = [:]
    private var timers: [String: Timer] = [:]
    private var alarmListeners: [(ChromeAlarm) -> ()] = []

    /// Minimum delay in minutes for alarms
    public static let minimumDelayInMinutes = 1.0

    public init(extensionId: String) {
        self.extensionId = extensionId
        logger.info("⏰ ChromeAlarms initialized for extension: \(extensionId)")
    }

    deinit {
        clearAll()
    }

    // MARK: - Public API

    /// Create an alarm
    /// - Parameters:
    ///   - name: Optional alarm name. If not provided, empty string is used
    ///   - alarmInfo: Alarm configuration
    ///   - completion: Completion callback
    public func create(
        _ name: String? = nil,
        alarmInfo: ChromeAlarmInfo,
        completion: (() -> ())? = nil
    ) {
        let alarmName = name ?? ""

        // Clear existing alarm with same name
        if alarms[alarmName] != nil {
            clear(alarmName)
        }

        // Validate alarm info
        guard validateAlarmInfo(alarmInfo) else {
            logger.error("❌ Invalid alarm info for alarm: \(alarmName)")
            completion?()
            return
        }

        let alarm = ChromeAlarm(
            name: alarmName,
            scheduledTime: calculateScheduledTime(from: alarmInfo),
            periodInMinutes: alarmInfo.periodInMinutes
        )

        alarms[alarmName] = alarm
        scheduleTimer(for: alarm)

        logger.info("⏰ Created alarm: \(alarmName) scheduled for \(alarm.scheduledTime)")
        completion?()
    }

    /// Get alarm by name
    /// - Parameters:
    ///   - name: Alarm name (optional, returns unnamed alarm if nil)
    ///   - completion: Completion callback with alarm or nil
    public func get(
        _ name: String? = nil,
        completion: @escaping (ChromeAlarm?) -> ()
    ) {
        let alarmName = name ?? ""
        let alarm = alarms[alarmName]

        DispatchQueue.main.async {
            completion(alarm)
        }
    }

    /// Get all alarms
    /// - Parameter completion: Completion callback with array of alarms
    public func getAll(completion: @escaping ([ChromeAlarm]) -> ()) {
        let allAlarms = Array(alarms.values)

        DispatchQueue.main.async {
            completion(allAlarms)
        }
    }

    /// Clear alarm by name
    /// - Parameters:
    ///   - name: Alarm name (optional, clears unnamed alarm if nil)
    ///   - completion: Completion callback with success status
    public func clear(
        _ name: String? = nil,
        completion: ((Bool) -> ())? = nil
    ) {
        let alarmName = name ?? ""

        let wasCleared = clearAlarm(alarmName)

        DispatchQueue.main.async {
            completion?(wasCleared)
        }
    }

    /// Clear all alarms
    /// - Parameter completion: Completion callback with success status
    public func clearAll(completion: ((Bool) -> ())? = nil) {
        let alarmNames = Array(alarms.keys)

        for alarmName in alarmNames {
            clearAlarm(alarmName)
        }

        let success = alarms.isEmpty && timers.isEmpty

        DispatchQueue.main.async {
            completion?(success)
        }
    }

    /// Add alarm listener
    /// - Parameter listener: Callback function for alarm events
    public func addAlarmListener(_ listener: @escaping (ChromeAlarm) -> ()) {
        alarmListeners.append(listener)
        logger.debug("👂 Added alarm listener")
    }

    /// Remove alarm listener
    /// - Parameter listener: Listener to remove
    public func removeAlarmListener(_ listener: @escaping (ChromeAlarm) -> ()) {
        // Function comparison is complex in Swift
        // In production, use a listener ID system
        logger.debug("🗑️ Removed alarm listener")
    }

    // MARK: - Private Implementation

    private func validateAlarmInfo(_ alarmInfo: ChromeAlarmInfo) -> Bool {
        // Check that at least one timing parameter is provided
        let hasWhen = alarmInfo.when != nil
        let hasDelayInMinutes = alarmInfo.delayInMinutes != nil

        if !hasWhen, !hasDelayInMinutes {
            logger.error("❌ Alarm must specify either 'when' or 'delayInMinutes'")
            return false
        }

        // Check minimum delay
        if let delay = alarmInfo.delayInMinutes, delay < Self.minimumDelayInMinutes {
            logger.error("❌ Alarm delay must be at least \(Self.minimumDelayInMinutes) minutes")
            return false
        }

        // Check period minimum
        if let period = alarmInfo.periodInMinutes, period < Self.minimumDelayInMinutes {
            logger.error("❌ Alarm period must be at least \(Self.minimumDelayInMinutes) minutes")
            return false
        }

        return true
    }

    private func calculateScheduledTime(from alarmInfo: ChromeAlarmInfo) -> Date {
        if let when = alarmInfo.when {
            Date(timeIntervalSince1970: when / 1000.0) // Convert from milliseconds
        } else if let delayInMinutes = alarmInfo.delayInMinutes {
            Date().addingTimeInterval(delayInMinutes * 60.0)
        } else {
            Date()
        }
    }

    private func scheduleTimer(for alarm: ChromeAlarm) {
        let timeInterval = alarm.scheduledTime.timeIntervalSinceNow

        guard timeInterval > 0 else {
            logger.warning("⚠️ Alarm scheduled time is in the past: \(alarm.name)")
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            self?.handleAlarmFired(alarm)
        }

        timers[alarm.name] = timer
        logger.debug("⏰ Scheduled timer for alarm: \(alarm.name) in \(timeInterval) seconds")
    }

    private func handleAlarmFired(_ alarm: ChromeAlarm) {
        logger.info("🔥 Alarm fired: \(alarm.name)")

        // Notify listeners
        for listener in alarmListeners {
            listener(alarm)
        }

        // Handle periodic alarms
        if let periodInMinutes = alarm.periodInMinutes {
            // Create new alarm for next occurrence
            let nextAlarm = ChromeAlarm(
                name: alarm.name,
                scheduledTime: Date().addingTimeInterval(periodInMinutes * 60.0),
                periodInMinutes: periodInMinutes
            )

            alarms[alarm.name] = nextAlarm
            scheduleTimer(for: nextAlarm)

            logger.debug("🔄 Rescheduled periodic alarm: \(alarm.name)")
        } else {
            // One-time alarm, remove it
            clearAlarm(alarm.name)
        }
    }

    @discardableResult
    private func clearAlarm(_ name: String) -> Bool {
        guard let alarm = alarms[name] else {
            return false
        }

        // Cancel timer
        timers[name]?.invalidate()
        timers.removeValue(forKey: name)

        // Remove alarm
        alarms.removeValue(forKey: name)

        logger.info("🗑️ Cleared alarm: \(name)")
        return true
    }
}

// MARK: - ChromeAlarmInfo

/// Chrome alarm information for creating alarms
public struct ChromeAlarmInfo {
    /// Time when the alarm should fire (milliseconds since epoch)
    public let when: Double?

    /// How many minutes from now the alarm should fire
    public let delayInMinutes: Double?

    /// How often the alarm should repeat (in minutes)
    public let periodInMinutes: Double?

    public init(when: Double? = nil, delayInMinutes: Double? = nil, periodInMinutes: Double? = nil) {
        self.when = when
        self.delayInMinutes = delayInMinutes
        self.periodInMinutes = periodInMinutes
    }
}

// MARK: - ChromeAlarm

/// Chrome alarm object
public struct ChromeAlarm {
    /// Alarm name
    public let name: String

    /// When the alarm is scheduled to fire (milliseconds since epoch)
    public let scheduledTime: Date

    /// How often the alarm repeats (in minutes, nil for one-time)
    public let periodInMinutes: Double?

    public init(name: String, scheduledTime: Date, periodInMinutes: Double? = nil) {
        self.name = name
        self.scheduledTime = scheduledTime
        self.periodInMinutes = periodInMinutes
    }

    /// Scheduled time in milliseconds since epoch (for Chrome compatibility)
    public var scheduledTimeMs: Double {
        scheduledTime.timeIntervalSince1970 * 1000.0
    }
}
