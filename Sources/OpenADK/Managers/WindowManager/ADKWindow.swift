//
//  ADKWindow.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import AppKit

// MARK: - AltoWindow

open class ADKWindow: NSWindow {
    public private(set) var id = UUID()
    public var profile: Profile?

    public let state: ADKState

    private var data: ADKData {
        ADKData.shared
    }

    private var hostingView: NSView?

    public init(
        rootView: NSView? = nil,
        state: ADKState? = nil,
        profile: Profile? = nil,
        useDefaultProfile: Bool = true,
        contentRect: NSRect? = nil
    ) {
        let config = DefaultWindowConfiguration()
        self.state = state ?? ADKState()
        let defaultProfile = ProfileManager.shared.defaultProfile
        self.profile = useDefaultProfile ? defaultProfile : profile

        super.init(
            contentRect: config.contentRect,
            styleMask: config.styleMask,
            backing: .buffered,
            defer: false
        )
        minSize = config.defaultMinimumSize

        // let defaultView = NSHostingView(rootView: DefaultBrowserView())
        contentView = rootView // ?? defaultView
    }

    func getTitle() -> String {
        state.currentContent?[0].title ?? ""
    }

    func setTitle(_ title: String) {
        self.title = title
    }
}
