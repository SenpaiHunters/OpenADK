//
//  OpenADK.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import Observation
import OpenADKObjC
import SwiftUI

// MARK: - Alto

/// Alto is a singleton that allows for global app data such as tab instances or spaces
@Observable
public class Alto {
    // MARK: - Properties

    public static let shared = Alto()

    /// global data
    public var tabs: [UUID: any TabProtocol] = [:] /// a global array of all the tabs across all windows
    public var spaces: [SpaceProtocol] = [
        Space(localLocations: [
            TabLocation(title: "pinned"),
            TabLocation(title: "unpinned")
        ]),
        Space(localLocations: [
            TabLocation(title: "pinned"),
            TabLocation(title: "unpinned")
        ])
    ] /// a global array of all the tabs across all windows
    public var profiles: String? /// TODO: impliment this

    /// global managers
    public let windowManager: WindowManager
    public let cookieManager: CookiesManager
    public let faviconManager: FaviconManager
    public let downloadManager: String? = nil // TODO: Handle Download

    // MARK: - Initialization

    /// Initilizes all of the global managers
    private init() {
        windowManager = WindowManager()
        cookieManager = CookiesManager()
        faviconManager = FaviconManager()
    }

    // MARK: - Public Methods

    /// Retreives a tab from the global tab storage via id
    /// - Parameter id: The id of the tab
    /// - Returns: A tab conforming to TabProtocol with that matching id or nil
    public func getTab(id: UUID) -> (any TabProtocol)? {
        guard let tab = tabs.first(where: { $0.key == id })?.value else {
            return nil
        }
        return tab
    }
}
