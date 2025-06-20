import Foundation

struct DiscoveredInstance: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let host: String // e.g., "192.168.1.10"
    let port: Int    // e.g., 8123
    var url: URL? {
        URL(string: "http://\(host):\(port)")
    }

    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(host)
        hasher.combine(port)
    }

    // Implement Equatable
    static func == (lhs: DiscoveredInstance, rhs: DiscoveredInstance) -> Bool {
        lhs.name == rhs.name && lhs.host == rhs.host && lhs.port == rhs.port
    }
}
