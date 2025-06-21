//
//  TabLocation.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit
import Observation

// MARK: - TabLocation

@Observable
public class TabLocation: TabLocationProtocol {
    public var title: String?
    public var id = UUID()
    public var tabs: [TabRepresentation] = []

    init(title: String? = nil) {
        self.title = title ?? id.uuidString
    }

    public func appendTabRep(_ tabRep: TabRepresentation) {
        tabs.append(tabRep)
        let tab = Alto.shared.getTab(id: tabRep.id)
        tab?.location = self
    }

    public func removeTab(id: UUID) {
        tabs.removeAll(where: { $0.id == id })
    }
}

// MARK: - TabLocationProtocol

public protocol TabLocationProtocol {
    var title: String? { get set }
    var id: UUID { get }
    var tabs: [TabRepresentation] { get set }

    func appendTabRep(_ tabRep: TabRepresentation)

    func removeTab(id: UUID)
}
