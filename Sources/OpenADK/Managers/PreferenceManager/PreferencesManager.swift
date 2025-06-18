//



import SwiftUI
import Observation
import Combine


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
        self.colorScheme = self.getScheme(from: self.storedColorScheme)
        self.searchEngine = getSearchEngine(string: self.storedSearchEngine)
        
        self.$storedColorScheme.sink { [weak self] newValue in
            self?.colorScheme = self?.getScheme(from: newValue)
        }
        .store(in: &cancellables)
        
        self.$storedSearchEngine.sink { [weak self] newValue in
            self?.searchEngine = self?.getSearchEngine(string: newValue)
        }
        .store(in: &cancellables)
        
    }

    func getScheme(from string: String) -> ColorScheme? {
        switch string {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
    
    func getSearchEngine(string: String) -> SearchEngines {
        switch string {
        case "google": return .google
        case "duckduckgo": return .duckduckgo
        case "brave": return .brave
        default: return .google
        }
    }
}


enum SearchEngines {
    case google, duckduckgo, brave
}
