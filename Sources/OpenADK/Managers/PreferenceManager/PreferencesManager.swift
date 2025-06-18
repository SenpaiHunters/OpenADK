//

import Combine
import Observation
import SwiftUI

@Observable
public class PreferencesManager {
    static let shared = PreferencesManager()

    // Use instance variable instead of static
    @UserDefault(key: "colorScheme", defaultValue: "dark")
    @ObservationIgnored var storedColorScheme: String

    @UserDefault(key: "colorScheme", defaultValue: "brave")
    @ObservationIgnored var storedSearchEngine: String

    /// Publicly avalable and observed version of Preferences
    var colorScheme: ColorScheme?
    var searchEngine: SearchEngines?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        colorScheme = getScheme(from: storedColorScheme)
        searchEngine = getSearchEngine(string: storedSearchEngine)

        $storedColorScheme.sink { [weak self] newValue in
            self?.colorScheme = self?.getScheme(from: newValue)
        }
        .store(in: &cancellables)

        $storedSearchEngine.sink { [weak self] newValue in
            self?.searchEngine = self?.getSearchEngine(string: newValue)
        }
        .store(in: &cancellables)
    }

    func getScheme(from string: String) -> ColorScheme? {
        switch string {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    func getSearchEngine(string: String) -> SearchEngines {
        switch string {
        case "google": .google
        case "duckduckgo": .duckduckgo
        case "brave": .brave
        default: .google
        }
    }
}

enum SearchEngines {
    case google, duckduckgo, brave
}
