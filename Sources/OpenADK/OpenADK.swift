//

//
//  OpenADK.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import Observation
import OpenADKObjC
import SwiftUI

// MARK: - ADKData

/// Alto is a singleton that allows for global app data such as tab instances or spaces
@Observable
open class ADKData: ADKDataProtocol {
    public static let shared = ADKData()

    // MARK: - Properties

    // Global shared data across browser windows
    public var tabs: [UUID: ADKTab] = [:]

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Retreives a tab from the global tab storage via id
    /// - Parameter id: The id of the tab
    /// - Returns: A tab conforming to TabProtocol with that matching id or nil
    public func getTab(id: UUID) -> ADKTab? {
        guard let tab = tabs.first(where: { $0.key == id })?.value else {
            return nil
        }
        return tab
    }
}

// MARK: - ADKDataProtocol

public protocol ADKDataProtocol {
    var tabs: [UUID: ADKTab] { get }

    func getTab(id: UUID) -> ADKTab?
}
