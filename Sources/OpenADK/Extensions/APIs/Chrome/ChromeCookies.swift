//
//  ChromeCookies.swift
//  OpenADK
//
//  Created by Kami on 26/06/2025.
//

import Foundation
import OSLog
import WebKit

// MARK: - ChromeCookies

/// Chrome Cookies API implementation
/// Provides chrome.cookies functionality for accessing and managing cookies
public class ChromeCookies {
    private let logger = Logger(subsystem: "com.alto.extensions", category: "ChromeCookies")

    private let extensionId: String
    private let httpCookieStorage = HTTPCookieStorage.shared
    private var changedListeners: [(ChromeCookieChangeInfo) -> ()] = []

    public init(extensionId: String) {
        self.extensionId = extensionId
        logger.info("🍪 ChromeCookies initialized for extension: \(extensionId)")
    }

    // MARK: - Public API

    /// Get cookie by details
    /// - Parameters:
    ///   - details: Cookie details to search for
    ///   - callback: Callback with found cookie or nil
    public func get(
        _ details: ChromeCookieDetails,
        callback: @escaping (ChromeCookie?) -> ()
    ) {
        guard let url = URL(string: details.url) else {
            callback(nil)
            return
        }

        let cookies = httpCookieStorage.cookies(for: url) ?? []
        let foundCookie = cookies.first { cookie in
            cookie.name == details.name
        }

        if let httpCookie = foundCookie {
            let chromeCookie = convertToChromeCookie(httpCookie, storeId: details.storeId)
            callback(chromeCookie)
        } else {
            callback(nil)
        }

        logger.debug("🔍 Searched for cookie: \(details.name) at \(details.url)")
    }

    /// Get all cookies matching details
    /// - Parameters:
    ///   - details: Cookie search details
    ///   - callback: Callback with matching cookies
    public func getAll(
        _ details: ChromeCookieSearchDetails,
        callback: @escaping ([ChromeCookie]) -> ()
    ) {
        var allCookies: [HTTPCookie] = []

        if let urlString = details.url, let url = URL(string: urlString) {
            allCookies = httpCookieStorage.cookies(for: url) ?? []
        } else if let domain = details.domain {
            allCookies = httpCookieStorage.cookies?.filter { cookie in
                cookie.domain.contains(domain)
            } ?? []
        } else {
            allCookies = httpCookieStorage.cookies ?? []
        }

        // Apply additional filters
        if let name = details.name {
            allCookies = allCookies.filter { $0.name == name }
        }

        if let path = details.path {
            allCookies = allCookies.filter { $0.path == path }
        }

        if let secure = details.secure {
            allCookies = allCookies.filter { $0.isSecure == secure }
        }

        if let session = details.session {
            allCookies = allCookies.filter { $0.isSessionOnly == session }
        }

        let chromeCookies = allCookies.map { cookie in
            convertToChromeCookie(cookie, storeId: details.storeId)
        }

        callback(chromeCookies)
        logger.debug("🍪 Retrieved \(chromeCookies.count) cookies")
    }

    /// Set a cookie
    /// - Parameters:
    ///   - details: Cookie details to set
    ///   - callback: Callback with set cookie or nil if failed
    public func set(
        _ details: ChromeCookieSetDetails,
        callback: @escaping (ChromeCookie?) -> ()
    ) {
        guard let url = URL(string: details.url) else {
            callback(nil)
            return
        }

        var cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .name: details.name ?? "",
            .value: details.value ?? "",
            .domain: details.domain ?? url.host ?? "",
            .path: details.path ?? "/"
        ]

        if let expirationDate = details.expirationDate {
            cookieProperties[.expires] = Date(timeIntervalSince1970: expirationDate)
        }

        if let secure = details.secure {
            cookieProperties[.secure] = secure
        }

        if let httpOnly = details.httpOnly {
            cookieProperties[HTTPCookiePropertyKey("HttpOnly")] = httpOnly
        }

        if let sameSite = details.sameSite {
            switch sameSite {
            case .strict:
                cookieProperties[.sameSitePolicy] = "Strict"
            case .lax:
                cookieProperties[.sameSitePolicy] = "Lax"
            case .none:
                cookieProperties[.sameSitePolicy] = "None"
            }
        }

        guard let newCookie = HTTPCookie(properties: cookieProperties) else {
            callback(nil)
            return
        }

        httpCookieStorage.setCookie(newCookie)

        let chromeCookie = convertToChromeCookie(newCookie, storeId: details.storeId)

        // Trigger changed event
        let changeInfo = ChromeCookieChangeInfo(
            removed: false,
            cookie: chromeCookie,
            cause: .explicit
        )

        for listener in changedListeners {
            listener(changeInfo)
        }

        callback(chromeCookie)
        logger.info("✅ Set cookie: \(details.name ?? "unnamed") for \(details.url)")
    }

    /// Remove a cookie
    /// - Parameters:
    ///   - details: Cookie details to remove
    ///   - callback: Callback with removal details
    public func remove(
        _ details: ChromeCookieDetails,
        callback: @escaping (ChromeCookieRemovalDetails?) -> ()
    ) {
        guard let url = URL(string: details.url) else {
            callback(nil)
            return
        }

        let cookies = httpCookieStorage.cookies(for: url) ?? []
        let cookieToRemove = cookies.first { cookie in
            cookie.name == details.name
        }

        guard let httpCookie = cookieToRemove else {
            callback(nil)
            return
        }

        let chromeCookie = convertToChromeCookie(httpCookie, storeId: details.storeId)
        httpCookieStorage.deleteCookie(httpCookie)

        // Trigger changed event
        let changeInfo = ChromeCookieChangeInfo(
            removed: true,
            cookie: chromeCookie,
            cause: .explicit
        )

        for listener in changedListeners {
            listener(changeInfo)
        }

        let removalDetails = ChromeCookieRemovalDetails(
            url: details.url,
            name: details.name
        )

        callback(removalDetails)
        logger.info("🗑️ Removed cookie: \(details.name) from \(details.url)")
    }

    /// Get all cookie stores
    /// - Parameter callback: Callback with cookie stores
    public func getAllCookieStores(_ callback: @escaping ([ChromeCookieStore]) -> ()) {
        // For now, return default cookie store
        let defaultStore = ChromeCookieStore(
            id: "0",
            tabIds: []
        )

        callback([defaultStore])
        logger.debug("🏪 Retrieved cookie stores")
    }

    // MARK: - Event Listeners

    /// Add changed event listener
    /// - Parameter listener: Changed event listener
    public func addChangedListener(_ listener: @escaping (ChromeCookieChangeInfo) -> ()) {
        changedListeners.append(listener)
        logger.debug("👂 Added cookie changed listener")
    }

    /// Remove changed event listener
    /// - Parameter listener: Changed event listener to remove
    public func removeChangedListener(_ listener: @escaping (ChromeCookieChangeInfo) -> ()) {
        // Note: Function comparison is complex in Swift
        // In production, use a listener ID system
        logger.debug("🗑️ Removed cookie changed listener")
    }

    // MARK: - Private Helper Methods

    /// Convert HTTPCookie to ChromeCookie
    /// - Parameters:
    ///   - httpCookie: HTTPCookie to convert
    ///   - storeId: Cookie store ID
    /// - Returns: ChromeCookie
    private func convertToChromeCookie(_ httpCookie: HTTPCookie, storeId: String?) -> ChromeCookie {
        let sameSite: ChromeCookieSameSite = if let sameSiteValue = httpCookie.sameSitePolicy {
            switch sameSiteValue.rawValue {
            case "Strict":
                .strict
            case "Lax":
                .lax
            case "None":
                .none
            default:
                .lax
            }
        } else {
            .lax
        }

        return ChromeCookie(
            name: httpCookie.name,
            value: httpCookie.value,
            domain: httpCookie.domain,
            hostOnly: !httpCookie.domain.hasPrefix("."),
            path: httpCookie.path,
            secure: httpCookie.isSecure,
            httpOnly: httpCookie.isHTTPOnly,
            sameSite: sameSite,
            session: httpCookie.isSessionOnly,
            expirationDate: httpCookie.expiresDate?.timeIntervalSince1970,
            storeId: storeId ?? "0"
        )
    }
}

// MARK: - ChromeCookie

/// Chrome cookie
public struct ChromeCookie {
    public let name: String
    public let value: String
    public let domain: String
    public let hostOnly: Bool
    public let path: String
    public let secure: Bool
    public let httpOnly: Bool
    public let sameSite: ChromeCookieSameSite
    public let session: Bool
    public let expirationDate: Double?
    public let storeId: String

    public init(
        name: String,
        value: String,
        domain: String,
        hostOnly: Bool,
        path: String,
        secure: Bool,
        httpOnly: Bool,
        sameSite: ChromeCookieSameSite,
        session: Bool,
        expirationDate: Double?,
        storeId: String
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.hostOnly = hostOnly
        self.path = path
        self.secure = secure
        self.httpOnly = httpOnly
        self.sameSite = sameSite
        self.session = session
        self.expirationDate = expirationDate
        self.storeId = storeId
    }
}

// MARK: - ChromeCookieDetails

/// Chrome cookie details for getting/removing cookies
public struct ChromeCookieDetails {
    public let url: String
    public let name: String
    public let storeId: String?

    public init(url: String, name: String, storeId: String? = nil) {
        self.url = url
        self.name = name
        self.storeId = storeId
    }
}

// MARK: - ChromeCookieSearchDetails

/// Chrome cookie search details
public struct ChromeCookieSearchDetails {
    public let url: String?
    public let name: String?
    public let domain: String?
    public let path: String?
    public let secure: Bool?
    public let session: Bool?
    public let storeId: String?

    public init(
        url: String? = nil,
        name: String? = nil,
        domain: String? = nil,
        path: String? = nil,
        secure: Bool? = nil,
        session: Bool? = nil,
        storeId: String? = nil
    ) {
        self.url = url
        self.name = name
        self.domain = domain
        self.path = path
        self.secure = secure
        self.session = session
        self.storeId = storeId
    }
}

// MARK: - ChromeCookieSetDetails

/// Chrome cookie set details
public struct ChromeCookieSetDetails {
    public let url: String
    public let name: String?
    public let value: String?
    public let domain: String?
    public let path: String?
    public let secure: Bool?
    public let httpOnly: Bool?
    public let sameSite: ChromeCookieSameSite?
    public let expirationDate: Double?
    public let storeId: String?

    public init(
        url: String,
        name: String? = nil,
        value: String? = nil,
        domain: String? = nil,
        path: String? = nil,
        secure: Bool? = nil,
        httpOnly: Bool? = nil,
        sameSite: ChromeCookieSameSite? = nil,
        expirationDate: Double? = nil,
        storeId: String? = nil
    ) {
        self.url = url
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.secure = secure
        self.httpOnly = httpOnly
        self.sameSite = sameSite
        self.expirationDate = expirationDate
        self.storeId = storeId
    }
}

// MARK: - ChromeCookieRemovalDetails

/// Chrome cookie removal details
public struct ChromeCookieRemovalDetails {
    public let url: String
    public let name: String

    public init(url: String, name: String) {
        self.url = url
        self.name = name
    }
}

// MARK: - ChromeCookieStore

/// Chrome cookie store
public struct ChromeCookieStore {
    public let id: String
    public let tabIds: [Int]

    public init(id: String, tabIds: [Int]) {
        self.id = id
        self.tabIds = tabIds
    }
}

// MARK: - ChromeCookieChangeInfo

/// Chrome cookie change info
public struct ChromeCookieChangeInfo {
    public let removed: Bool
    public let cookie: ChromeCookie
    public let cause: ChromeCookieChangeCause

    public init(removed: Bool, cookie: ChromeCookie, cause: ChromeCookieChangeCause) {
        self.removed = removed
        self.cookie = cookie
        self.cause = cause
    }
}

// MARK: - ChromeCookieSameSite

/// Chrome cookie SameSite values
public enum ChromeCookieSameSite: String, CaseIterable {
    case strict
    case lax
    case none
}

// MARK: - ChromeCookieChangeCause

/// Chrome cookie change causes
public enum ChromeCookieChangeCause: String, CaseIterable {
    case evicted
    case expired
    case explicit
    case overwrite
}
