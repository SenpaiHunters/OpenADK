//
import AppKit


public class AltoWindow: NSWindow {
    public var id = UUID()
    private var state: any StateProtocol
    
    init(contentRect: NSRect, contentView: NSView, state: any StateProtocol, title: String? = nil, isIncognito: Bool = false, minimumSize: CGSize? = nil) {
        self.state = state
        
        super.init(contentRect: contentRect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        
        self.title = id.uuidString
        self.state.window = self
        self.contentView = contentView
    }
}



public protocol BrowserView {
    var state: any StateProtocol { get set }
}
