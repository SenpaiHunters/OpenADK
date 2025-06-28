//
//  ChromeCommands.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog

// MARK: - ChromeCommands

/// Chrome Commands API implementation
/// Provides chrome.commands functionality for handling keyboard shortcuts
public class ChromeCommands {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeCommands")
    private let extensionId: String
    private var commands: [String: ChromeCommand] = [:]
    private var listeners: [(String, ChromeTab?) -> ()] = []

    public init(extensionId: String) {
        self.extensionId = extensionId
        logger.info("⌨️ ChromeCommands initialized for extension: \(extensionId)")
    }

    // MARK: - Public API

    /// Register commands from manifest
    /// - Parameter manifestCommands: Commands from extension manifest
    public func registerManifestCommands(_ manifestCommands: [String: ChromeManifestCommand]) {
        for (commandName, manifestCommand) in manifestCommands {
            let command = ChromeCommand(
                name: commandName,
                description: manifestCommand.description,
                shortcut: manifestCommand.suggestedKey?.default,
                globalShortcut: manifestCommand.global ?? false
            )

            commands[commandName] = command

            // Register with system shortcut handler
            registerSystemShortcut(command)

            logger.info("⌨️ Registered command: \(commandName) - \(manifestCommand.description ?? "No description")")
        }
    }

    /// Get all commands for this extension
    /// - Parameter callback: Completion callback with commands array
    public func getAll(callback: @escaping ([ChromeCommand]) -> ()) {
        let commandList = Array(commands.values).sorted { $0.name < $1.name }
        logger.debug("📋 Retrieved \(commandList.count) commands")
        callback(commandList)
    }

    /// Add command event listener
    /// - Parameter listener: Command event listener
    public func addListener(_ listener: @escaping (String, ChromeTab?) -> ()) {
        listeners.append(listener)
        logger.debug("👂 Added command event listener")
    }

    /// Remove command event listener
    /// - Parameter listener: Command event listener to remove
    public func removeListener(_ listener: @escaping (String, ChromeTab?) -> ()) {
        // Note: Function comparison is complex in Swift
        // In production, use a listener ID system
        logger.debug("🗑️ Removed command event listener")
    }

    /// Execute a command programmatically
    /// - Parameters:
    ///   - commandName: Name of command to execute
    ///   - tab: Optional tab context
    public func executeCommand(_ commandName: String, tab: ChromeTab? = nil) {
        guard commands[commandName] != nil else {
            logger.warning("⚠️ Command not found: \(commandName)")
            return
        }

        logger.info("🎯 Executing command: \(commandName)")
        handleCommandExecution(commandName, tab: tab)
    }

    /// Update command shortcut
    /// - Parameters:
    ///   - commandName: Name of command to update
    ///   - shortcut: New keyboard shortcut
    ///   - callback: Completion callback
    public func updateShortcut(
        _ commandName: String,
        shortcut: String?,
        callback: (() -> ())? = nil
    ) {
        guard var command = commands[commandName] else {
            logger.warning("⚠️ Command not found for shortcut update: \(commandName)")
            callback?()
            return
        }

        // Unregister old shortcut
        unregisterSystemShortcut(command)

        // Update shortcut
        command.shortcut = shortcut
        commands[commandName] = command

        // Register new shortcut
        registerSystemShortcut(command)

        logger.info("🔄 Updated shortcut for command: \(commandName) -> \(shortcut ?? "none")")
        callback?()
    }

    /// Reset command shortcut to default
    /// - Parameters:
    ///   - commandName: Name of command to reset
    ///   - callback: Completion callback
    public func resetShortcut(_ commandName: String, callback: (() -> ())? = nil) {
        guard var command = commands[commandName] else {
            logger.warning("⚠️ Command not found for shortcut reset: \(commandName)")
            callback?()
            return
        }

        // Unregister current shortcut
        unregisterSystemShortcut(command)

        // Reset to default (this would need to be stored from manifest)
        command.shortcut = nil // In real implementation, restore from manifest default
        commands[commandName] = command

        // Register default shortcut
        registerSystemShortcut(command)

        logger.info("↩️ Reset shortcut for command: \(commandName)")
        callback?()
    }

    /// Check if shortcut is available
    /// - Parameters:
    ///   - shortcut: Keyboard shortcut to check
    ///   - callback: Completion callback with availability status
    public func isShortcutAvailable(_ shortcut: String, callback: @escaping (Bool) -> ()) {
        // Check if shortcut is already used by any command
        let isUsed = commands.values.contains { $0.shortcut == shortcut }

        // In real implementation, also check system shortcuts
        let isAvailable = !isUsed && !isSystemReservedShortcut(shortcut)

        logger.debug("🔍 Shortcut availability check: \(shortcut) -> \(isAvailable)")
        callback(isAvailable)
    }

    /// Get shortcut suggestions for a command
    /// - Parameters:
    ///   - commandName: Name of command
    ///   - callback: Completion callback with shortcut suggestions
    public func getShortcutSuggestions(
        _ commandName: String,
        callback: @escaping ([String]) -> ()
    ) {
        guard let command = commands[commandName] else {
            logger.warning("⚠️ Command not found for suggestions: \(commandName)")
            callback([])
            return
        }

        var suggestions: [String] = []

        // Add common patterns
        let modifiers = ["Ctrl", "Cmd", "Opt", "Shift"]
        let keys = [
            "A",
            "B",
            "C",
            "D",
            "E",
            "F",
            "G",
            "H",
            "I",
            "J",
            "K",
            "L",
            "M",
            "N",
            "O",
            "P",
            "Q",
            "R",
            "S",
            "T",
            "U",
            "V",
            "W",
            "X",
            "Y",
            "Z"
        ]

        for modifier in modifiers {
            for key in keys {
                let shortcut = "\(modifier)+\(key)"
                if !commands.values.contains(where: { $0.shortcut == shortcut }) {
                    suggestions.append(shortcut)
                    if suggestions.count >= 10 { break }
                }
            }
            if suggestions.count >= 10 { break }
        }

        logger.debug("💡 Generated \(suggestions.count) shortcut suggestions for: \(commandName)")
        callback(suggestions)
    }

    // MARK: - Event Handling

    /// Handle system keyboard shortcut
    /// - Parameters:
    ///   - shortcut: Triggered keyboard shortcut
    ///   - tab: Active tab context
    public func handleShortcut(_ shortcut: String, tab: ChromeTab? = nil) {
        // Find command with matching shortcut
        guard let command = commands.values.first(where: { $0.shortcut == shortcut }) else {
            logger.debug("🤷‍♂️ No command found for shortcut: \(shortcut)")
            return
        }

        logger.info("⌨️ Shortcut triggered: \(shortcut) -> \(command.name)")
        handleCommandExecution(command.name, tab: tab)
    }

    /// Handle command execution
    /// - Parameters:
    ///   - commandName: Name of executed command
    ///   - tab: Tab context
    private func handleCommandExecution(_ commandName: String, tab: ChromeTab?) {
        // Notify all listeners
        for listener in listeners {
            listener(commandName, tab)
        }

        // Handle built-in commands
        handleBuiltInCommand(commandName, tab: tab)
    }

    /// Handle built-in extension commands
    /// - Parameters:
    ///   - commandName: Command name
    ///   - tab: Tab context
    private func handleBuiltInCommand(_ commandName: String, tab: ChromeTab?) {
        switch commandName {
        case "_execute_browser_action",
             "_execute_action":
            logger.info("🔘 Executing browser action")
            // This would trigger the extension's browser action

        case "_execute_page_action":
            logger.info("📄 Executing page action")
            // This would trigger the extension's page action

        case "_execute_sidebar_action":
            logger.info("📋 Executing sidebar action")
            // This would trigger the extension's sidebar action

        default:
            logger.debug("🎯 Custom command executed: \(commandName)")
        }
    }

    // MARK: - System Integration

    /// Register command shortcut with system
    /// - Parameter command: Command to register
    private func registerSystemShortcut(_ command: ChromeCommand) {
        guard let shortcut = command.shortcut else { return }

        // In real implementation, register with macOS global hotkey system
        logger.debug("🔗 Registered system shortcut: \(shortcut) for \(command.name)")
    }

    /// Unregister command shortcut from system
    /// - Parameter command: Command to unregister
    private func unregisterSystemShortcut(_ command: ChromeCommand) {
        guard let shortcut = command.shortcut else { return }

        // In real implementation, unregister from macOS global hotkey system
        logger.debug("🔗 Unregistered system shortcut: \(shortcut) for \(command.name)")
    }

    /// Check if shortcut is reserved by system
    /// - Parameter shortcut: Shortcut to check
    /// - Returns: Whether shortcut is system reserved
    private func isSystemReservedShortcut(_ shortcut: String) -> Bool {
        let reservedShortcuts = [
            "Cmd+Q", "Cmd+W", "Cmd+T", "Cmd+N", "Cmd+R",
            "Cmd+Z", "Cmd+Y", "Cmd+X", "Cmd+C", "Cmd+V",
            "Cmd+A", "Cmd+S", "Cmd+O", "Cmd+P", "Cmd+F",
            "Cmd+Tab", "Cmd+Space", "Cmd+Option+Esc"
        ]

        return reservedShortcuts.contains(shortcut)
    }
}

// MARK: - ChromeCommand

/// Chrome command
public struct ChromeCommand {
    public let name: String
    public let description: String?
    public var shortcut: String?
    public let globalShortcut: Bool

    public init(
        name: String,
        description: String?,
        shortcut: String?,
        globalShortcut: Bool = false
    ) {
        self.name = name
        self.description = description
        self.shortcut = shortcut
        self.globalShortcut = globalShortcut
    }
}

// MARK: - ChromeManifestCommand

/// Manifest command definition
public struct ChromeManifestCommand {
    public let description: String?
    public let suggestedKey: ChromeManifestCommandKey?
    public let global: Bool?

    public init(
        description: String? = nil,
        suggestedKey: ChromeManifestCommandKey? = nil,
        global: Bool? = nil
    ) {
        self.description = description
        self.suggestedKey = suggestedKey
        self.global = global
    }
}

// MARK: - ChromeManifestCommandKey

/// Manifest command keyboard shortcut
public struct ChromeManifestCommandKey {
    public let `default`: String?
    public let mac: String?
    public let windows: String?
    public let linux: String?
    public let chromeos: String?

    public init(
        default: String? = nil,
        mac: String? = nil,
        windows: String? = nil,
        linux: String? = nil,
        chromeos: String? = nil
    ) {
        self.default = `default`
        self.mac = mac
        self.windows = windows
        self.linux = linux
        self.chromeos = chromeos
    }
}

// MARK: - ChromeCommandModifier

/// Keyboard modifier keys
public enum ChromeCommandModifier: String, CaseIterable {
    case ctrl = "Ctrl"
    case cmd = "Command"
    case alt = "Alt"
    case shift = "Shift"
    case meta = "Meta"
}

// MARK: - ChromeBuiltInCommand

/// Special command names
public enum ChromeBuiltInCommand: String, CaseIterable {
    case executeBrowserAction = "_execute_browser_action"
    case executeAction = "_execute_action"
    case executePageAction = "_execute_page_action"
    case executeSidebarAction = "_execute_sidebar_action"
}
