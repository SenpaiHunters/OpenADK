//
//  ContentScriptInjector.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog
import WebKit

// MARK: - ContentScriptInjector

/// Manages injection of content scripts into web pages
@MainActor
public class ContentScriptInjector {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ContentScript")

    /// Loaded content scripts by extension ID
    private var loadedScripts: [UUID: [ContentScript]] = [:]

    /// Script injection registry
    private var scriptRegistry: [UUID: [WKUserScript]] = [:]

    public init() {
        logger.info("📝 ContentScriptInjector initialized")
    }

    /// Register content scripts for an extension
    /// - Parameters:
    ///   - scripts: Content scripts to register
    ///   - extensionId: Extension ID
    ///   - baseURL: Extension base URL
    public func registerContentScripts(
        _ scripts: [ContentScript],
        for extensionId: UUID,
        baseURL: URL
    ) throws {
        logger.info("📝 Registering \(scripts.count) content scripts for extension \(extensionId)")

        loadedScripts[extensionId] = scripts

        let userScripts = try scripts.flatMap { script in
            try createUserScripts(from: script, baseURL: baseURL)
        }

        scriptRegistry[extensionId] = userScripts
        logger.info("✅ Registered \(userScripts.count) user scripts for extension \(extensionId)")
    }

    /// Create user scripts from a content script configuration
    /// - Parameters:
    ///   - script: Content script configuration
    ///   - baseURL: Extension base URL
    /// - Returns: Array of WKUserScript objects
    private func createUserScripts(from script: ContentScript, baseURL: URL) throws -> [WKUserScript] {
        var userScripts: [WKUserScript] = []

        // Process JavaScript files
        if let jsFiles = script.js {
            let jsScripts = try jsFiles.map { jsFile in
                try createJavaScriptUserScript(
                    from: jsFile,
                    baseURL: baseURL,
                    script: script
                )
            }
            userScripts.append(contentsOf: jsScripts)
        }

        // Process CSS files
        if let cssFiles = script.css {
            let cssScripts = try cssFiles.map { cssFile in
                try createCSSUserScript(
                    from: cssFile,
                    baseURL: baseURL,
                    script: script
                )
            }
            userScripts.append(contentsOf: cssScripts)
        }

        return userScripts
    }

    /// Create a JavaScript user script
    /// - Parameters:
    ///   - jsFile: JavaScript file path
    ///   - baseURL: Extension base URL
    ///   - script: Content script configuration
    /// - Returns: WKUserScript for JavaScript
    private func createJavaScriptUserScript(
        from jsFile: String,
        baseURL: URL,
        script: ContentScript
    ) throws -> WKUserScript {
        let scriptURL = baseURL.appendingPathComponent(jsFile)
        let scriptContent = try String(contentsOf: scriptURL)

        let injectionTime = getInjectionTime(for: script.runAt)
        let isMainFrameOnly = script.allFrames != true

        return WKUserScript(
            source: scriptContent,
            injectionTime: injectionTime,
            forMainFrameOnly: isMainFrameOnly
        )
    }

    /// Create a CSS user script
    /// - Parameters:
    ///   - cssFile: CSS file path
    ///   - baseURL: Extension base URL
    ///   - script: Content script configuration
    /// - Returns: WKUserScript for CSS injection
    private func createCSSUserScript(
        from cssFile: String,
        baseURL: URL,
        script: ContentScript
    ) throws -> WKUserScript {
        let cssURL = baseURL.appendingPathComponent(cssFile)
        let cssContent = try String(contentsOf: cssURL)

        // Wrap CSS in JavaScript for injection
        let jsWrapper = try createCSSWrapper(for: cssContent)
        let isMainFrameOnly = script.allFrames != true

        return WKUserScript(
            source: jsWrapper,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: isMainFrameOnly
        )
    }

    /// Create JavaScript wrapper for CSS injection
    /// - Parameter cssContent: CSS content to wrap
    /// - Returns: JavaScript code that injects CSS
    private func createCSSWrapper(for cssContent: String) throws -> String {
        let escapedCSS = try String(
            data: JSONSerialization.data(withJSONObject: cssContent),
            encoding: .utf8
        ) ?? "''"

        return """
        (function() {
            var style = document.createElement('style');
            style.textContent = \(escapedCSS);
            document.head.appendChild(style);
        })();
        """
    }

    /// Get WebKit injection time from content script run time
    /// - Parameter runAt: Content script run time
    /// - Returns: WebKit injection time
    private func getInjectionTime(for runAt: ContentScript.RunAt) -> WKUserScriptInjectionTime {
        switch runAt {
        case .documentStart:
            .atDocumentStart
        case .documentEnd,
             .documentIdle:
            .atDocumentEnd
        }
    }

    /// Unregister content scripts for an extension
    /// - Parameter extensionId: Extension ID
    public func unregisterContentScripts(for extensionId: UUID) {
        loadedScripts.removeValue(forKey: extensionId)
        scriptRegistry.removeValue(forKey: extensionId)
        logger.info("🗑️ Unregistered content scripts for extension \(extensionId)")
    }

    /// Inject scripts for an extension into a WebView
    /// - Parameters:
    ///   - extensionId: Extension ID
    ///   - webView: Target WebView
    ///   - url: Current URL
    public func injectScripts(
        for extensionId: UUID,
        into webView: WKWebView,
        url: URL
    ) async {
        guard let scripts = loadedScripts[extensionId],
              let userScripts = scriptRegistry[extensionId] else {
            return
        }

        logger.debug("🔍 Checking scripts for \(url.absoluteString)")

        let configuration = webView.configuration

        for (index, script) in scripts.enumerated() where shouldInjectScript(script, for: url) {
            guard index < userScripts.count else { continue }

            let userScript = userScripts[index]
            configuration.userContentController.addUserScript(userScript)

            logger.debug("💉 Injected script for extension \(extensionId)")
        }
    }

    /// Check if a script should be injected for the given URL
    /// - Parameters:
    ///   - script: Content script
    ///   - url: Target URL
    /// - Returns: Whether script should be injected
    private func shouldInjectScript(_ script: ContentScript, for url: URL) -> Bool {
        let urlString = url.absoluteString

        // Check if URL matches any include pattern
        let matchesInclude = script.matches.contains { pattern in
            matchesPattern(pattern, url: urlString)
        }

        guard matchesInclude else { return false }

        // Check if URL matches any exclude pattern
        if let excludeMatches = script.excludeMatches {
            let matchesExclude = excludeMatches.contains { pattern in
                matchesPattern(pattern, url: urlString)
            }
            if matchesExclude { return false }
        }

        return true
    }

    /// Check if URL matches a pattern
    /// - Parameters:
    ///   - pattern: URL pattern
    ///   - url: URL string
    /// - Returns: Whether URL matches pattern
    private func matchesPattern(_ pattern: String, url: String) -> Bool {
        // Handle special case for all URLs
        if pattern == "<all_urls>" {
            return true
        }

        // Handle wildcard patterns
        if pattern.contains("*") {
            return matchesWildcardPattern(pattern, url: url)
        }

        // Simple prefix matching
        return url.hasPrefix(pattern)
    }

    /// Match URL against wildcard pattern
    /// - Parameters:
    ///   - pattern: Wildcard pattern
    ///   - url: URL string
    /// - Returns: Whether URL matches wildcard pattern
    private func matchesWildcardPattern(_ pattern: String, url: String) -> Bool {
        // Convert glob pattern to regex
        let regexPattern = pattern
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")

        do {
            let regex = try NSRegularExpression(pattern: regexPattern)
            let range = NSRange(location: 0, length: url.count)
            return regex.firstMatch(in: url, options: [], range: range) != nil
        } catch {
            logger.error("Invalid regex pattern: \(pattern)")
            return false
        }
    }
}

// MARK: - ContentScript

/// Content script configuration
public struct ContentScript: Codable, Equatable {
    public let matches: [String]
    public let excludeMatches: [String]?
    public let js: [String]?
    public let css: [String]?
    public let runAt: RunAt
    public let allFrames: Bool?
    public let includeGlobs: [String]?
    public let excludeGlobs: [String]?

    public enum RunAt: String, Codable {
        case documentStart = "document_start"
        case documentEnd = "document_end"
        case documentIdle = "document_idle"
    }

    public init(
        matches: [String],
        excludeMatches: [String]? = nil,
        js: [String]? = nil,
        css: [String]? = nil,
        runAt: RunAt = .documentEnd,
        allFrames: Bool? = nil,
        includeGlobs: [String]? = nil,
        excludeGlobs: [String]? = nil
    ) {
        self.matches = matches
        self.excludeMatches = excludeMatches
        self.js = js
        self.css = css
        self.runAt = runAt
        self.allFrames = allFrames
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
    }
}

// MARK: - ContentScriptError

/// Content script injection errors
public enum ContentScriptError: Error, LocalizedError {
    case scriptNotFound(String)
    case invalidPattern(String)
    case injectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .scriptNotFound(script):
            "Script file not found: \(script)"
        case let .invalidPattern(pattern):
            "Invalid URL pattern: \(pattern)"
        case let .injectionFailed(error):
            "Script injection failed: \(error)"
        }
    }
}
