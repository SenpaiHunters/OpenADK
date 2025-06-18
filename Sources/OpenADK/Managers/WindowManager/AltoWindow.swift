//
import AppKit

public class AltoWindow: NSWindow {
    public var id = UUID()
    private var state: any StateProtocol

    init(contentRect: NSRect, contentView: NSView, state: any StateProtocol, title _: String? = nil, isIncognito _: Bool = false, minimumSize _: CGSize? = nil) {
        self.state = state

        super.init(contentRect: contentRect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)

        title = id.uuidString
        self.state.window = self
        self.contentView = contentView
    }
}

public protocol BrowserView {
    var state: any StateProtocol { get set }
}
