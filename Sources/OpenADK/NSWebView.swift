//

import SwiftUI

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

    public func updateNSView(_: NSViewType, context _: Context) {}
}
