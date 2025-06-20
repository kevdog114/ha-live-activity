// In HaLiveNotifications/Views/LiveActivityListView.swift
import SwiftUI
import SwiftData

struct LiveActivityListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    // State for this view
    @State private var entities: [HAState] = []
    @State private var isLoadingActivities: Bool = false
    @State private var viewError: Error?

    // Main view body, now delegating to helper properties
    var body: some View {
        NavigationView {
            contentView
                .navigationTitle("HA Console")
                .toolbar { mainToolbar }
                .onAppear(perform: onAppearAction)
                // FIX: Watch a value that is Equatable, like whether the client is nil.
                .onChange(of: appState.apiClient != nil) { _, isConnected in
                    onClientChange(isConnected: isConnected)
                }
        }
    }

    // MARK: - View Builders

    /// The main content view that switches between loading, error, empty, and list states.
    @ViewBuilder
    private var contentView: some View {
        if isLoadingActivities {
            ProgressView("Loading Home Assistant Data...")
        } else if let error = viewError {
            errorView(error)
        } else if entities.isEmpty {
            emptyStateView
        } else {
            entityListView
        }
    }

    /// The view to display when an error occurs.
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text("Error Loading Data")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry", action: fetchEntities)
                .buttonStyle(.borderedProminent)
        }
    }

    /// The view to display when no entities are loaded.
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray.fill")
                .font(.largeTitle)
                .foregroundColor(.gray)
            Text("No Entities Found")
                .font(.headline)
            Text("Connect to an instance and fetch entities.")
                .font(.caption)
            Button("Fetch Entities", action: fetchEntities)
                .buttonStyle(.bordered)
                .disabled(appState.apiClient == nil)
        }
    }

    /// The main list view that displays connection info and entities.
    private var entityListView: some View {
        List {
            connectionInfoSection
            entityListSection
        }
    }

    /// A section for displaying the current connection information.
    private var connectionInfoSection: some View {
        Section("Connection Info") {
            if let connection = appState.currentConnection {
                Text(connection.instanceName ?? "Unnamed Instance")
                    .fontWeight(.bold)
                Text(connection.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("Not connected.")
            }
            Button("Test API: Fetch States", action: fetchEntities)
        }
    }
    
    /// A section that lists all the fetched entities.
    private var entityListSection: some View {
        Section("Entities (\(entities.count) found)") {
            ForEach(entities) { entity in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entity.attributes["friendly_name"]?.value as? String ?? entity.entityId)
                        .font(.headline)
                    Text("State: \(entity.state)")
                        .font(.subheadline)
                    if let lastChanged = entity.attributes["last_changed"]?.value as? String {
                        Text(formattedDate(from: lastChanged) ?? lastChanged)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// The toolbar content for the navigation view.
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Disconnect", role: .destructive) {
                appState.disconnect(context: modelContext)
            }
            .disabled(appState.currentConnection == nil)
        }
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Refresh", systemImage: "arrow.clockwise", action: fetchEntities)
                .disabled(isLoadingActivities || appState.apiClient == nil)
        }
    }
    
    // MARK: - Actions & Logic

    private func onAppearAction() {
        if entities.isEmpty && appState.apiClient != nil && !isLoadingActivities {
            fetchEntities()
        }
    }
    
    // FIX: This function now receives a simple Boolean.
    private func onClientChange(isConnected: Bool) {
        if isConnected && entities.isEmpty {
            fetchEntities()
        }
    }

    private func fetchEntities() {
        guard let client = appState.apiClient else {
            viewError = HAErrors.configurationError("API Client not available. Connect first.")
            return
        }

        isLoadingActivities = true
        viewError = nil

        Task {
            do {
                let fetchedStates = try await client.getStates()
                // Update state on the main thread
                await MainActor.run {
                    self.entities = fetchedStates.sorted {
                        let name1 = $0.attributes["friendly_name"]?.value as? String ?? $0.entityId
                        let name2 = $1.attributes["friendly_name"]?.value as? String ?? $1.entityId
                        return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
                    }
                    print("Fetched and sorted \(fetchedStates.count) entities.")
                    self.isLoadingActivities = false
                }
            } catch {
                print("Error fetching entities: \(error)")
                let processedError = (error as? HAErrors) ?? HAErrors.unknownError(error.localizedDescription)
                // Update state on the main thread
                await MainActor.run {
                    self.viewError = processedError
                    self.entities = []
                    self.isLoadingActivities = false
                }
            }
        }
    }

    // MARK: - Helpers

    private func formattedDate(from dateString: String) -> String? {
        let formatter = ISO8601DateFormatter()
        // Try parsing with fractional seconds first
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date.formatted(date: .abbreviated, time: .standard)
        }
        // Fallback to parsing without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date.formatted(date: .abbreviated, time: .standard)
        }
        return nil
    }
}

// MARK: - Preview

struct LiveActivityListView_Previews: PreviewProvider {
    // Helper to create a fully configured AppState for previews
    static func configuredAppState(withEntities: Bool = false) -> AppState {
        let appState = AppState()
        let previewConnection = HomeAssistantConnection(
            baseURL: URL(string: "http://preview.home.assistant.io:8123")!,
            accessToken: "fake_token_for_preview",
            instanceName: "Preview HA"
        )
        // This assignment triggers the didSet in AppState, initializing the apiClient
        appState.currentConnection = previewConnection
        return appState
    }

    // Helper to create the model container for SwiftData
    @MainActor
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: HomeAssistantConnection.self, configurations: config)

        return container
    }
    
    static var previews: some View {
        let container = makeContainer()

        // Preview for the empty state, ready to fetch
        LiveActivityListView()
            .environment(configuredAppState())
            .modelContainer(container)
            .previewDisplayName("Empty State")

        // You would need to adjust the view or AppState to directly show pre-filled entities
        // in a preview, as @State is owned by the view.
    }
}
