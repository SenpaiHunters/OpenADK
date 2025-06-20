//
import AppKit

// MARK: - AltoWindow

public class AltoWindow: NSWindow {
    public var id = UUID()
    private var state: any StateProtocol
    public var showWinowButtons = false

    init(
        contentRect: NSRect,
        contentView: NSView,
        state: any StateProtocol,
        title _: String? = nil,
        isIncognito _: Bool = false,
        minimumSize _: CGSize? = nil
    ) {
        self.state = state

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        toolbar?.isVisible = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        isMovable = false
        if !showWinowButtons {
            standardWindowButton(NSWindow.ButtonType.closeButton)?.isHidden = true
            standardWindowButton(NSWindow.ButtonType.zoomButton)?.isHidden = true
            standardWindowButton(NSWindow.ButtonType.miniaturizeButton)?.isHidden = true
        }

        title = id.uuidString
        self.state.window = self
        self.contentView = contentView
    }
}

// MARK: - BrowserView

public protocol BrowserView {
    var state: any StateProtocol { get set }
}
