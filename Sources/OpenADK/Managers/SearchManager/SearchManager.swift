import Foundation
import Observation



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
        case bookmark = "bookmark"
    }
}

// MARK: - SearchHistoryItem

/// Represents a search history item
public struct SearchHistoryItem: Identifiable, Codable, Hashable {
    public  let id: UUID
    public let query: String
    public let timestamp: Date
    public  let searchEngine: SearchEngine

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
    private let maxSuggestions = 10

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
    public  var homePageURL: String {
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
        suggestions = []
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
        // First check if it's already a complete URL
        if let url = URL(string: string),
           let scheme = url.scheme,
           ["http", "https", "file", "ftp"].contains(scheme.lowercased()) {
            return true
        }

        // Check for common domain patterns without protocol
        let domainPatterns = [
            #"^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+(/.*)?$"#, // Standard domain
            #"^localhost(:[0-9]+)?(/.*)?$"#, // Localhost
            #"^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(:[0-9]+)?(/.*)?$"# // IP address
        ]

        for pattern in domainPatterns {
            let regex = try? NSRegularExpression(pattern: pattern)
            let range = NSRange(string.startIndex ..< string.endIndex, in: string)
            if regex?.firstMatch(in: string, options: [], range: range) != nil {
                return true
            }
        }

        return false
    }
    
    // MARK: - Private Methods

    /// Normalizes a URL by adding protocol if missing
    private func normalizeURL(_ string: String) -> String {
        if string.hasPrefix("http://") || string.hasPrefix("https://") || string.hasPrefix("file://") {
            return string
        }

        // Add https:// for domain-like strings
        if isValidURL(string) {
            return "https://" + string
        }

        return string
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
              let url = URL(string: baseURL + encodedQuery) else {
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

                self.suggestions = Array(uniqueSuggestions.prefix(maxSuggestions))
            }
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
            if let json = json {
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
                        if let json = json {
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
              let suggestions = json[1] as? [String] else {
            return []
        }

        return suggestions.prefix(5).map {
            var isURL = isValidURL($0)
            return SearchSuggestion(text: $0, type: isURL ? .url : .query)
        }
    }

    /// Parses DuckDuckGo suggestions (JSON array format)
    private func parseDuckDuckGoSuggestions(from data: Data) throws -> [SearchSuggestion] {
        // Ensure data is properly encoded as UTF-8
        guard let jsonString = String(data: data, encoding: .utf8),
              let jsonData = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return []
        }

        return json.compactMap { item in
            guard let phrase = item["phrase"] as? String else { return nil }
            var isURL = isValidURL(phrase)

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
              let searchSuggestions = firstGroup["searchSuggestions"] as? [[String: Any]] else {
            return []
        }

        return searchSuggestions.compactMap { item in
            guard let query = item["query"] as? String else { return nil }
            var isURL = isValidURL(query)

            return SearchSuggestion(text: query, type: isURL ? .url : .query)
        }.prefix(5).map(\.self)
    }

    // MARK: - Persistence

    /// Loads search history from UserDefaults
    private func loadSearchHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([SearchHistoryItem].self, from: data) else {
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

