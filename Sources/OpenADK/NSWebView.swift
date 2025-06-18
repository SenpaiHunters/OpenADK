//

import SwiftUI
import OpenADKObjC

/// Allows the Appkit native WKWebView to be used in SwiftUI
public struct NSWebView: NSViewRepresentable {
    public var webView: (any webViewProtocol)?

    public init(webView: (any webViewProtocol)? = nil) {
        self.webView = webView
    }

    public func makeNSView(context _: Context) -> NSView {
        let VisualEffect = NSVisualEffectView()
        VisualEffect.material = .fullScreenUI
        VisualEffect.state = .active
        VisualEffect.blendingMode = .behindWindow

        if let concreteView = webView {
            return concreteView
        } else {
            return VisualEffect
        }
    }

    public func updateNSView(_ nsView: NSViewType, context _: Context) {


    }
}


public struct WebViewContainer: View, NSViewRepresentable {
    public typealias ContentView = NSViewContainerView<AltoWebView>
    public typealias NSViewType = NSViewContainerView<ContentView>

    let contentView: NSViewContainerView<AltoWebView>
    let topContentInset: CGFloat
    
    public init(contentView: NSViewContainerView<AltoWebView>, topContentInset: CGFloat) {
        self.contentView = contentView
        self.topContentInset = topContentInset
    }
    
    public func makeNSView(context: Context) -> NSViewType {
        return NSViewType()
    }

    public func updateNSView(_ nsView: NSViewContainerView<ContentView>, context: Context) {
        nsView.contentView = contentView
    }
}


import Foundation
import AppKit

/// A NSView which simply adds some view to its view hierarchy
public class NSViewContainerView<ContentView: NSView>: NSView {
    public var contentView: ContentView? {
        didSet {
            guard oldValue !== contentView, let contentView = contentView else { return }
            insertNewContentView(contentView, oldValue: oldValue)
        }
    }

    public init(contentView: ContentView?) {
        self.contentView = contentView
        super.init(frame: NSRect())
        if let contentView = contentView {
            self.insertNewContentView(contentView, oldValue: nil)
        }
    }

    public convenience init() {
        self.init(contentView: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func insertNewContentView(_ contentView: ContentView, oldValue: ContentView?) {
        contentView.autoresizingMask = [.width, .height]
        contentView.frame = bounds
        if let oldValue = oldValue {
            replaceSubview(oldValue, with: contentView)
        } else {
            addSubview(contentView)
        }
    }
}
