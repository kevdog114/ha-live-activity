import Foundation
import SwiftData

@Model
final class HomeAssistantConnection {
    @Attribute(.unique) var id: UUID
    var baseURL: URL
    var accessToken: String
    var refreshToken: String? // Optional, as not all auth methods might use it initially
    var instanceName: String? // Optional, user-friendly name
    var lastConnectedAt: Date? // To track when this connection was last used

    init(id: UUID = UUID(), baseURL: URL, accessToken: String, refreshToken: String? = nil, instanceName: String? = nil, lastConnectedAt: Date? = nil) {
        self.id = id
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.instanceName = instanceName
        self.lastConnectedAt = lastConnectedAt
    }
}
