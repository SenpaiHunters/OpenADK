//
//  NSWebView.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import OpenADKObjC
import SwiftUI

// MARK: - WebViewContainer

/// Allows the webview to be displayed in swiftUI
/// The content view needs to be wrapped in another container to avoid glitching issues and frame resets due to full
/// screan
public struct WebViewContainer: View, NSViewRepresentable {
    public typealias ContentView = NSViewContainerView<AltoWebView>
    public typealias NSViewType = NSViewContainerView<ContentView>

    let contentView: NSViewContainerView<AltoWebView>
    let topContentInset: CGFloat

    /// Allows the webview to be displayed in swiftUI
    /// - Parameters:
    ///   - contentView: A NSViewContainerView holding a webview
    ///   - topContentInset: the inset of the content from the top of the window
    public init(contentView: NSViewContainerView<AltoWebView>, topContentInset: CGFloat) {
        self.contentView = contentView
        self.topContentInset = topContentInset
    }

    public func makeNSView(context _: Context) -> NSViewType {
        NSViewType()
    }

    public func updateNSView(_ nsView: NSViewContainerView<ContentView>, context _: Context) {
        nsView.contentView = contentView
    }
}
