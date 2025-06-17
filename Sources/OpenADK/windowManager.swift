//
import AppKit
import SwiftUI

/// Lets us set the default sizing and positioning of a window
public struct DefaultWindowConfiguration {
    public let defaultMinimumSize = CGSize(width: 500, height: 400)
    public let defaultSize = CGSize(width: 1024, height: 768)
    
    public var browserView: NSView?
    
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
    
    /// Note: the functions must be marked with mutating in order to change the value of the struct
    
    /// Handles swiftUI Views
    public mutating func setView<V: View>(_ view: V) {
        let hostingView = NSHostingView(rootView: view)
        browserView = hostingView
    }

    /// Handles AppKit Views
    public mutating func setView(_ view: NSView) {
        browserView = view
    }
}

/// Handles creating Browser Windows
final public class WindowManager {
    private let alto = Alto.shared
    private var altoState: AltoState?
    
    public var configuration: DefaultWindowConfiguration
    
    public var windows: [AltoWindow] = []
    
    public init() {
        self.configuration = DefaultWindowConfiguration()
    }
    
    /// Creates a window with designated content
    @discardableResult
    public func createWindow(content: NSView, frame: NSRect? = nil) -> AltoWindow? {
        /// We still use AltoWindow rather than window because we still want to be able to keep track of it
        let window = AltoWindow(
            contentRect: frame ?? configuration.windowRec,
            content: content,
            minimumSize: configuration.defaultMinimumSize
        )
        
        window.orderFront(nil)
        return window
    }
    
    /// Creates a browser window with tabs
    @discardableResult
    public func createWindow(tabs: [AltoTab]) throws -> AltoWindow? {
        let browserView = configuration.browserView
        
        if let browserView {
            let window = self.createWindow(content: browserView)
            
            return window
        } else {
            throw WindowErrors.contentViewNilValue
        }
    }
}

public enum WindowErrors: Error {
    case contentViewNilValue
}

public class AltoTab {
    
    public init() {
        
    }
}

public class AltoWindow: NSWindow {
    
    init(contentRect: NSRect, content: NSView, state: AltoState? = nil, title: String? = nil, isIncognito: Bool = false, minimumSize: CGSize? = nil) {
        
        super.init(contentRect: contentRect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        
        self.contentView = content
    }
}
