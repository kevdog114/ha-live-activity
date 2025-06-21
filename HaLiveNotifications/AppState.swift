import Foundation
import SwiftData
import Combine // Needed if not using @Observable directly for some reason, but @Observable is preferred.

@Observable // Use the new Observable macro
class AppState {
    // MARK: - Published Properties
    var currentConnection: HomeAssistantConnection? {
        didSet {
            // The actual initialization of apiClient with modelContext should happen
            // in methods like loadPersistedConnection or saveConnection,
            // or if AppState itself holds a modelContext.
            // This didSet is now more of a notification that the connection changed.
            // The responsibility to set up apiClient correctly with context lies with
            // the methods that change currentConnection and have access to the context.
            if oldValue?.id != currentConnection?.id { // Check if it's truly a different connection
                if currentConnection == nil {
                    self.apiClient = nil
                    print("HomeAssistantAPIClient deinitialized because currentConnection is nil.")
                } else {
                    // If currentConnection is set directly without context (e.g. in tests or future code),
                    // this would be an issue. For now, relying on load/save to set apiClient.
                    print("currentConnection changed. APIClient should be re-initialized with ModelContext by the calling function if not already.")
                }
            }
        }
    }
    var apiClient: HomeAssistantAPIClient? // Make this accessible
    var isLoading: Bool = false
    var connectionError: HAErrors?

    // Properties to hold temporary OAuth state during the flow
    var pendingOAuthState: String?
    var pendingPkceCodeVerifier: String?

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

                let oldConnectionId = self.currentConnection?.id
                self.currentConnection = connections.first // Triggers didSet

                if let activeConnection = self.currentConnection {
                    // Ensure apiClient is updated if the connection actually changed or was nil
                    if oldConnectionId != activeConnection.id || self.apiClient == nil {
                        self.apiClient = HomeAssistantAPIClient(connection: activeConnection, modelContext: context)
                        print("HomeAssistantAPIClient initialized/updated with model context after loading.")
                    }
                    print("Successfully loaded persisted connection: \(activeConnection.instanceName ?? activeConnection.baseURL.absoluteString)")
                } else {
                    self.apiClient = nil // Explicitly nil out if no connection found
                    print("No persisted connection found.")
                }
            } catch {
                print("Failed to load persisted connection: \(error)")
                self.currentConnection = nil // Ensure inconsistent state is cleared
                self.apiClient = nil
                self.connectionError = .swiftDataError(error.localizedDescription)
            }
            self.isLoading = false
        }
    }

    @MainActor
    func saveConnection(connection: HomeAssistantConnection, context: ModelContext) {
        self.isLoading = true
        self.connectionError = nil
        // apiClient will be set after successful save and currentConnection update.

        Task {
            connection.lastConnectedAt = Date()
            // If the connection is not yet in a modelContext or is from a different context,
            // it needs to be inserted into 'this' context.
            // A robust way is to fetch or re-fetch if necessary, or ensure it's the correct instance.
            // For simplicity, assuming 'connection' is ready to be saved or is already managed by 'context'.
            // If 'connection' is a new instance, 'insert' is correct.
            // If 'connection' is an existing instance from 'context', changes are saved by 'context.save()'.
            // If 'connection' is from another context, this can be problematic.
            // Let's assume 'connection' is either new or already part of 'context'.
            if connection.modelContext == nil { // Basic check if it's a new, unmanaged object
                 context.insert(connection)
            } // If already managed, its properties are updated, and save() will persist.

            do {
                try context.save()

                let oldConnectionId = self.currentConnection?.id
                self.currentConnection = connection // This will trigger didSet

                // Ensure apiClient is updated if the connection actually changed or was nil
                if oldConnectionId != connection.id || self.apiClient == nil || self.apiClient?.connection.id != connection.id {
                    self.apiClient = HomeAssistantAPIClient(connection: connection, modelContext: context)
                    print("HomeAssistantAPIClient initialized/updated with model context after saving connection.")
                }
                print("Successfully saved connection: \(connection.instanceName ?? connection.baseURL.absoluteString)")
            } catch {
                print("Failed to save connection: \(error)")
                // Don't set currentConnection or apiClient if save fails
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

    // MARK: - OAuth State Management
    func clearPendingOAuthData() {
        pendingOAuthState = nil
        pendingPkceCodeVerifier = nil
        print("Cleared pending OAuth state and PKCE verifier from AppState.")
    }
}
