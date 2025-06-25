//
//  AltoWindow.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit

// MARK: - AltoWindow

/// A modified version of the NSWindow class
public class AltoWindow: NSWindow {
    // MARK: - Properties

    public var id = UUID()
    private var state: GenaricState
    public var showWinowButtons = false

    // MARK: - Initiation

    /// A modified version of the NSWindow class
    /// - Parameters:
    ///   - contentRect: The sizing and positioning of the window
    ///   - contentView: The content to display
    ///   - state: A State to manage the view of the window
    public init(
        contentRect: NSRect,
        contentView: NSView,
        state: GenaricState,
        minimumSize: CGSize? = nil
    ) {
        self.state = state

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        /// Window Configurations
        toolbar?.isVisible = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        isMovable = false

        /// Removes the window buttons
        if !showWinowButtons {
            standardWindowButton(NSWindow.ButtonType.closeButton)?.isHidden = true
            standardWindowButton(NSWindow.ButtonType.zoomButton)?.isHidden = true
            standardWindowButton(NSWindow.ButtonType.miniaturizeButton)?.isHidden = true
        }

        let windowTitle = state.currentSpace?.currentTab?.activeContent?.title ?? state.currentSpace?.name
        title = windowTitle ?? "Untitiled"
        self.state.window = self
        self.contentView = contentView
    }

    func getTitle() -> String {
        state.currentContent?[0].title ?? ""
    }
}

// MARK: - BrowserView

public protocol BrowserView {
    var state: GenaricState { get set }
}
