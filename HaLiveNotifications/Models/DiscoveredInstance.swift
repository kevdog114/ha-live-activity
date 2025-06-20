import Foundation

struct DiscoveredInstance: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let host: String
    let port: Int

    /// A computed property for the base URL of the instance.
    var baseURL: URL? {
        URL(string: "http://\(host):\(port)")
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(host)
        hasher.combine(port)
    }

    // Equatable conformance for Set uniqueness
    static func == (lhs: DiscoveredInstance, rhs: DiscoveredInstance) -> Bool {
        lhs.host == rhs.host && lhs.port == rhs.port
    }
}
