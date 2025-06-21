//
//  HostingBrowserView.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import SwiftUI

// MARK: - HostingBrowserView

/// An NSHosting veiw to wrap SwiftUI Views
public class HostingBrowserView<V: View>: NSHostingView<V>, BrowserView {
    public var state: any StateProtocol

    @MainActor @preconcurrency
    public required init(rootView: V, state: any StateProtocol) {
        self.state = state
        super.init(rootView: rootView)
    }

    public required init(rootView: V) {
        state = GenaricState()
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency
    public dynamic required init?(coder _: NSCoder) {
        // You could support decoding here if needed
        // For now, safely fail
        nil
    }
}
