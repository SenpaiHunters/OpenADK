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
        public func createWindow(tabs: [any TabProtocol]) -> AltoWindow? {
            guard let viewFactory = configuration.viewFactory else {
                print("Error: viewFactory not set in DefaultWindowConfiguration.")
                return nil
            }
            
            let newState = configuration.stateFactory()
            
            let contentView = viewFactory(newState)
            
            let window = AltoWindow(
                contentRect: configuration.windowRec,
                contentView: contentView,
                state: newState,
                minimumSize: configuration.defaultMinimumSize
            )
            
            self.windows.append(window)
            window.orderFront(nil)
            return window
        }
}

