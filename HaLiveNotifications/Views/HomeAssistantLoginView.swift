import SwiftUI
import SwiftData

struct HomeAssistantLoginView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss // To dismiss the sheet upon successful connection

    @State private var manualURLString: String = ""
    @State private var accessToken: String = ""
    @State private var showManualSetup: Bool = false
    @State private var discoveryService = HomeAssistantDiscoveryService()
    @State private var selectedDiscoveredInstance: DiscoveredInstance?

    // To give more specific feedback during connection attempt
    @State private var connectingToInstanceName: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if appState.isLoading {
                    if let instanceName = connectingToInstanceName {
                        ProgressView("Connecting to \(instanceName)...")
                    } else {
                        ProgressView("Processing...") // Generic loading for other AppState loading states
                    }
                } else {
                    // Error display should be prominent
                    if appState.connectionError != nil {
                        ErrorDisplayView(error: appState.connectionError)
                            .padding(.bottom)
                    }

                    if !discoveryService.discoveredInstances.isEmpty && !showManualSetup {
                        discoveredInstancesSection
                    }

                    manualSetupToggle

                    if showManualSetup {
                        manualSetupSection
                    }
                }
            }
            .navigationTitle("Connect to Home Assistant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Show dismiss only if presented as a sheet and no connection yet,
                    // or allow dismissing if already connected (though ContentView handles this swap)
                    Button("Cancel") { // Changed from "Dismiss"
                        appState.connectionError = nil // Clear errors on cancel
                        dismiss()
                    }
                }
            }
            .onAppear {
                appState.connectionError = nil
                if discoveryService.discoveredInstances.isEmpty { // Start only if not already populated
                    discoveryService.startDiscovery()
                }
            }
            .onDisappear {
                // Consider stopping discovery only if view is truly disappearing, not just covered
                // discoveryService.stopDiscovery()
            }
            // If connection is successful, ContentView will change and this view will be dismissed.
            // We can also listen for appState.currentConnection becoming non-nil to explicitly dismiss.
            .onChange(of: appState.currentConnection) { _, newValue in
                if newValue != nil {
                    dismiss() // Dismiss the login sheet on successful connection
                }
            }
        }
    }

    private var discoveredInstancesSection: some View {
        Section(header: Text("Discovered Instances").font(.headline)) {
            List(discoveryService.discoveredInstances) { instance in
                VStack(alignment: .leading) {
                    Text(instance.name).font(.title3)
                    if let url = instance.url {
                        Text(url.absoluteString).font(.caption).foregroundColor(.gray)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    self.selectedDiscoveredInstance = instance
                    self.manualURLString = instance.url?.absoluteString ?? ""
                    self.accessToken = "" // Clear previous token
                    withAnimation {
                       self.showManualSetup = true
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxHeight: discoveryService.discoveredInstances.isEmpty ? 0 : 200)
        }
    }

    private var manualSetupToggle: some View {
        Button(action: {
            withAnimation {
                showManualSetup.toggle()
                if !showManualSetup {
                    manualURLString = ""
                    accessToken = ""
                    selectedDiscoveredInstance = nil
                    appState.connectionError = nil // Clear error when toggling setup mode
                }
            }
        }) {
            Text(showManualSetup ? "Hide Manual Setup / Token Entry" : (discoveryService.discoveredInstances.isEmpty ? "Manual Setup" : "Or Enter Manually / Add Token"))
                .padding(.vertical, 5)
        }
    }

    private var manualSetupSection: some View {
        VStack(alignment: .leading) {
            Text(selectedDiscoveredInstance != nil ? "Enter Token for \(selectedDiscoveredInstance!.name)" : "Manual Configuration")
                .font(.headline)
                .padding(.bottom, 5)

            TextField("Home Assistant URL", text: $manualURLString, prompt: Text("e.g., http://homeassistant.local:8123"))
                .keyboardType(.URL)
                .autocapitalization(.none)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .disabled(selectedDiscoveredInstance != nil && selectedDiscoveredInstance?.url != nil)


            SecureField("Long-Lived Access Token", text: $accessToken)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)

            HStack {
                Spacer()
                Button("Connect") {
                    handleConnect()
                }
                .padding()
                .buttonStyle(.borderedProminent)
                .disabled(manualURLString.isEmpty || accessToken.isEmpty || appState.isLoading)
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    private func handleConnect() {
        appState.connectionError = nil
        guard !accessToken.isEmpty else {
            appState.connectionError = .authenticationError("Access token cannot be empty.")
            return
        }

        let nameToConnect: String
        if let selectedInstance = selectedDiscoveredInstance {
            nameToConnect = selectedInstance.name
            connectingToInstanceName = nameToConnect
            Task { // Ensure UI updates for connectingToInstanceName are seen
                await appState.connect(to: selectedInstance, accessToken: accessToken, context: modelContext)
                connectingToInstanceName = nil // Clear after attempt
            }
        } else {
            guard let url = URL(string: manualURLString) else { // Basic validation, canOpenURL is tricky
                appState.connectionError = .configurationError("Invalid URL format.")
                return
            }
            nameToConnect = url.host ?? "Manual Instance"
            connectingToInstanceName = nameToConnect

            // Using the direct saveConnection via a new HomeAssistantConnection object
            let newConnection = HomeAssistantConnection(baseURL: url, accessToken: accessToken, instanceName: nameToConnect)
            Task { // Ensure UI updates for connectingToInstanceName are seen
                await appState.saveConnection(connection: newConnection, context: modelContext)
                connectingToInstanceName = nil // Clear after attempt
            }
        }
    }
}

// Ensure HAErrors has user-friendly descriptions (already done in a previous step)
// Ensure AppState methods (connect, saveConnection, loadPersistedConnection) correctly set
// appState.isLoading and appState.connectionError. This was largely handled when AppState was developed.
// For example, in AppState.swift:
// func connect(...) {
//    self.isLoading = true
//    self.connectionError = nil // Clear previous before attempt
//    ...
//    Task {
//        ...
//        if error occurs { self.connectionError = HAErrors.someError(...) }
//        self.isLoading = false
//    }
// }
// This pattern is already mostly in place in AppState.swift.

// Preview
struct HomeAssistantLoginView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a dummy AppState and ModelContainer for preview
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: HomeAssistantConnection.self, configurations: config)
        let appState = AppState()

        // Example: Simulate an error state
        let appStateWithError = AppState()
        appStateWithError.connectionError = HAErrors.networkError("Preview: Could not connect to server.")

        // Example: Simulate loading state
        let appStateLoading = AppState()
        appStateLoading.isLoading = true
        // appStateLoading.connectingToInstanceName = "Preview HA" // This would need HomeAssistantLoginView's @State to be settable or passed in

        return Group {
            HomeAssistantLoginView()
                .environment(appState)
                .modelContainer(container)
                .previewDisplayName("Default State")

            HomeAssistantLoginView()
                .environment(appStateWithError)
                .modelContainer(container)
                .previewDisplayName("Error State")

            // For loading state with specific instance name, it's harder to preview
            // directly as `connectingToInstanceName` is internal @State.
            // One way is to modify the view to accept it for previews, or test by running.
            HomeAssistantLoginView()
                .environment(appStateLoading) // Will show "Processing..."
                .modelContainer(container)
                .previewDisplayName("Loading State (Generic)")

        }
    }
}
