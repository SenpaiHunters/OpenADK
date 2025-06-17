//
import AppKit


public class AltoWindow: NSWindow {
    private var state: AltoState
    
    init(contentRect: NSRect, content: () -> NSView, state: AltoState? = nil, title: String? = nil, isIncognito: Bool = false, minimumSize: CGSize? = nil) {
        self.state = state ?? AltoState()
        
        super.init(contentRect: contentRect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        
        // more will go in this class but im in the middle of a rewrite
        self.contentView = content()
    }
}
