//
//  ADKWebViewConfigurationBase.swift
//  Alto
//
//  Created by StudioMovieGirl
//

import OpenADKObjC
import WebKit

/// A base configuration for `WKWebViewConfiguration` used for creating tabs.
///
/// This is a modified version of Beam's implementation:
/// https://github.com/beamlegacy/beam/blob/3fa234d6ad509c2755c16fb3fd240e9142eaa8bb/Beam/Classes/Models/TabAndWebview/BeamWebViewConfiguration/BeamWebViewConfiguration.swift#L4
public class ADKWebViewConfigurationBase: WKWebViewConfiguration {
    required init?(coder: NSCoder) { super.init(coder: coder) }

    public override init() {
        super.init()
    }

    public init(dataStore: WKWebsiteDataStore) {
        super.init()

        websiteDataStore = dataStore
        preferences.javaScriptCanOpenWindowsAutomatically = true
        preferences.isFraudulentWebsiteWarningEnabled = true
        preferences.setValue(true, forKey: "developerExtrasEnabled")
        allowsAirPlayForMediaPlayback = true
        preferences._setAllowsPicture(inPictureMediaPlayback: true)
        preferences._setBackspaceKeyNavigationEnabled(false)
        preferences.isElementFullscreenEnabled = true

        defaultWebpagePreferences.preferredContentMode = .desktop
        defaultWebpagePreferences.allowsContentJavaScript = true
    }
}
