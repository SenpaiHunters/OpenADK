//
//  SearchManager.swift
//  OpenADK
//
//  Created by StudioMovieGirl
//

import Foundation
import Observation
import SwiftUI

// MARK: - SearchEngine

/// Supported search engines
public enum SearchEngine: String, CaseIterable, Identifiable {
    case brave
    case duckduckgo
    case google
    case bing
    case yahoo
    case startpage
    case searx
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .brave: "Brave Search"
        case .duckduckgo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .yahoo: "Yahoo"
        case .startpage: "Startpage"
        case .searx: "SearX"
        case .none: "Default (Google)"
        }
    }

    public var iconName: String {
        switch self {
        case .brave: "shield.fill"
        case .duckduckgo: "eye.slash.fill"
        case .google: "magnifyingglass"
        case .bing: "b.square.fill"
        case .yahoo: "y.square.fill"
        case .startpage: "lock.shield.fill"
        case .searx: "server.rack"
        case .none: "questionmark.square.fill"
        }
    }
}

// MARK: - SearchSuggestion

/// Represents a search suggestion
public struct SearchSuggestion: Identifiable, Hashable {
    public let id = UUID()
    public let text: String
    public let type: SuggestionType

//    Also provieds an SF Symbol for the type
    public enum SuggestionType: String {
        case history = "clock.arrow.circlepath"
        case query = "magnifyingglass"
        case url = "globe"
        case bookmark
    }
}

// MARK: - SearchHistoryItem

/// Represents a search history item
public struct SearchHistoryItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public let query: String
    public let timestamp: Date
    public let searchEngine: SearchEngine

    public init(query: String, searchEngine: SearchEngine) {
        id = UUID()
        self.query = query
        self.searchEngine = searchEngine
        timestamp = Date()
    }

    // Custom coding keys to handle SearchEngine encoding/decoding
    public enum CodingKeys: String, CodingKey {
        case id
        case query
        case timestamp
        case searchEngine
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        query = try container.decode(String.self, forKey: .query)
        timestamp = try container.decode(Date.self, forKey: .timestamp)

        // Handle SearchEngine decoding with fallback
        if let searchEngineRawValue = try? container.decode(String.self, forKey: .searchEngine),
           let decodedSearchEngine = SearchEngine(rawValue: searchEngineRawValue) {
            searchEngine = decodedSearchEngine
        } else {
            searchEngine = .google // Default fallback
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(query, forKey: .query)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(searchEngine.rawValue, forKey: .searchEngine)
    }
}

// MARK: - SearchManager

/// Dedicated manager for handling search engine functionality
@Observable
@MainActor
public class SearchManager {
    public static let shared = SearchManager()

    // MARK: - Properties

    /// Current search suggestions
    public var suggestions: [SearchSuggestion] = []

    /// Search history (limited to recent items)
    private(set) var searchHistory: [SearchHistoryItem] = []

    /// Maximum number of history items to keep
    private let maxHistoryItems = 100

    /// Maximum number of suggestions to show
    private let maxSuggestions = 5

    /// UserDefaults key for search history
    private let historyKey = "SearchHistory"

    /// Current search task for cancellation
    private var suggestionTask: Task<(), Never>?

    // MARK: - Initialization

    private init() {
        loadSearchHistory()
    }

    // MARK: - Search Engine URLs

    /// Returns the appropriate search engine URL based on user preferences
    public var searchEngineURL: String {
        switch PreferencesManager.shared.searchEngine {
        case .brave:
            "https://search.brave.com/search?q="
        case .duckduckgo:
            "https://duckduckgo.com/?q="
        case .google:
            "https://www.google.com/search?q="
        case .bing:
            "https://www.bing.com/search?q="
        case .yahoo:
            "https://search.yahoo.com/search?p="
        case .startpage:
            "https://www.startpage.com/sp/search?query="
        case .searx:
            "https://searx.org/?q="
        case .none:
            "https://www.google.com/search?q="
        }
    }

    /// Returns the home page URL for the search engine
    public var homePageURL: String {
        switch PreferencesManager.shared.searchEngine {
        case .brave:
            "https://search.brave.com/"
        case .duckduckgo:
            "https://duckduckgo.com/"
        case .google:
            "https://www.google.com/"
        case .bing:
            "https://www.bing.com/"
        case .yahoo:
            "https://www.yahoo.com/"
        case .startpage:
            "https://www.startpage.com/"
        case .searx:
            "https://searx.org/"
        case .none:
            "https://www.google.com/"
        }
    }

    /// Returns the suggestions API URL for the current search engine
    private var suggestionsURL: String? {
        switch PreferencesManager.shared.searchEngine {
        case .google,
             .none:
            "https://suggestqueries.google.com/complete/search?client=firefox&q="
        case .duckduckgo:
            "https://duckduckgo.com/ac/?q="
        case .bing:
            "https://www.bing.com/AS/Suggestions?pt=page.home&mkt=en-us&qry="
        default:
            nil // Some engines don't support suggestions API
        }
    }

    // MARK: - Public Methods

    /// Constructs a search URL for the given query
    public func searchURL(for query: String) -> String {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return homePageURL
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if the query is already a URL
        if isValidURL(trimmedQuery) {
            return normalizeURL(trimmedQuery)
        }

        // Add to search history
        addToHistory(query: trimmedQuery)

        // Encode the query for URL safety
        let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedQuery
        return searchEngineURL + encodedQuery
    }

    /// Fetches search suggestions for the given query
    public func fetchSuggestions(for query: String) {
        // Cancel previous task
        suggestionTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            suggestions = []
            return
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Start with history-based suggestions
        let historySuggestions = getHistorySuggestions(for: trimmedQuery)
        suggestions = historySuggestions

        // Fetch online suggestions if available
        guard let suggestionsURLString = suggestionsURL else { return }

        suggestionTask = Task {
            await fetchOnlineSuggestions(for: trimmedQuery, baseURL: suggestionsURLString)
        }
    }

    /// Clears all search suggestions
    public func clearSuggestions() {
        suggestionTask?.cancel()
        withAnimation {
            suggestions = []
        }
    }

    /// Clears search history
    public func clearHistory() {
        searchHistory.removeAll()
        saveSearchHistory()
    }

    /// Removes a specific item from search history
    public func removeFromHistory(_ item: SearchHistoryItem) {
        searchHistory.removeAll { $0.id == item.id }
        saveSearchHistory()
    }

    /// Returns recent search queries
    public func getRecentSearches(limit: Int = 10) -> [String] {
        Array(searchHistory.prefix(limit).map(\.query))
    }

    /// Checks if search suggestions are supported for current engine
    public var supportsSuggestions: Bool {
        suggestionsURL != nil
    }

    /// Checks if a string is a valid URL
    public func isValidURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject empty strings or strings with spaces
        if trimmed.isEmpty || trimmed.contains(" ") {
            return false
        }

        // First check if it's already a complete URL with scheme
        if let url = URL(string: trimmed),
           let scheme = url.scheme,
           ["http", "https", "file", "ftp"].contains(scheme.lowercased()),
           let host = url.host,
           !host.isEmpty {
            return true
        }

        // For strings without scheme, validate as domain-like patterns
        return isValidDomainPattern(trimmed)
    }

    /// Normalizes a URL by adding protocol if missing
    public func normalizeURL(_ string: String) -> String {
        if string.hasPrefix("http://") || string.hasPrefix("https://") || string.hasPrefix("file://") {
            return string
        }

        // Add https:// for domain-like strings
        if isValidURL(string) {
            return "https://" + string
        }

        return string
    }

    // MARK: - Private Methods

    /// Validates whether a string matches a valid domain pattern.
    ///
    /// This method checks if the input string represents a valid domain pattern,
    /// including localhost addresses, IP addresses, and domain names.
    ///
    /// - Parameter string: The string to validate as a domain pattern
    /// - Returns: `true` if the string is a valid domain pattern, `false` otherwise
    ///
    /// ## Supported Patterns
    /// - Localhost: `localhost`, `localhost:8080`, `localhost/path`
    /// - IP addresses: `192.168.1.1`, `10.0.0.1:3000`
    /// - Domain names: `example.com`, `subdomain.example.org:8080`
    private func isValidDomainPattern(_ string: String) -> Bool {
        // Handle localhost case
        if string.hasPrefix("localhost") {
            let remainder = String(string.dropFirst(9)) // "localhost".count = 9
            return remainder.isEmpty || remainder.hasPrefix(":") || remainder.hasPrefix("/")
        }

        // Handle IP addresses
        if isValidIPAddress(string) {
            return true
        }

        // Handle domain names
        return isValidDomainName(string)
    }

    /// Validates whether a string represents a valid IPv4 address.
    ///
    /// This method checks if the input string is a properly formatted IPv4 address,
    /// optionally including a port number and/or path.
    ///
    /// - Parameter string: The string to validate as an IP address
    /// - Returns: `true` if the string is a valid IPv4 address, `false` otherwise
    ///
    /// ## Supported Formats
    /// - Basic IP: `192.168.1.1`
    /// - IP with port: `192.168.1.1:8080`
    /// - IP with path: `192.168.1.1/path`
    /// - IP with port and path: `192.168.1.1:8080/path`
    ///
    /// ## Validation Rules
    /// - Each octet must be between 0-255
    /// - No leading zeros allowed (except for "0" itself)
    /// - Port numbers must be between 1-65535
    private func isValidIPAddress(_ string: String) -> Bool {
        // Split by '/' to separate IP from path
        let components = string.components(separatedBy: "/")
        let ipPart = components[0]

        // Split by ':' to separate IP from port
        let ipPortComponents = ipPart.components(separatedBy: ":")
        let ipOnly = ipPortComponents[0]

        // Validate port if present
        if ipPortComponents.count == 2 {
            guard let port = Int(ipPortComponents[1]), port > 0, port <= 65535 else {
                return false
            }
        } else if ipPortComponents.count > 2 {
            return false
        }

        // Validate IP address format
        let octets = ipOnly.components(separatedBy: ".")
        guard octets.count == 4 else { return false }

        for octet in octets {
            guard let num = Int(octet), num >= 0, num <= 255 else {
                return false
            }
            // Reject leading zeros (except for "0" itself)
            if octet.count > 1, octet.hasPrefix("0") {
                return false
            }
        }

        return true
    }

    /// Validates whether a string represents a valid domain name.
    ///
    /// This method checks if the input string is a properly formatted domain name,
    /// optionally including a port number and/or path.
    ///
    /// - Parameter string: The string to validate as a domain name
    /// - Returns: `true` if the string is a valid domain name, `false` otherwise
    ///
    /// ## Supported Formats
    /// - Basic domain: `example.com`
    /// - Subdomain: `subdomain.example.com`
    /// - Domain with port: `example.com:8080`
    /// - Domain with path: `example.com/path`
    /// - Domain with port and path: `example.com:8080/path`
    ///
    /// ## Validation Rules
    /// - Must contain at least one dot
    /// - Must have at least 2 parts when split by dots
    /// - Each domain part must be valid (no empty parts, proper characters)
    /// - Top-level domain must be at least 2 characters and contain only letters
    /// - Port numbers must be between 1-65535
    private func isValidDomainName(_ string: String) -> Bool {
        // Split by '/' to separate domain from path
        let components = string.components(separatedBy: "/")
        let domainPart = components[0]

        // Split by ':' to separate domain from port
        let domainPortComponents = domainPart.components(separatedBy: ":")
        let domainOnly = domainPortComponents[0]

        // Validate port if present
        if domainPortComponents.count == 2 {
            guard let port = Int(domainPortComponents[1]), port > 0, port <= 65535 else {
                return false
            }
        } else if domainPortComponents.count > 2 {
            return false
        }

        // Domain must contain at least one dot
        guard domainOnly.contains(".") else { return false }

        let parts = domainOnly.components(separatedBy: ".")
        guard parts.count >= 2 else { return false }

        // Validate each part of the domain
        for part in parts {
            if !isValidDomainPart(part) {
                return false
            }
        }

        // Last part (TLD) must be at least 2 characters and all letters
        let tld = parts.last!
        guard tld.count >= 2, tld.allSatisfy(\.isLetter) else {
            return false
        }

        return true
    }

    /// Validates whether a string represents a valid domain name part.
    ///
    /// This method checks if a single part of a domain name (separated by dots)
    /// follows proper domain naming conventions.
    ///
    /// - Parameter part: The domain part to validate
    /// - Returns: `true` if the part is valid, `false` otherwise
    ///
    /// ## Validation Rules
    /// - Cannot be empty
    /// - Cannot start or end with a hyphen
    /// - Can only contain alphanumeric characters and hyphens
    /// - Must follow RFC 1123 hostname conventions
    ///
    /// ## Examples
    /// - Valid: `example`, `sub-domain`, `test123`
    /// - Invalid: ``, `-invalid`, `invalid-`, `invalid_part`
    private func isValidDomainPart(_ part: String) -> Bool {
        // Domain parts can't be empty
        guard !part.isEmpty else { return false }

        // Can't start or end with hyphen
        if part.hasPrefix("-") || part.hasSuffix("-") {
            return false
        }

        // Must contain only alphanumeric characters and hyphens
        return part.allSatisfy { char in
            char.isLetter || char.isNumber || char == "-"
        }
    }

    /// Adds a query to search history
    private func addToHistory(query: String) {
        // Don't add if it's already the most recent search
        if let lastSearch = searchHistory.first, lastSearch.query == query {
            return
        }

        // Remove existing instances of this query
        searchHistory.removeAll { $0.query == query }

        // Add to beginning
        let historyItem = SearchHistoryItem(query: query, searchEngine: PreferencesManager.shared.searchEngine)
        searchHistory.insert(historyItem, at: 0)

        // Limit history size
        if searchHistory.count > maxHistoryItems {
            searchHistory = Array(searchHistory.prefix(maxHistoryItems))
        }

        saveSearchHistory()
    }

    /// Gets history-based suggestions for a query
    private func getHistorySuggestions(for query: String) -> [SearchSuggestion] {
        let lowercaseQuery = query.lowercased()

        return searchHistory
            .filter { $0.query.lowercased().contains(lowercaseQuery) && $0.query != query }
            .prefix(5)
            .map { SearchSuggestion(text: $0.query, type: .history) }
    }

    /// Fetches online suggestions from search engine
    private func fetchOnlineSuggestions(for query: String, baseURL: String) async {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: baseURL + encodedQuery)
        else {
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            // Parse suggestions based on search engine
            let onlineSuggestions = try parseSuggestions(from: data, for: PreferencesManager.shared.searchEngine)

            // Combine with existing history suggestions
            await MainActor.run {
                let historySuggestions = getHistorySuggestions(for: query)
                let combinedSuggestions = historySuggestions + onlineSuggestions

                // Remove duplicates and limit
                var uniqueSuggestions: [SearchSuggestion] = []
                var seenTexts: Set<String> = []

                for suggestion in combinedSuggestions {
                    if !seenTexts.contains(suggestion.text.lowercased()) {
                        uniqueSuggestions.append(suggestion)
                        seenTexts.insert(suggestion.text.lowercased())
                    }
                }

                withAnimation {
                    self.suggestions = Array(uniqueSuggestions.prefix(maxSuggestions))
                }
            }
        } catch URLError.cancelled {
            // Task gets canceled, no need to log the error because
            // it's not really an error.
        } catch {
            // Silently fail - suggestions are optional
            print("Failed to fetch suggestions: \(error)")
        }
    }

    /// Parses suggestions from API response
    private func parseSuggestions(from data: Data, for engine: SearchEngine) throws -> [SearchSuggestion] {
        switch engine {
        case .google,
             .none:
            try parseGoogleSuggestions(from: data)
        case .duckduckgo:
            try parseDuckDuckGoSuggestions(from: data)
        case .bing:
            try parseBingSuggestions(from: data)
        default:
            []
        }
    }

    /// Parses Google-style suggestions (JSON array format)
    private func parseGoogleSuggestions(from data: Data) throws -> [SearchSuggestion] {
        // Try direct JSON parsing first, then fallback to string conversion if needed
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [Any]
            if let json {
                return try parseGoogleJSON(json)
            }
        } catch {
            // Fallback: try different encodings
            let encodings: [String.Encoding] = [.utf8, .ascii, .isoLatin1, .windowsCP1252]
            for encoding in encodings {
                if let jsonString = String(data: data, encoding: encoding),
                   let jsonData = jsonString.data(using: .utf8) {
                    do {
                        let json = try JSONSerialization.jsonObject(with: jsonData) as? [Any]
                        if let json {
                            return try parseGoogleJSON(json)
                        }
                    } catch {
                        continue
                    }
                }
            }
        }

        return []
    }

    private func parseGoogleJSON(_ json: [Any]) throws -> [SearchSuggestion] {
        guard json.count > 1,
              let suggestions = json[1] as? [String]
        else {
            return []
        }

        return suggestions.prefix(5).map {
            let isURL = isValidURL($0)
            return SearchSuggestion(text: $0, type: isURL ? .url : .query)
        }
    }

    /// Parses DuckDuckGo suggestions (JSON array format)
    private func parseDuckDuckGoSuggestions(from data: Data) throws -> [SearchSuggestion] {
        // Ensure data is properly encoded as UTF-8
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]]
        else {
            return []
        }

        return json.compactMap { item in
            guard let phrase = item["phrase"] as? String else { return nil }
            let isURL = isValidURL(phrase)

            return SearchSuggestion(text: phrase, type: isURL ? .url : .query)
        }.prefix(5).map(\.self)
    }

    /// Parses Bing suggestions (JSON object format)
    private func parseBingSuggestions(from data: Data) throws -> [SearchSuggestion] {
        // Ensure data is properly encoded as UTF-8
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let suggestionGroups = json["suggestionGroups"] as? [[String: Any]],
              let firstGroup = suggestionGroups.first,
              let searchSuggestions = firstGroup["searchSuggestions"] as? [[String: Any]]
        else {
            return []
        }

        return searchSuggestions.compactMap { item in
            guard let query = item["query"] as? String else { return nil }
            let isURL = isValidURL(query)

            return SearchSuggestion(text: query, type: isURL ? .url : .query)
        }.prefix(5).map(\.self)
    }

    // MARK: - Persistence

    /// Loads search history from UserDefaults
    private func loadSearchHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([SearchHistoryItem].self, from: data)
        else {
            return
        }

        searchHistory = history
    }

    /// Saves search history to UserDefaults
    private func saveSearchHistory() {
        guard let data = try? JSONEncoder().encode(searchHistory) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}

// MARK: - Extensions

public extension SearchManager {
    /// Returns popular search engines for selection
    static var popularSearchEngines: [SearchEngine] {
        [.google, .duckduckgo, .brave, .bing, .startpage]
    }

    /// Returns privacy-focused search engines
    static var privacySearchEngines: [SearchEngine] {
        [.duckduckgo, .brave, .startpage, .searx]
    }
}
