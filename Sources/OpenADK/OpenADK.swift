//
import Observation
import OpenADKObjC
import SwiftUI

public struct AltoConfiguration {
    var name: String?
}

@Observable
public class Alto {
    public static let shared = Alto()

    public let configuration: AltoConfiguration?

    public var tabs: [UUID: any TabProtocol] = [:] // This will need to pull from storage
    public var spaces: [SpaceProtocol] = []
    public var profiles: String?

    public let windowManager: WindowManager
    public let cookieManager: CookiesManager
    public let faviconManager: FaviconManager
    public let contextManager: String?
    public let paswordManager: String? // ToDo
    public let downloadManager: String? // ToDo
    public let modelManager: String? // ToDo (This will be AI intigration for local and cloud based LLMs)
    
    // public let searchManager: SearchManager

    
    private init() {
        configuration = nil

        windowManager = WindowManager()
        cookieManager = CookiesManager()
        contextManager = nil
        paswordManager = nil
        downloadManager = nil
        modelManager = nil
        // searchManager = SearchManager()
        faviconManager = FaviconManager()

        if spaces.isEmpty {
            spaces.append(Space())
        }
    }

    public func getTab(id: UUID) -> (any TabProtocol)? {
        let tab = tabs.first(where: { $0.key == id })?.value
        return tab
    }
}
