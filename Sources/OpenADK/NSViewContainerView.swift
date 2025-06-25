//
//  NSViewContainerView.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit
import Foundation

// MARK: - NSViewContainerView

/// A NSView which simply adds some view to its view hierarchy
public class NSViewContainerView<ContentView: NSView>: NSView {
    public var contentView: ContentView? {
        didSet {
            guard oldValue !== contentView, let contentView else { return }
            insertNewContentView(contentView, oldValue: oldValue)
        }
    }

    public init(contentView: ContentView?) {
        self.contentView = contentView
        super.init(frame: NSRect())
        if let contentView {
            insertNewContentView(contentView, oldValue: nil)
        }
    }

    public convenience init() {
        self.init(contentView: nil)
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func insertNewContentView(_ contentView: ContentView, oldValue: ContentView?) {
        contentView.autoresizingMask = [.width, .height]
        contentView.frame = bounds
        if let oldValue {
            replaceSubview(oldValue, with: contentView)
        } else {
            addSubview(contentView)
        }
    }
}
