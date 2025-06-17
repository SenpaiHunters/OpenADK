//
import AppKit
import SwiftUI


/// Lets us set the default sizing and positioning of a window
public struct DefaultWindowConfiguration {
    public let defaultMinimumSize = CGSize(width: 500, height: 400)
    public let defaultSize = CGSize(width: 1024, height: 768)
    
    public var browserView: (() -> NSView)?
    
    public var windowRec: NSRect {
        return NSRect(x: defaultPoint.x, y: defaultPoint.y, width: defaultSize.width, height: defaultSize.height)
    }
    
    public var defaultPoint: CGPoint {
        if let screen = NSScreen.main {
            let rect = screen.frame
            let height = rect.size.height
            let width = rect.size.width
            
            return CGPoint(x: height/2, y: width/2)
        }
        return CGPoint(x: 0, y: 0)
    }
    
    public init() {
        
    }
    
    /// Note: the functions must be marked with mutating in order to change the value of the struct
    
    /// Handles swiftUI Views
    public mutating func setView<V: View>(_ viewBuilder: @escaping (() -> V)) {
            browserView = {
                let nsView = NSHostingView(rootView: viewBuilder())
                return nsView
            }
        }

    /// Handles AppKit Views
    public mutating func setView(_ viewBuilder: @escaping () -> NSView ) {
        browserView = viewBuilder
    }
}
