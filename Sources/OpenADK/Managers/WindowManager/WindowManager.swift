//
//  WindowManager.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit
import SwiftUI

// MARK: - WindowManager

/// Handles creating Browser Windows
public final class WindowManager {
    // MARK: - Properties

    public var configuration: DefaultWindowConfiguration

    public var windows: [AltoWindow] = []

    // MARK: - Initialization

    /// sets up the Default Config if not provided
    init(configuration: DefaultWindowConfiguration = DefaultWindowConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - Public Methods

    /// Creates a window with designated content
    @discardableResult
    public func createWindow(tabs _: [GenaricTab]) -> AltoWindow? {
        guard let viewFactory = configuration.viewFactory else {
            print("Error: viewFactory not set in DefaultWindowConfiguration.")
            return nil
        }

        let newState = configuration.stateFactory()

        let contentView = viewFactory(newState)

        let window = AltoWindow(
            contentRect: configuration.windowRec,
            contentView: contentView,
            state: newState,
            minimumSize: configuration.defaultMinimumSize
        )

        windows.append(window)
        window.orderFront(nil)
        return window
    }

    /// A more flexible window creation method for Mini Alto
    @discardableResult
    public func createWindow(
        contentRect: NSRect,
        contentView: NSView,
        state: GenaricState
    ) -> AltoWindow? {
        let newState = configuration.stateFactory()

        let window = AltoWindow(
            contentRect: configuration.windowRec,
            contentView: contentView,
            state: newState,
            minimumSize: configuration.defaultMinimumSize
        )

        windows.append(window)
        window.orderFront(nil)
        return window
    }
}
