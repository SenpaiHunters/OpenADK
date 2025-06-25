//
//  PreferencesManager.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import Combine
import Observation
import SwiftUI

// MARK: - PreferencesManager

@Observable
public final class PreferencesManager {
    public static let shared = PreferencesManager()

    // Use instance variable instead of static
    @UserDefault(key: "colorScheme", defaultValue: "dark")
    @ObservationIgnored public var storedColorScheme: String

    @UserDefault(key: "searchEngine", defaultValue: "brave")
    @ObservationIgnored public var storedSearchEngine: String

    @UserDefault(key: "sidebarPosition", defaultValue: "top")
    @ObservationIgnored public var storedSidebarPosition: String

    @UserDefault(key: "downloadPath", defaultValue: "")
    @ObservationIgnored public var storedDownloadPath: String

    /// Publicly available and observed version of Preferences
    public var colorScheme: ColorScheme?
    public var searchEngine: SearchEngine
    public var sidebarPosition: SidebarPosition
    public var downloadPath: URL

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Initialize with default values first
        colorScheme = nil
        searchEngine = .google
        sidebarPosition = .top
        downloadPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!

        // Then update with actual stored values
        colorScheme = Self.getScheme(from: storedColorScheme)
        searchEngine = Self.getSearchEngine(string: storedSearchEngine)
        sidebarPosition = Self.getSidebarPosition(from: storedSidebarPosition)
        downloadPath = Self.getDownloadPath(from: storedDownloadPath)

        // Now set up the observers
        $storedColorScheme.sink { [weak self] newValue in
            self?.colorScheme = Self.getScheme(from: newValue)
        }
        .store(in: &cancellables)

        $storedSearchEngine.sink { [weak self] newValue in
            self?.searchEngine = Self.getSearchEngine(string: newValue)
        }
        .store(in: &cancellables)

        $storedSidebarPosition.sink { [weak self] newValue in
            self?.sidebarPosition = Self.getSidebarPosition(from: newValue)
        }
        .store(in: &cancellables)

        $storedDownloadPath.sink { [weak self] newValue in
            self?.downloadPath = Self.getDownloadPath(from: newValue)
        }
        .store(in: &cancellables)
    }

    // Make these static methods so they can be called during initialization
    public static func getScheme(from string: String) -> ColorScheme? {
        switch string {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    public static func getSearchEngine(string: String) -> SearchEngine {
        switch string {
        case "google": .google
        case "duckduckgo": .duckduckgo
        case "brave": .brave
        case "bing": .bing
        case "yahoo": .yahoo
        case "startpage": .startpage
        case "searx": .searx
        case "none": .none
        default: .google
        }
    }

    public static func getSidebarPosition(from string: String) -> SidebarPosition {
        switch string {
        case "left": .left
        case "right": .right
        case "top": .top
        default: .top
        }
    }

    public static func getDownloadPath(from string: String) -> URL {
        if string.isEmpty {
            // Default to Downloads folder
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        } else {
            // Use stored path, with fallback to Downloads if invalid
            let url = URL(fileURLWithPath: string)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            } else {
                return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            }
        }
    }

    // Method to update search engine and persist it
    public func setSearchEngine(_ engine: SearchEngine) {
        searchEngine = engine
        storedSearchEngine = engine.rawValue
    }

    // Method to update sidebar position and persist it
    public func setSidebarPosition(_ position: SidebarPosition) {
        sidebarPosition = position
        storedSidebarPosition = position.rawValue
    }

    // Method to update color scheme and persist it
    public func setColorScheme(_ scheme: ColorScheme?) {
        colorScheme = scheme
        storedColorScheme = scheme?.stringValue ?? "system"
    }

    // Method to update download path and persist it
    public func setDownloadPath(_ path: URL) {
        downloadPath = path
        storedDownloadPath = path.path
    }
}

// MARK: - SidebarPosition

public enum SidebarPosition: String, CaseIterable {
    case top
    case left
    case right
}

// MARK: - ColorScheme Extension

public extension ColorScheme {
    var stringValue: String {
        switch self {
        case .dark: return "dark"
        case .light: return "light"
        @unknown default: return "system"
        }
    }
}
