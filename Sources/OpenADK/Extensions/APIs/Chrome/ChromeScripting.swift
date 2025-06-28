//
//  ChromeScripting.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog
import WebKit

// MARK: - ChromeScripting

/// Chrome Scripting API implementation (Manifest v3)
/// Provides chrome.scripting functionality for script and CSS injection
public class ChromeScripting {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeScripting")
    private let extensionId: String
    private var injectedScripts: [String: ChromeInjectedScript] = [:]
    private var injectedCSS: [String: ChromeInjectedCSS] = [:]
    private var nextInjectionId = 1

    public init(extensionId: String) {
        self.extensionId = extensionId
        logger.info("💉 ChromeScripting initialized for extension: \(extensionId)")
    }

    // MARK: - Script Injection

    /// Execute a script in specified tabs
    /// - Parameters:
    ///   - injection: Script injection details
    ///   - callback: Completion callback with injection results
    public func executeScript(
        _ injection: ChromeScriptInjection,
        callback: @escaping ([ChromeInjectionResult]) -> ()
    ) {
        let injectionId = generateInjectionId()

        logger.info("💉 Executing script injection: \(injectionId)")

        // Validate injection parameters
        guard validateScriptInjection(injection) else {
            logger.error("❌ Script injection validation failed")
            callback([])
            return
        }

        // Get target tabs
        let targetTabs = resolveTargetTabs(injection.target)

        var results: [ChromeInjectionResult] = []
        let group = DispatchGroup()

        for tab in targetTabs {
            group.enter()

            executeScriptInTab(
                injection: injection,
                tab: tab,
                injectionId: injectionId
            ) { result in
                results.append(result)
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.logger.info("✅ Script injection completed: \(results.count) results")
            callback(results)
        }
    }

    /// Insert CSS into specified tabs
    /// - Parameters:
    ///   - injection: CSS injection details
    ///   - callback: Completion callback
    public func insertCSS(
        _ injection: ChromeCSSInjection,
        callback: (() -> ())? = nil
    ) {
        let injectionId = generateInjectionId()

        logger.info("🎨 Inserting CSS: \(injectionId)")

        // Validate injection parameters
        guard validateCSSInjection(injection) else {
            logger.error("❌ CSS injection validation failed")
            callback?()
            return
        }

        // Get target tabs
        let targetTabs = resolveTargetTabs(injection.target)

        let group = DispatchGroup()

        for tab in targetTabs {
            group.enter()

            insertCSSInTab(
                injection: injection,
                tab: tab,
                injectionId: injectionId
            ) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.logger.info("✅ CSS insertion completed")
            callback?()
        }
    }

    /// Remove CSS from specified tabs
    /// - Parameters:
    ///   - injection: CSS removal details
    ///   - callback: Completion callback
    public func removeCSS(
        _ injection: ChromeCSSInjection,
        callback: (() -> ())? = nil
    ) {
        logger.info("🗑️ Removing CSS")

        // Get target tabs
        let targetTabs = resolveTargetTabs(injection.target)

        let group = DispatchGroup()

        for tab in targetTabs {
            group.enter()

            removeCSSFromTab(
                injection: injection,
                tab: tab
            ) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.logger.info("✅ CSS removal completed")
            callback?()
        }
    }

    /// Register content scripts
    /// - Parameters:
    ///   - scripts: Content scripts to register
    ///   - callback: Completion callback
    public func registerContentScripts(
        _ scripts: [ChromeRegisteredContentScript],
        callback: (() -> ())? = nil
    ) {
        logger.info("📝 Registering \(scripts.count) content scripts")

        for script in scripts {
            // Validate script
            guard validateContentScript(script) else {
                logger.warning("⚠️ Content script validation failed: \(script.id)")
                continue
            }

            // Store script registration
            let injectedScript = ChromeInjectedScript(
                id: script.id,
                extensionId: extensionId,
                matches: script.matches,
                js: script.js,
                css: script.css,
                runAt: script.runAt ?? .documentIdle,
                allFrames: script.allFrames ?? false,
                matchOriginAsFallback: script.matchOriginAsFallback ?? false,
                world: script.world ?? .isolated
            )

            injectedScripts[script.id] = injectedScript

            // Register with content script injector
            registerWithContentScriptInjector(injectedScript)

            logger.info("✅ Registered content script: \(script.id)")
        }

        callback?()
    }

    /// Unregister content scripts
    /// - Parameters:
    ///   - filter: Filter for scripts to unregister
    ///   - callback: Completion callback
    public func unregisterContentScripts(
        filter: ChromeContentScriptFilter? = nil,
        callback: (() -> ())? = nil
    ) {
        logger.info("🗑️ Unregistering content scripts")

        var scriptsToRemove: [String] = []

        if let filter {
            // Apply filter
            for (scriptId, script) in injectedScripts {
                if shouldUnregisterScript(script, filter: filter) {
                    scriptsToRemove.append(scriptId)
                }
            }
        } else {
            // Remove all scripts
            scriptsToRemove = Array(injectedScripts.keys)
        }

        for scriptId in scriptsToRemove {
            if let script = injectedScripts.removeValue(forKey: scriptId) {
                unregisterFromContentScriptInjector(script)
                logger.info("🗑️ Unregistered content script: \(scriptId)")
            }
        }

        logger.info("✅ Unregistered \(scriptsToRemove.count) content scripts")
        callback?()
    }

    /// Get registered content scripts
    /// - Parameters:
    ///   - filter: Filter for scripts to retrieve
    ///   - callback: Completion callback with scripts
    public func getRegisteredContentScripts(
        filter: ChromeContentScriptFilter? = nil,
        callback: @escaping ([ChromeRegisteredContentScript]) -> ()
    ) {
        logger.debug("📋 Getting registered content scripts")

        var results: [ChromeRegisteredContentScript] = []

        for script in injectedScripts.values {
            if let filter {
                if !shouldIncludeScript(script, filter: filter) {
                    continue
                }
            }

            let registeredScript = ChromeRegisteredContentScript(
                id: script.id,
                matches: script.matches,
                excludeMatches: nil,
                js: script.js,
                css: script.css,
                allFrames: script.allFrames,
                matchOriginAsFallback: script.matchOriginAsFallback,
                runAt: script.runAt,
                world: script.world
            )

            results.append(registeredScript)
        }

        logger.debug("📋 Retrieved \(results.count) content scripts")
        callback(results)
    }

    // MARK: - Private Methods

    private func generateInjectionId() -> String {
        let id = nextInjectionId
        nextInjectionId += 1
        return "\(extensionId)_\(id)"
    }

    private func validateScriptInjection(_ injection: ChromeScriptInjection) -> Bool {
        // Must have either files or func, not both
        let hasFiles = injection.files != nil && !injection.files!.isEmpty
        let hasFunc = injection.func != nil

        guard hasFiles != hasFunc else {
            logger.error("❌ Script injection must have either files or func, not both")
            return false
        }

        // Validate target
        guard validateInjectionTarget(injection.target) else {
            return false
        }

        return true
    }

    private func validateCSSInjection(_ injection: ChromeCSSInjection) -> Bool {
        // Must have either files or css, not both
        let hasFiles = injection.files != nil && !injection.files!.isEmpty
        let hasCSS = injection.css != nil

        guard hasFiles != hasCSS else {
            logger.error("❌ CSS injection must have either files or css, not both")
            return false
        }

        // Validate target
        guard validateInjectionTarget(injection.target) else {
            return false
        }

        return true
    }

    private func validateInjectionTarget(_ target: ChromeInjectionTarget) -> Bool {
        // Must have valid tab IDs
        guard !target.tabId.isEmpty else {
            logger.error("❌ Injection target must specify at least one tab ID")
            return false
        }

        return true
    }

    private func validateContentScript(_ script: ChromeRegisteredContentScript) -> Bool {
        // Must have valid ID
        guard !script.id.isEmpty else {
            logger.error("❌ Content script must have a valid ID")
            return false
        }

        // Must have matches
        guard !script.matches.isEmpty else {
            logger.error("❌ Content script must have match patterns")
            return false
        }

        // Must have either JS or CSS
        let hasJS = script.js != nil && !script.js!.isEmpty
        let hasCSS = script.css != nil && !script.css!.isEmpty

        guard hasJS || hasCSS else {
            logger.error("❌ Content script must have either JS or CSS files")
            return false
        }

        return true
    }

    private func resolveTargetTabs(_ target: ChromeInjectionTarget) -> [ChromeTab] {
        // Get actual tabs from ADKData
        target.tabId.compactMap { tabId in
            // Try to find the tab in ADKData
            guard let adkTab = ADKData.shared.tabs.values.first(where: {
                // Convert UUID to Int for comparison (simplified mapping)
                abs($0.id.hashValue) % 100_000 == tabId
            }) else {
                logger.warning("⚠️ Tab not found for ID: \(tabId)")
                return nil
            }

            // Convert ADKTab to ChromeTab
            return convertADKTabToChromeTab(adkTab, chromeTabId: tabId)
        }
    }

    /// Convert ADKTab to ChromeTab for extension API compatibility
    private func convertADKTabToChromeTab(_ adkTab: ADKTab, chromeTabId: Int) -> ChromeTab {
        let webPage = adkTab.content as? ADKWebPage
        let webView = webPage?.webView

        return ChromeTab(
            id: chromeTabId,
            index: adkTab.tabRepresentation?.index ?? 0,
            windowId: 1, // Simplified window ID
            selected: false, // TODO: Implement proper selection state
            active: adkTab === adkTab.state.tabManager.currentTab,
            pinned: false, // TODO: Implement pinned state if needed
            url: webView?.url?.absoluteString ?? "about:blank",
            title: webView?.title ?? "New Tab",
            favIconUrl: nil, // TODO: Implement favicon support
            status: getTabStatus(webView),
            incognito: false, // TODO: Implement incognito detection
            width: Int(webView?.frame.width ?? 1024),
            height: Int(webView?.frame.height ?? 768),
            sessionId: adkTab.id.uuidString
        )
    }

    /// Get tab loading status from WebView
    private func getTabStatus(_ webView: WKWebView?) -> String {
        guard let webView else { return "complete" }
        return webView.isLoading ? "loading" : "complete"
    }

    private func executeScriptInTab(
        injection: ChromeScriptInjection,
        tab: ChromeTab,
        injectionId: String,
        completion: @escaping (ChromeInjectionResult) -> ()
    ) {
        logger.debug("💉 Executing script in tab: \(tab.id)")

        // Find the actual WebView for this tab
        guard let webView = getWebViewForTab(tab) else {
            let result = ChromeInjectionResult(
                tabId: tab.id,
                frameId: 0,
                result: nil,
                error: "Tab WebView not found"
            )
            completion(result)
            return
        }

        // Prepare script content
        var scriptContent = ""

        if let files = injection.files {
            // Load script files from extension
            for file in files {
                if let fileContent = loadExtensionFile(file) {
                    scriptContent += fileContent + "\n"
                }
            }
        } else if let function = injection.func {
            // Execute function with arguments
            let argsJSON = serializeArgs(injection.args ?? [])
            scriptContent = "(\(function))(\(argsJSON))"
        }

        // Execute script in WebView
        DispatchQueue.main.async {
            webView.evaluateJavaScript(scriptContent) { result, error in
                let injectionResult = ChromeInjectionResult(
                    tabId: tab.id,
                    frameId: 0,
                    result: result,
                    error: error?.localizedDescription
                )

                self.logger.info("✅ Script executed in tab \(tab.id): \(error == nil ? "success" : "failed")")
                completion(injectionResult)
            }
        }
    }

    /// Get WebView for a given ChromeTab
    private func getWebViewForTab(_ tab: ChromeTab) -> WKWebView? {
        // Find ADKTab using session ID
        guard let sessionId = tab.sessionId,
              let uuid = UUID(uuidString: sessionId),
              let adkTab = ADKData.shared.tabs[uuid],
              let webPage = adkTab.content as? ADKWebPage else {
            return nil
        }

        return webPage.webView
    }

    /// Load extension file content
    private func loadExtensionFile(_ filename: String) -> String? {
        // TODO: Implement actual file loading from extension bundle
        logger.warning("⚠️ Extension file loading not yet implemented: \(filename)")
        return "// Extension file: \(filename)\nconsole.log('Extension script loaded: \(filename)');"
    }

    /// Serialize function arguments to JSON
    private func serializeArgs(_ args: [Any]) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: args)
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            logger.error("❌ Failed to serialize arguments: \(error)")
            return "[]"
        }
    }

    private func insertCSSInTab(
        injection: ChromeCSSInjection,
        tab: ChromeTab,
        injectionId: String,
        completion: @escaping () -> ()
    ) {
        logger.debug("🎨 Inserting CSS in tab: \(tab.id)")

        // Find the actual WebView for this tab
        guard let webView = getWebViewForTab(tab) else {
            logger.error("❌ WebView not found for tab: \(tab.id)")
            completion()
            return
        }

        // Store CSS injection record
        let cssInjection = ChromeInjectedCSS(
            id: injectionId,
            extensionId: extensionId,
            tabId: tab.id,
            files: injection.files,
            css: injection.css,
            origin: injection.origin ?? .author
        )

        injectedCSS[injectionId] = cssInjection

        // Prepare CSS content
        var cssContent = ""

        if let files = injection.files {
            // Load CSS files from extension
            for file in files {
                if let fileContent = loadExtensionFile(file) {
                    cssContent += fileContent + "\n"
                }
            }
        } else if let css = injection.css {
            cssContent = css
        }

        // Inject CSS into WebView using JavaScript
        let cssInjectionScript = """
        (function() {
            var style = document.createElement('style');
            style.id = '\(injectionId)';
            style.textContent = \(escapeJavaScriptString(cssContent));
            document.head.appendChild(style);
        })();
        """

        DispatchQueue.main.async {
            webView.evaluateJavaScript(cssInjectionScript) { _, error in
                if let error {
                    self.logger.error("❌ CSS injection failed: \(error.localizedDescription)")
                } else {
                    self.logger.info("✅ CSS injected successfully in tab \(tab.id)")
                }
                completion()
            }
        }
    }

    private func removeCSSFromTab(
        injection: ChromeCSSInjection,
        tab: ChromeTab,
        completion: @escaping () -> ()
    ) {
        logger.debug("🗑️ Removing CSS from tab: \(tab.id)")

        // Find the actual WebView for this tab
        guard let webView = getWebViewForTab(tab) else {
            logger.error("❌ WebView not found for tab: \(tab.id)")
            completion()
            return
        }

        // Find and remove matching CSS injections
        let matchingInjections = injectedCSS.values.filter { css in
            css.tabId == tab.id &&
                ((css.files == injection.files) || (css.css == injection.css))
        }

        let group = DispatchGroup()

        for css in matchingInjections {
            group.enter()

            // Remove CSS from WebView using JavaScript
            let cssRemovalScript = """
            (function() {
                var style = document.getElementById('\(css.id)');
                if (style) {
                    style.remove();
                    return true;
                }
                return false;
            })();
            """

            DispatchQueue.main.async {
                webView.evaluateJavaScript(cssRemovalScript) { _, error in
                    if let error {
                        self.logger.error("❌ CSS removal failed: \(error.localizedDescription)")
                    } else {
                        self.logger.info("✅ CSS removed successfully from tab \(tab.id)")
                    }

                    // Remove from tracking
                    self.injectedCSS.removeValue(forKey: css.id)
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    private func registerWithContentScriptInjector(_ script: ChromeInjectedScript) {
        // Register with the browser's content script injection system
        logger.debug("🔗 Registered content script with injector: \(script.id)")

        // TODO: Integrate with ContentScriptInjector to automatically inject
        // scripts when tabs navigate to matching URLs
        notifyContentScriptSystemOfRegistration(script)
    }

    private func unregisterFromContentScriptInjector(_ script: ChromeInjectedScript) {
        // Unregister from the browser's content script injection system
        logger.debug("🔗 Unregistered content script from injector: \(script.id)")

        // TODO: Remove from ContentScriptInjector system
        notifyContentScriptSystemOfUnregistration(script)
    }

    /// Notify the content script system of new registration
    private func notifyContentScriptSystemOfRegistration(_ script: ChromeInjectedScript) {
        // TODO: Integrate with actual ContentScriptInjector
        // This would register the script to be automatically injected when tabs
        // navigate to URLs matching the script's patterns
        logger.info("📝 Content script \(script.id) registered for patterns: \(script.matches)")
    }

    /// Notify the content script system of unregistration
    private func notifyContentScriptSystemOfUnregistration(_ script: ChromeInjectedScript) {
        // TODO: Remove from ContentScriptInjector system
        logger.info("🗑️ Content script \(script.id) unregistered")
    }

    /// Escape JavaScript string for safe injection
    private func escapeJavaScriptString(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        return "\"\(escaped)\""
    }

    private func shouldUnregisterScript(_ script: ChromeInjectedScript, filter: ChromeContentScriptFilter) -> Bool {
        if let ids = filter.ids {
            return ids.contains(script.id)
        }
        return true
    }

    private func shouldIncludeScript(_ script: ChromeInjectedScript, filter: ChromeContentScriptFilter) -> Bool {
        if let ids = filter.ids {
            return ids.contains(script.id)
        }
        return true
    }
}

// MARK: - ChromeScriptInjection

/// Script injection configuration
public struct ChromeScriptInjection {
    public let target: ChromeInjectionTarget
    public let files: [String]?
    public let `func`: String?
    public let args: [Any]?
    public let world: ChromeExecutionWorld?
    public let injectImmediately: Bool?

    public init(
        target: ChromeInjectionTarget,
        files: [String]? = nil,
        func: String? = nil,
        args: [Any]? = nil,
        world: ChromeExecutionWorld? = nil,
        injectImmediately: Bool? = nil
    ) {
        self.target = target
        self.files = files
        self.func = `func`
        self.args = args
        self.world = world
        self.injectImmediately = injectImmediately
    }
}

// MARK: - ChromeCSSInjection

/// CSS injection configuration
public struct ChromeCSSInjection {
    public let target: ChromeInjectionTarget
    public let files: [String]?
    public let css: String?
    public let origin: ChromeStyleOrigin?

    public init(
        target: ChromeInjectionTarget,
        files: [String]? = nil,
        css: String? = nil,
        origin: ChromeStyleOrigin? = nil
    ) {
        self.target = target
        self.files = files
        self.css = css
        self.origin = origin
    }
}

// MARK: - ChromeInjectionTarget

/// Injection target specification
public struct ChromeInjectionTarget {
    public let tabId: [Int]
    public let frameIds: [Int]?
    public let documentIds: [String]?
    public let allFrames: Bool?

    public init(
        tabId: [Int],
        frameIds: [Int]? = nil,
        documentIds: [String]? = nil,
        allFrames: Bool? = nil
    ) {
        self.tabId = tabId
        self.frameIds = frameIds
        self.documentIds = documentIds
        self.allFrames = allFrames
    }
}

// MARK: - ChromeInjectionResult

/// Script injection result
public struct ChromeInjectionResult {
    public let tabId: Int
    public let frameId: Int
    public let result: Any?
    public let error: String?

    public init(
        tabId: Int,
        frameId: Int,
        result: Any? = nil,
        error: String? = nil
    ) {
        self.tabId = tabId
        self.frameId = frameId
        self.result = result
        self.error = error
    }
}

// MARK: - ChromeRegisteredContentScript

/// Registered content script
public struct ChromeRegisteredContentScript {
    public let id: String
    public let matches: [String]
    public let excludeMatches: [String]?
    public let js: [String]?
    public let css: [String]?
    public let allFrames: Bool?
    public let matchOriginAsFallback: Bool?
    public let runAt: ChromeRunAt?
    public let world: ChromeExecutionWorld?

    public init(
        id: String,
        matches: [String],
        excludeMatches: [String]? = nil,
        js: [String]? = nil,
        css: [String]? = nil,
        allFrames: Bool? = nil,
        matchOriginAsFallback: Bool? = nil,
        runAt: ChromeRunAt? = nil,
        world: ChromeExecutionWorld? = nil
    ) {
        self.id = id
        self.matches = matches
        self.excludeMatches = excludeMatches
        self.js = js
        self.css = css
        self.allFrames = allFrames
        self.matchOriginAsFallback = matchOriginAsFallback
        self.runAt = runAt
        self.world = world
    }
}

// MARK: - ChromeContentScriptFilter

/// Content script filter
public struct ChromeContentScriptFilter {
    public let ids: [String]?

    public init(ids: [String]? = nil) {
        self.ids = ids
    }
}

// MARK: - ChromeInjectedScript

/// Internal injected script tracking
struct ChromeInjectedScript {
    let id: String
    let extensionId: String
    let matches: [String]
    let js: [String]?
    let css: [String]?
    let runAt: ChromeRunAt
    let allFrames: Bool
    let matchOriginAsFallback: Bool
    let world: ChromeExecutionWorld
}

// MARK: - ChromeInjectedCSS

/// Internal injected CSS tracking
struct ChromeInjectedCSS {
    let id: String
    let extensionId: String
    let tabId: Int
    let files: [String]?
    let css: String?
    let origin: ChromeStyleOrigin
}

// MARK: - ChromeExecutionWorld

/// Script execution world
public enum ChromeExecutionWorld: String, CaseIterable {
    case isolated = "ISOLATED"
    case main = "MAIN"
}

// MARK: - ChromeStyleOrigin

/// CSS style origin
public enum ChromeStyleOrigin: String, CaseIterable {
    case author = "AUTHOR"
    case user = "USER"
}

// MARK: - ChromeRunAt

/// Script run timing
public enum ChromeRunAt: String, CaseIterable {
    case documentStart = "document_start"
    case documentEnd = "document_end"
    case documentIdle = "document_idle"
}
