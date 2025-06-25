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

    // Global shared data across browser windows
    public var tabs: [UUID: GenaricTab] = [:]
    public var spaces: [Space] = []

    // Global managers
    public let windowManager: WindowManager
    public let cookieManager: CookiesManager
    public let faviconManager: FaviconManager
    public let profileManager: ProfileManager
    public let spaceManager: SpaceManager

    // MARK: - Initialization

    private init() {
        // Set up managers
        windowManager = WindowManager()
        cookieManager = CookiesManager()
        faviconManager = FaviconManager()
        profileManager = ProfileManager()
        spaceManager = SpaceManager()

        profileManager.createNewProfile(name: "test")

        let test = profileManager.getProfile(name: "test")
        if test != nil {
            print("test found")
        } else {
            print("Test not found")
        }
        // Set up spaces
        let defaultProfile = profileManager.defaultProfile
        spaces = [
            Space(profile: defaultProfile, name: "Latent Space", localLocations: [
                TabLocation(title: "pinned"),
                TabLocation(title: "unpinned")
            ]),
            Space(profile: test ?? defaultProfile, name: "The Final Frontier", localLocations: [
                TabLocation(title: "pinned"),
                TabLocation(title: "unpinned")
            ])
        ]
    }

    // MARK: - Public Methods

    /// Retreives a tab from the global tab storage via id
    /// - Parameter id: The id of the tab
    /// - Returns: A tab conforming to TabProtocol with that matching id or nil
    public func getTab(id: UUID) -> GenaricTab? {
        guard let tab = tabs.first(where: { $0.key == id })?.value else {
            return nil
        }
        return tab
    }
}
