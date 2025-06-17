//
import OpenADKObjC
import Observation
import SwiftUI

public struct AltoConfiguration {
    var name: String?
}

@Observable
public class Alto {
    public static let shared = Alto()
    
    public let configuration: AltoConfiguration?
    
    public var tabs: [String] = [] // This will need to pull from storage
    
    public let windowManager: WindowManager
    public let cookieManager: CookiesManager
    public let contextManager: String?
    public let paswordManager: String? // ToDo
    public let downloadManager: String? // ToDo
    public let modelManager: String? // ToDo (This will be AI intigration for local and cloud based LLMs)
    public let searchManager: SearchManager
    
    private init() {
        self.configuration = nil
        
        self.windowManager = WindowManager()
        self.cookieManager = CookiesManager()
        self.contextManager = nil
        self.paswordManager = nil
        self.downloadManager = nil
        self.modelManager = nil
        self.searchManager = SearchManager()
    }
}

// Dummy class that is for later
public class AltoTab {
    
    public init() {
        
    }
}
