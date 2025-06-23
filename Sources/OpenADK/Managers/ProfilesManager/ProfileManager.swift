//

import WebKit


open class DefaultProfileConfig {
    public var isDefault: Bool
    public var searchEngine: SearchEngine
    public var archiveTime: ArchiveTime

    init() {
        self.isDefault = false
        self.searchEngine = .google
        self.archiveTime = .halfDay
    }
}

// MARK: - ProfileManager

/// Handles the storage and data management around creating and loading profiles
open class ProfileManager {
    private let key = "Profiles"
    public var profiles: [Profile] = []
    public var defaultProfile: Profile {
        return profiles.first(where: { $0.isDefault }) ?? profiles[0]
    }
    
    public init() {
        guard let data = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] else {
            print("Failed to pull profile data from userDefaults")

            createNewProfile(name: "normal")
            updateStoredProfiles()
            return
        }
        constructProfile(data: data)
    }
    
    func getProfile(name:String) -> Profile? {
        return profiles.first(where: { $0.name == name })
    }
    
    func setDefault(profile: Profile) {
        // makes all profiles not default then sets the proper one
        for profile in profiles {
            profile.setDefault(false)
        }
        
        profile.setDefault(true)
        updateStoredProfiles()
    }

    func constructProfile(data: [String: [String: String]]) {
        for (key, data) in data {
            if let uuid = UUID(uuidString: key),
               let name = data["name"] {
                guard data["searchEngine"] != nil,
                      data["archiveTime"] != nil,
                      data["isDefault"] != nil else {
                    
                    // Incomplete or invalid profile data — create fresh profile
                    print("Incomplete data for profile named \(name)")
                    
                    let defaultConfig = DefaultProfileConfig()
                    // TODO: This should just retreave it from a default profile
                    let reconstructedData = [
                        "name": name,
                        "isDefault": data["isDefault"] ?? defaultConfig.isDefault.toString(),
                        "searchEngine": data["searchEngine"] ?? defaultConfig.searchEngine.rawValue,
                        "archiveTime": data["searchEngine"] ?? defaultConfig.archiveTime.rawValue
                    ]
                    
                    profiles.append(Profile(id: uuid, data: reconstructedData))
                    continue
                }
                // Safe to create profile
                profiles.append(Profile(id: uuid, data: data))
            } else {
                print("COMPLEAT data Loss for profile with id \(key). Re-initializing profile.")
                createNewProfile(name: "RecoveredProfile-\(key.prefix(4))")
                continue
            }
        }
    }


    func createNewProfile(name: String) {
        if self.getProfile(name:name) == nil {
            let defaultUserData = UserData(searchEngine: .google, archiveTime: .halfDay)
            let profile = Profile(name: name, userData: defaultUserData)
            profile.setDefault(profiles.isEmpty ? true : false)
            
            profiles.append(profile)
            updateStoredProfiles()
            
        } else {
            print("A space with that name already exists")
        }
    }
    
    
    func createNewProfile() {
        let defaultUserData = UserData(searchEngine: .google, archiveTime: .halfDay)
        let profile = Profile(name: "Default Profile", userData: defaultUserData)
        profile.setDefault(profiles.isEmpty ? true : false)
        
        profiles.append(profile)
        updateStoredProfiles()
    }


    func updateStoredProfiles() {
        let data = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id.uuidString, $0.asDictionary) })
        print(data)
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Profile

/// Stores the data and methods to preform relating to a users profile
open class Profile {
    public private(set) var name: String
    public private(set) var id: UUID
    public private(set) var isDefault: Bool
    public private(set) var cookieStore: WKWebsiteDataStore
    private var userData: UserData

    public var asDictionary: [String: String] {
        var data: [String: String] = [
            "name": name,
            "isDefault": isDefault.toString()
        ]

        // this adds the user data to the profile data
        data.merge(userData.asDictionary) { _, new in new }
        return data
    }

    public init(name: String, userData: UserData, isDefault: Bool? = nil) {
        let defaultConfig = DefaultProfileConfig()
        
        self.name = name
        id = UUID()
        cookieStore = WKWebsiteDataStore(forIdentifier: id)
        self.userData = userData
        self.isDefault = isDefault ?? defaultConfig.isDefault
    }

    public init(id: UUID, data: [String: String]) {
        
        self.id = id
        name = data["name"]!
        cookieStore =  WKWebsiteDataStore(forIdentifier: id)
        userData = UserData(data: data)
        isDefault = Bool(string: data["isDefault"]!)
    }
    
    public func setDefault(_ value: Bool) {
        self.isDefault = value
    }
}

// MARK: - UserData

open class UserData {
    private var searchEngine: SearchEngine
    private var archiveTime: ArchiveTime

    public var asDictionary: [String: String] {
        [
            "searchEngine": searchEngine.rawValue,
            "archiveTime": archiveTime.rawValue
        ]
    }

    public init(searchEngine: SearchEngine? = nil, archiveTime: ArchiveTime? = nil) {
        let defaultConfig = DefaultProfileConfig()
        
        self.searchEngine = searchEngine ?? defaultConfig.searchEngine
        self.archiveTime = archiveTime ?? defaultConfig.archiveTime
    }

    public init(data: [String: String]) {
        searchEngine = SearchEngine(rawValue: data["searchEngine"]!)!
        archiveTime = ArchiveTime(rawValue: data["archiveTime"]!)!
    }
}

// MARK: - ArchiveTime

public enum ArchiveTime: String, Codable, CaseIterable {
    case halfDay
    case day
    case week
    case month

    var displayName: String {
        switch self {
        case .halfDay: "12 Hours"
        case .day: "24 Hours"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }
}


extension Bool {
    func toString() -> String {
        if self {
            return "true"
        } else {
            return "false"
        }
    }
    
    init(string: String) {
        let string = string.lowercased()
        if string == "true" {
            self = true
        } else {
            self = false
        }
    }
}
