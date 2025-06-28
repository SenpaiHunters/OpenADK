//
//  NotificationManager.swift
//  OpenADK
//
//  Created by Kami on 27/06/2025.
//

import Foundation

/// Notification names for extension runtime events
extension Notification.Name {
    static let openExtensionSettings = Notification.Name("OpenExtensionSettings")
    static let webViewDidFinishNavigation = Notification.Name("WebViewDidFinishNavigation")
    static let contentWasBlocked = Notification.Name("ContentWasBlocked")
}
