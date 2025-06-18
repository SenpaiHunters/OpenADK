//
import AppKit


public class AltoWindow: NSWindow {
    private var state: StateProtocol
    
    init(contentRect: NSRect, content: () -> (NSView & BrowserView), state: StateProtocol, title: String? = nil, isIncognito: Bool = false, minimumSize: CGSize? = nil) {
        self.state = state
        
        super.init(contentRect: contentRect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        
        // more will go in this class but im in the middle of a rewrite
        
        var contentView = content()
        contentView.state = self.state
        self.contentView = contentView
    }
}


public protocol BrowserView {
    var state: StateProtocol { get set }
}
