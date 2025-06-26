//
//  DefaultWindowConfiguration.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//
import AppKit

// MARK: - DefaultWindowConfiguration

/// Holds default peramaters for window shapes and sizes
public struct DefaultWindowConfiguration {
    // MARK: - Properties

    /// configurations
    public let defaultMinimumSize = CGSize(width: 500, height: 400)
    public let defaultSize = CGSize(width: 1024, height: 768)

    public var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]

    public var contentRect: NSRect {
        NSRect(x: 100, y: 100, width: defaultSize.width, height: defaultSize.height)
    }

    // MARK: - Inititalizer

    public init() {}
}
