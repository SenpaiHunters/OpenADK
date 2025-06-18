

internal import Algorithms
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A structure to store the tab data for drag and drop
public struct TabRepresentation: Transferable, Codable, Comparable, Hashable, Identifiable {
    public var id: UUID /// The ID of the tab being represented
    public var containerID: UUID? /// The drop zone: this could be a folder or a place like pinned tabs and favorites
    public var index: Int /// the tabs position in its containers list

    public init(id: UUID, containerID: UUID? = nil, index: Int) {
        self.id = id
        self.containerID = containerID
        self.index = index
    }
    /// tells the struct it should be represented as the custom UTType .tabItem
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tabItem)
    }

    /// allows the tabs to be comparied with eachother based on ID
    public static func < (lhs: TabRepresentation, rhs: TabRepresentation) -> Bool {
        lhs.id == rhs.id
    }

    // this is for the toDrag system if it is needed
    func toItemProvider() -> NSItemProvider {
        print("dragged")
        if let data = try? JSONEncoder().encode(self) {
            return NSItemProvider(item: data as NSData, typeIdentifier: "public.json")
        }

        return NSItemProvider()
    }
}

/// extentds the Unifide type identifier to add the tabItem structure
extension UTType {
    static let tabItem = UTType(exportedAs: "Alto-Browser.Alto.tabItem")
    /// creates a exported type identiffier
}
