//
import Observation
import AppKit

@Observable
public class TabLocation: TabLocationProtocol {
    public var name: String
    public var id = UUID()
    public var tabs: [TabRepresentation] = []
    
    init(name: String) {
        self.name = name
    }
    
    public func appendTabRep(_ tabRep: TabRepresentation) {
        self.tabs.append(tabRep)
        let tab = Alto.shared.getTab(id: tabRep.id)
        tab?.location = self
    }
    
    public func removeTab(id: UUID) {
        tabs.removeAll(where: { $0.id == id })
    }
}


public protocol TabLocationProtocol {
    var name: String { get set }
    var id: UUID { get }
    var tabs: [TabRepresentation] { get set }
    
    func appendTabRep(_ tabRep: TabRepresentation)
    
    func removeTab(id: UUID)
}
