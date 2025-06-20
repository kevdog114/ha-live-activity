import Foundation
import SwiftData
import Combine // Needed if not using @Observable directly for some reason, but @Observable is preferred.

@Observable // Use the new Observable macro
class AppState {
    // MARK: - Published Properties
    var currentConnection: HomeAssistantConnection? {
        didSet {
            if let connection = currentConnection {
                self.apiClient = HomeAssistantAPIClient(connection: connection)
                print("HomeAssistantAPIClient initialized.")
            } else {
                self.apiClient = nil
                print("HomeAssistantAPIClient deinitialized.")
            }
        }
    }
    var apiClient: HomeAssistantAPIClient? // Make this accessible
    var isLoading: Bool = false
    var connectionError: HAErrors?

    // MARK: - Initialization
    init() {
        // Initial apiClient will be nil until a connection is loaded/established
    }

    // MARK: - Connection Management

    @MainActor
    func loadPersistedConnection(context: ModelContext) {
        self.isLoading = true
        self.connectionError = nil
        self.apiClient = nil // Clear previous client while loading

        Task {
            do {
                let descriptor = FetchDescriptor<HomeAssistantConnection>(sortBy: [SortDescriptor(\.lastConnectedAt, order: .reverse)])
                let connections = try context.fetch(descriptor)

                // Deliberately setting currentConnection which will trigger its didSet
                self.currentConnection = connections.first

                if let activeConnection = self.currentConnection {
                    print("Successfully loaded persisted connection: \(activeConnection.instanceName ?? activeConnection.baseURL.absoluteString)")
                } else {
                    print("No persisted connection found.")
                }
            } catch {
                print("Failed to load persisted connection: \(error)")
                self.connectionError = .swiftDataError(error.localizedDescription)
            }
            self.isLoading = false
        }
    }

    @MainActor
    func connect(to instance: DiscoveredInstance, accessToken: String, refreshToken: String? = nil, context: ModelContext) {
        guard let baseURL = instance.baseURL else {
            self.connectionError = .configurationError("Invalid URL for discovered instance.")
            return
        }

        self.isLoading = true
        self.connectionError = nil
        self.apiClient = nil

        Task {
            let predicate = #Predicate<HomeAssistantConnection> { $0.baseURL == baseURL }
            let descriptor = FetchDescriptor(predicate: predicate)
            var connectionToSave: HomeAssistantConnection?

            do {
                let existingConnections = try context.fetch(descriptor)
                if let existing = existingConnections.first {
                    existing.accessToken = accessToken
                    existing.refreshToken = refreshToken
                    existing.instanceName = instance.name
                    existing.lastConnectedAt = Date()
                    connectionToSave = existing
                    print("Updating existing connection: \(instance.name)")
                } else {
                    let newConn = HomeAssistantConnection(
                        baseURL: baseURL,
                        accessToken: accessToken,
                        refreshToken: refreshToken,
                        instanceName: instance.name,
                        lastConnectedAt: Date()
                    )
                    context.insert(newConn)
                    connectionToSave = newConn
                    print("Saving new connection: \(instance.name)")
                }

                try context.save()
                // Set currentConnection which triggers didSet for apiClient
                self.currentConnection = connectionToSave

            } catch {
                print("Failed to save connection: \(error)")
                self.connectionError = .swiftDataError(error.localizedDescription)
            }
            self.isLoading = false
        }
    }

    @MainActor
    func saveConnection(connection: HomeAssistantConnection, context: ModelContext) {
        self.isLoading = true
        self.connectionError = nil
        self.apiClient = nil

        Task {
            connection.lastConnectedAt = Date()
            context.insert(connection) // Assuming it's a new or unmanaged object to be inserted/updated.
                                    // If 'connection' is already managed, this might not be necessary,
                                    // and context.save() would suffice if its properties changed.
            do {
                try context.save()
                // Set currentConnection which triggers didSet for apiClient
                self.currentConnection = connection
                print("Successfully saved connection: \(connection.instanceName ?? connection.baseURL.absoluteString)")
            } catch {
                print("Failed to save connection: \(error)")
                self.connectionError = .swiftDataError(error.localizedDescription)
            }
            self.isLoading = false
        }
    }

    @MainActor
    func disconnect(context: ModelContext) {
        self.isLoading = true // Optional: indicate loading state during disconnect
        Task {
            if let conn = self.currentConnection {
                 print("Disconnected from \(conn.instanceName ?? conn.baseURL.absoluteString)")
                // Optionally update the connection in SwiftData, e.g., clear lastConnectedAt or a flag.
                // For now, just clearing the session:
            }
            // Clear currentConnection, which triggers didSet for apiClient
            self.currentConnection = nil
            self.isLoading = false
        }
    }
}
