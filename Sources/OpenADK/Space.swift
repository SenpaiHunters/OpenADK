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
public class Space: SpaceProtocol, Identifiable, Equatable {
    // MARK: - Properties

    public let id: UUID = .init()
    public var title: String
    public var index: Int? {
        if let index = Alto.shared.spaces.firstIndex(where: { $0.id == self.id }) {
            return index
        }
        return nil
    }

    public var icon: String?
    public var currentTab: (any TabProtocol)? // maybe make this computed in the future
    /// TODO: add a theme manager, a designated profile, and search engine

    public var localLocations: [TabLocation]

    // MARK: - Initialization

    /// A default space class for use in the browser
    /// - Parameters:
    ///   - title: the title of the space
    ///   - index: the space's index for ordering
    ///   - icon: the space icon displayed
    ///   - currentTab: the active tab for that space
    ///   - localLocations: Tab locations specific to the space
    init(
        title: String = "Space",
        icon: String? = nil,
        currentTab: (any TabProtocol)? = nil,
        localLocations: [TabLocation] = [TabLocation()]
    ) {
        self.title = title
        self.icon = icon
        self.currentTab = currentTab
        self.localLocations = localLocations
    }

    public static func == (lhs: Space, rhs: Space) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - SpaceProtocol

// If the user wants to add things to spaces they can use the tab protocol
public protocol SpaceProtocol: Identifiable, Equatable {
    var id: UUID { get }
    var index: Int? { get }
    var title: String { get set }
    var icon: String? { get set }
    var currentTab: (any TabProtocol)? { get set }

    var localLocations: [TabLocation] { get set }
}
