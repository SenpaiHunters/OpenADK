//
//  DefaultWindowConfiguration.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit
import SwiftUI

// MARK: - DefaultWindowConfiguration

/// Lets us set the default sizing and positioning of a window
public struct DefaultWindowConfiguration {
    // MARK: - Properties

    /// Factories to buil the view and state for each new window
    public var viewFactory: ((GenaricState) -> (NSView & BrowserView))?
    public var stateFactory: () -> GenaricState = { GenaricState() }

    /// configurations
    public let defaultMinimumSize = CGSize(width: 500, height: 400)
    public let defaultSize = CGSize(width: 1024, height: 768)
    public var windowRec: NSRect {
        NSRect(x: defaultPoint.x, y: defaultPoint.y, width: defaultSize.width, height: defaultSize.height)
    }

    public var defaultPoint: CGPoint {
        if let screen = NSScreen.main {
            let rect = screen.frame
            let height = rect.size.height
            let width = rect.size.width

            return CGPoint(x: height / 2, y: width / 2)
        }
        return CGPoint(x: 0, y: 0)
    }

    // MARK: - Inititalizer

    public init() {}

    // MARK: - Public Methods

    /// Note to devs: the functions must be marked with mutating in order to change the value of the struct

    /// Handles swiftUI Views
    public mutating func setView(_ viewBuilder: @escaping ((GenaricState) -> some View)) {
        viewFactory = { state in
            HostingBrowserView(rootView: viewBuilder(state), state: state)
        }
    }

    /// Handles AppKit Views
    public mutating func setView(_ viewBuilder: @escaping ((GenaricState) -> (NSView & BrowserView))) {
        viewFactory = viewBuilder
    }
}
