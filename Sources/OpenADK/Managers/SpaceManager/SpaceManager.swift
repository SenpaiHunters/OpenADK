//

// MARK: - SpaceManager

public class SpaceManager {
    public var currentSpace: Space?
    private var currentSpaceIndex = 0
    public var spaces: [Space] {
        Alto.shared.spaces
    }

    public init() {}

    public func newSpace(name: String? = nil, profile: Profile? = nil) {
        let profile = profile ?? Alto.shared.profileManager.defaultProfile
        let spaceName = name ?? "Space \(spaces.count)"
        let newSpace = Space(profile: profile, name: spaceName)
        Alto.shared.spaces.append(newSpace)
    }
}
