//
//  Space.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import Observation
import SwiftUI

// MARK: - Space

// A default space class for use in the browser
@Observable
public class Space: Identifiable, Equatable {
    // MARK: - Properties

    public let id: UUID = .init()
    public var name: String
    public var index: Int? {
        if let index = Alto.shared.spaces.firstIndex(where: { $0.id == self.id }) {
            return index
        }
        return nil
    }

    public var icon: String?
    public var currentTab: GenaricTab? // maybe make this computed in the future
    public var profile: Profile?
    // TODO: add a theme manager, a designated profile, and search engine

    public var localLocations: [TabLocation]

    // MARK: - Initialization

    /// A default space class for use in the browser
    /// - Parameters:
    ///   - name: the title of the space
    ///   - index: the space's index for ordering
    ///   - icon: the space icon displayed
    ///   - currentTab: the active tab for that space
    ///   - localLocations: Tab locations specific to the space
    init(
        profile: Profile,
        name: String? = nil,
        icon: String? = nil,
        currentTab: GenaricTab? = nil,
        localLocations: [TabLocation]? = nil
    ) {
        self.name = name ?? "Space _"
        self.icon = icon
        self.currentTab = currentTab
        self.localLocations = localLocations ??  [TabLocation()]
        self.profile = profile
    }

    public static func == (lhs: Space, rhs: Space) -> Bool {
        lhs.id == rhs.id
    }
}
