//

import Observation

// A default space class for use in the browser
@Observable
public class Space: SpaceProtocol {
    public var title: String?
    public var icon: String?

    public var currentTab: (any TabProtocol)? // maybe make this computed in the future

    // var theme: AltoTheme <-- we will add this later

    // var searchEngine: SearchEngine <-- currently this logic is for the entire app so it should be moved here

    // var profile: Profile <-- adding this will be a pain

    public var localLocations: [TabLocation] = [
        TabLocation(name: "pinned"),
        TabLocation(name: "unpinned"),
    ]
}

// If the user wants to add things to spaces they can use the tab protocol
public protocol SpaceProtocol {
    var title: String? { get set }
    var icon: String? { get set }

    var currentTab: (any TabProtocol)? { get set }

    var localLocations: [TabLocation] { get set }
}
