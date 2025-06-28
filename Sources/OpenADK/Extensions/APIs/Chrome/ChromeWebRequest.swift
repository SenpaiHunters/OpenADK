//
//  ChromeWebRequest.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog
import WebKit

// MARK: - ChromeWebRequest

/// Chrome WebRequest API implementation
/// Provides chrome.webRequest functionality for intercepting and modifying web requests
public class ChromeWebRequest {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeWebRequest")

    private let extensionId: String
    private var beforeRequestListeners: [(ChromeWebRequestDetails) -> ChromeWebRequestResponse?] = []
    private var beforeSendHeadersListeners: [(ChromeWebRequestDetails) -> ChromeWebRequestResponse?] = []
    private var responseStartedListeners: [(ChromeWebRequestDetails) -> ()] = []
    private var completedListeners: [(ChromeWebRequestDetails) -> ()] = []
    private var errorOccurredListeners: [(ChromeWebRequestDetails) -> ()] = []

    /// Request ID counter
    private var requestIdCounter: Int64 = 0
    private let requestIdLock = NSLock()

    /// Active requests
    private var activeRequests: [String: ChromeWebRequestDetails] = [:]

    public init(extensionId: String) {
        self.extensionId = extensionId
        logger.info("🌐 ChromeWebRequest initialized for extension: \(extensionId)")
    }

    // MARK: - Event Listeners

    /// Add listener for onBeforeRequest event
    /// - Parameters:
    ///   - listener: Callback function for before request events
    ///   - filter: Request filter
    ///   - extraInfoSpec: Additional information to include
    public func addBeforeRequestListener(
        _ listener: @escaping (ChromeWebRequestDetails) -> ChromeWebRequestResponse?,
        filter: ChromeWebRequestFilter,
        extraInfoSpec: [String]? = nil
    ) {
        beforeRequestListeners.append(listener)
        logger.debug("👂 Added onBeforeRequest listener")
    }

    /// Add listener for onBeforeSendHeaders event
    /// - Parameters:
    ///   - listener: Callback function for before send headers events
    ///   - filter: Request filter
    ///   - extraInfoSpec: Additional information to include
    public func addBeforeSendHeadersListener(
        _ listener: @escaping (ChromeWebRequestDetails) -> ChromeWebRequestResponse?,
        filter: ChromeWebRequestFilter,
        extraInfoSpec: [String]? = nil
    ) {
        beforeSendHeadersListeners.append(listener)
        logger.debug("👂 Added onBeforeSendHeaders listener")
    }

    /// Add listener for onResponseStarted event
    /// - Parameters:
    ///   - listener: Callback function for response started events
    ///   - filter: Request filter
    ///   - extraInfoSpec: Additional information to include
    public func addResponseStartedListener(
        _ listener: @escaping (ChromeWebRequestDetails) -> (),
        filter: ChromeWebRequestFilter,
        extraInfoSpec: [String]? = nil
    ) {
        responseStartedListeners.append(listener)
        logger.debug("👂 Added onResponseStarted listener")
    }

    /// Add listener for onCompleted event
    /// - Parameters:
    ///   - listener: Callback function for completed events
    ///   - filter: Request filter
    ///   - extraInfoSpec: Additional information to include
    public func addCompletedListener(
        _ listener: @escaping (ChromeWebRequestDetails) -> (),
        filter: ChromeWebRequestFilter,
        extraInfoSpec: [String]? = nil
    ) {
        completedListeners.append(listener)
        logger.debug("👂 Added onCompleted listener")
    }

    /// Add listener for onErrorOccurred event
    /// - Parameters:
    ///   - listener: Callback function for error events
    ///   - filter: Request filter
    ///   - extraInfoSpec: Additional information to include
    public func addErrorOccurredListener(
        _ listener: @escaping (ChromeWebRequestDetails) -> (),
        filter: ChromeWebRequestFilter,
        extraInfoSpec: [String]? = nil
    ) {
        errorOccurredListeners.append(listener)
        logger.debug("👂 Added onErrorOccurred listener")
    }

    // MARK: - Request Handling

    /// Handle a web request (called by the browser engine)
    /// - Parameters:
    ///   - request: URL request
    ///   - webView: WebView making the request
    ///   - completion: Completion handler with modified request or nil
    public func handleRequest(
        _ request: URLRequest,
        from webView: WKWebView,
        completion: @escaping (URLRequest?) -> ()
    ) {
        let requestId = generateRequestId()
        let details = createRequestDetails(
            requestId: requestId,
            request: request,
            webView: webView
        )

        activeRequests[requestId] = details

        // Process onBeforeRequest listeners
        var modifiedRequest = request
        var shouldCancel = false

        for listener in beforeRequestListeners {
            if let response = listener(details) {
                switch response.action {
                case .cancel:
                    shouldCancel = true
                    logger.debug("🚫 Request cancelled by extension: \(requestId)")
                case let .redirect(url):
                    var newRequest = request
                    newRequest.url = url
                    modifiedRequest = newRequest
                    logger.debug("↩️ Request redirected by extension: \(requestId) -> \(url)")
                case .allow:
                    break
                }

                if shouldCancel {
                    break
                }
            }
        }

        if shouldCancel {
            completion(nil)
            return
        }

        // Process onBeforeSendHeaders listeners
        for listener in beforeSendHeadersListeners {
            if let response = listener(details) {
                if case .cancel = response.action {
                    completion(nil)
                    return
                }

                // Apply header modifications
                if let headers = response.requestHeaders {
                    var mutableRequest = modifiedRequest
                    for (key, value) in headers {
                        mutableRequest.setValue(value, forHTTPHeaderField: key)
                    }
                    modifiedRequest = mutableRequest
                }
            }
        }

        completion(modifiedRequest)
    }

    /// Notify about response started
    /// - Parameters:
    ///   - requestId: Request identifier
    ///   - response: HTTP response
    public func notifyResponseStarted(requestId: String, response: HTTPURLResponse) {
        guard var details = activeRequests[requestId] else { return }

        details.statusCode = response.statusCode
        details.responseHeaders = response.allHeaderFields as? [String: String] ?? [:]
        details.statusLine = "HTTP/\(response.statusCode)"

        activeRequests[requestId] = details

        for listener in responseStartedListeners {
            listener(details)
        }

        logger.debug("📤 Response started: \(requestId) (\(response.statusCode))")
    }

    /// Notify about request completion
    /// - Parameters:
    ///   - requestId: Request identifier
    ///   - response: HTTP response (optional)
    public func notifyCompleted(requestId: String, response: HTTPURLResponse? = nil) {
        guard let details = activeRequests[requestId] else { return }

        if let response {
            var updatedDetails = details
            updatedDetails.statusCode = response.statusCode
            updatedDetails.responseHeaders = response.allHeaderFields as? [String: String] ?? [:]
            updatedDetails.statusLine = "HTTP/\(response.statusCode)"

            for listener in completedListeners {
                listener(updatedDetails)
            }
        } else {
            for listener in completedListeners {
                listener(details)
            }
        }

        activeRequests.removeValue(forKey: requestId)
        logger.debug("✅ Request completed: \(requestId)")
    }

    /// Notify about request error
    /// - Parameters:
    ///   - requestId: Request identifier
    ///   - error: Error that occurred
    public func notifyError(requestId: String, error: Error) {
        guard var details = activeRequests[requestId] else { return }

        details.error = error.localizedDescription

        for listener in errorOccurredListeners {
            listener(details)
        }

        activeRequests.removeValue(forKey: requestId)
        logger.debug("❌ Request error: \(requestId) - \(error)")
    }

    // MARK: - Private Implementation

    private func generateRequestId() -> String {
        requestIdLock.lock()
        defer { requestIdLock.unlock() }

        requestIdCounter += 1
        return "\(extensionId)_\(requestIdCounter)"
    }

    private func createRequestDetails(
        requestId: String,
        request: URLRequest,
        webView: WKWebView
    ) -> ChromeWebRequestDetails {
        ChromeWebRequestDetails(
            requestId: requestId,
            url: request.url?.absoluteString ?? "",
            method: request.httpMethod ?? "GET",
            frameId: 0, // Main frame
            parentFrameId: -1,
            tabId: extractTabId(from: webView),
            type: inferResourceType(from: request),
            timeStamp: Date().timeIntervalSince1970 * 1000,
            requestHeaders: extractHeaders(from: request),
            statusCode: nil,
            responseHeaders: [:],
            statusLine: nil,
            error: nil
        )
    }

    private func extractTabId(from webView: WKWebView) -> Int {
        // TODO: Implementation, you'd map WebView to tab ID
        // However, for the time being, we'll just return 0.
        0
    }

    private func inferResourceType(from request: URLRequest) -> ChromeResourceType {
        guard let url = request.url else { return .other }

        let pathExtension = url.pathExtension.lowercased()

        switch pathExtension {
        case "js":
            return .script
        case "css":
            return .stylesheet
        case "png",
             "jpg",
             "jpeg",
             "gif",
             "svg",
             "webp":
            return .image
        case "woff",
             "woff2",
             "ttf",
             "otf":
            return .font
        case "xml":
            return .xmlHttpRequest
        default:
            if request.httpMethod == "POST" || request.httpMethod == "PUT" {
                return .xmlHttpRequest
            }
            return .other
        }
    }

    private func extractHeaders(from request: URLRequest) -> [String: String] {
        request.allHTTPHeaderFields ?? [:]
    }
}

// MARK: - ChromeWebRequestDetails

/// Web request details
public struct ChromeWebRequestDetails {
    public let requestId: String
    public let url: String
    public let method: String
    public let frameId: Int
    public let parentFrameId: Int
    public let tabId: Int
    public let type: ChromeResourceType
    public let timeStamp: Double
    public let requestHeaders: [String: String]
    public var statusCode: Int?
    public var responseHeaders: [String: String]
    public var statusLine: String?
    public var error: String?

    public init(
        requestId: String,
        url: String,
        method: String,
        frameId: Int,
        parentFrameId: Int,
        tabId: Int,
        type: ChromeResourceType,
        timeStamp: Double,
        requestHeaders: [String: String],
        statusCode: Int? = nil,
        responseHeaders: [String: String] = [:],
        statusLine: String? = nil,
        error: String? = nil
    ) {
        self.requestId = requestId
        self.url = url
        self.method = method
        self.frameId = frameId
        self.parentFrameId = parentFrameId
        self.tabId = tabId
        self.type = type
        self.timeStamp = timeStamp
        self.requestHeaders = requestHeaders
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.statusLine = statusLine
        self.error = error
    }
}

// MARK: - ChromeWebRequestResponse

/// Web request response from listeners
public struct ChromeWebRequestResponse {
    public let action: ChromeWebRequestAction
    public let requestHeaders: [String: String]?

    public init(action: ChromeWebRequestAction, requestHeaders: [String: String]? = nil) {
        self.action = action
        self.requestHeaders = requestHeaders
    }
}

// MARK: - ChromeWebRequestAction

/// Web request actions
public enum ChromeWebRequestAction {
    case allow
    case cancel
    case redirect(URL)
}

// MARK: - ChromeWebRequestFilter

/// Web request filter
public struct ChromeWebRequestFilter {
    public let urls: [String]
    public let types: [ChromeResourceType]?
    public let tabId: Int?
    public let windowId: Int?

    public init(
        urls: [String],
        types: [ChromeResourceType]? = nil,
        tabId: Int? = nil,
        windowId: Int? = nil
    ) {
        self.urls = urls
        self.types = types
        self.tabId = tabId
        self.windowId = windowId
    }
}

// MARK: - ChromeResourceType

/// Chrome resource types
public enum ChromeResourceType: String, CaseIterable {
    case mainFrame = "main_frame"
    case subFrame = "sub_frame"
    case stylesheet
    case script
    case image
    case font
    case object
    case xmlHttpRequest = "xmlhttprequest"
    case ping
    case cspReport = "csp_report"
    case media
    case websocket
    case other
}
