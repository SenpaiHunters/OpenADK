//
import AppKit
import SwiftUI

/// Lets us set the default sizing and positioning of a window
public struct DefaultWindowConfiguration {
    public let defaultMinimumSize = CGSize(width: 500, height: 400)
    public let defaultSize = CGSize(width: 1024, height: 768)

    public var viewFactory: ((any StateProtocol) -> (NSView & BrowserView))?

    public var stateFactory: () -> any StateProtocol = { AltoState() }

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

    public init() {}

    /// Note to devs: the functions must be marked with mutating in order to change the value of the struct

    /// Handles swiftUI Views
    public mutating func setView(_ viewBuilder: @escaping ((any StateProtocol) -> some View)) {
        viewFactory = { state in
            HostingBrowserView(rootView: viewBuilder(state), state: state)
        }
    }

    /// Handles AppKit Views
    public mutating func setView(_ viewBuilder: @escaping ((any StateProtocol) -> (NSView & BrowserView))) {
        viewFactory = viewBuilder
    }
}

public class HostingBrowserView<V: View>: NSHostingView<V>, BrowserView {
    public var state: any StateProtocol

    @MainActor @preconcurrency
    public required init(rootView: V, state: any StateProtocol) {
        self.state = state
        super.init(rootView: rootView)
    }

    public required init(rootView: V) {
        state = AltoState() // or some fallback/default state
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency
    public dynamic required init?(coder _: NSCoder) {
        // You could support decoding here if needed
        // For now, safely fail
        nil
    }
}
