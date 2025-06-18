//
import AppKit
import SwiftUI


/// Handles creating Browser Windows
final public class WindowManager {
    
    public var configuration: DefaultWindowConfiguration
    
    public var windows: [AltoWindow] = []
    
    public init() {
        self.configuration = DefaultWindowConfiguration()
    }
    
    /// Creates a window with designated content
    @discardableResult
    public func createWindow(content: () -> (NSView & BrowserView), frame: NSRect? = nil) -> AltoWindow? {
        print("NEW NUGH UH")

        guard let state = configuration.state else {
            return nil
        }
        print("NEW WIDNOW")
        /// We still use AltoWindow rather than window because we still want to be able to keep track of it
        let window = AltoWindow(
            contentRect: frame ?? configuration.windowRec,
            content: content,
            state: state,
            minimumSize: configuration.defaultMinimumSize
        )
        self.windows.append(window)
        
        window.orderFront(nil)
        return window
    }
    
    /// Creates a browser window with tabs
    @discardableResult
    public func createWindow(tabs: [any TabProtocol]) -> AltoWindow? {
        let browserView = configuration.browserView
        
        if let browserView {
            let window = self.createWindow(content: browserView)
            
            return window
        } else {
            return nil
        }
    }
}

