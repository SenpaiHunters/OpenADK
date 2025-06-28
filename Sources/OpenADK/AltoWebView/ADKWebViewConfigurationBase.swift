//
//  ADKWebViewConfigurationBase.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import OpenADKObjC
import OSLog
import WebKit

/// A base configuration for `WKWebViewConfiguration` used for creating tabs.
///
/// This is a modified version of Beam's implementation:
/// https://github.com/beamlegacy/beam/blob/3fa234d6ad509c2755c16fb3fd240e9142eaa8bb/Beam/Classes/Models/TabAndWebview/BeamWebViewConfiguration/BeamWebViewConfiguration.swift#L4
public class ADKWebViewConfigurationBase: WKWebViewConfiguration {
    /// Logger for configuration debugging
    private let logger = Logger(subsystem: "com.alto.webkit", category: "WebViewConfig")

    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override init() {
        super.init()
        setupBaseConfiguration()
    }

    public init(dataStore: WKWebsiteDataStore) {
        super.init()

        logger.info("🔧 Initializing WebView configuration with custom data store")

        websiteDataStore = dataStore
        setupBaseConfiguration()
    }

    /// Configure base WebView settings
    private func setupBaseConfiguration() {
        logger.info("⚙️ Setting up base WebView configuration")

        configureJavaScriptSettings()
        configureMediaSettings()
        configureWebpageDefaults()
        setupExtensionCompatibility()

        logger.info("✅ WebView configuration setup complete")
    }

    /// Configure JavaScript and security settings
    private func configureJavaScriptSettings() {
        let jsSettings: [(String, Any)] = [
            ("javaScriptEnabled", true),
            ("developerExtrasEnabled", true),
            ("webSecurityEnabled", true),
            ("logsPageMessagesToSystemConsoleEnabled", true)
        ]

        preferences.javaScriptCanOpenWindowsAutomatically = true
        preferences.isFraudulentWebsiteWarningEnabled = true

        // Apply JavaScript-related preferences
        for (key, value) in jsSettings {
            preferences.setValue(value, forKey: key)
        }

        // Force enable developer menu for macOS 13.3+
        preferences.setValue(true, forKey: "developerExtrasEnabled")
        preferences.setValue(true, forKey: "webSecurityEnabled")
    }

    /// Configure media playback settings
    private func configureMediaSettings() {
        allowsAirPlayForMediaPlayback = true
        preferences._setAllowsPicture(inPictureMediaPlayback: true)
        preferences._setBackspaceKeyNavigationEnabled(false)
        preferences.isElementFullscreenEnabled = true
        preferences.setValue(true, forKey: "allowsInlineMediaPlayback")
    }

    /// Configure default webpage preferences
    private func configureWebpageDefaults() {
        defaultWebpagePreferences.preferredContentMode = .desktop
        defaultWebpagePreferences.allowsContentJavaScript = true
    }

    /// Configure settings for better extension compatibility
    private func setupExtensionCompatibility() {
        logger.debug("🔌 Setting up extension compatibility settings")

        let extensionSettings: [(String, Any)] = [
            ("webSecurityEnabled", false), // Allow cross-origin requests
            ("diagnosticLoggingEnabled", true),
            ("mockCaptureDevicesEnabled", true)
        ]

        // Apply extension compatibility preferences
        for (key, value) in extensionSettings {
            preferences.setValue(value, forKey: key)
        }

        logger.debug("✅ Extension compatibility settings configured")
    }
}
