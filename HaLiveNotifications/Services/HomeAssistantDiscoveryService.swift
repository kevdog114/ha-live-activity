import Foundation
import Network

@Observable
class HomeAssistantDiscoveryService {
    private(set) var discoveredInstances: [DiscoveredInstance] = []
    private var browser: NWBrowser?

    init() {}

    func startDiscovery() {
        // Ensure discovery is not already running
        guard browser == nil else { return }

        // Home Assistant advertises itself via mDNS (Bonjour)
        // with the service type "_home-assistant._tcp"
        let parameters = NWParameters()
        parameters.includePeerToPeer = true // Allow discovery over Wi-Fi and Ethernet

        browser = NWBrowser(for: .bonjour(type: "_home-assistant._tcp", domain: nil), using: parameters)

        browser?.stateUpdateHandler = { newState in
            switch newState {
            case .failed(let error):
                print("NWBrowser failed with error: \(error)")
                // Handle error, perhaps by stopping the browser or retrying
                self.stopDiscovery()
            case .ready:
                print("NWBrowser ready.")
            case .setup:
                print("NWBrowser setup.")
            case .cancelled:
                print("NWBrowser cancelled.")
            default:
                break
            }
        }

        browser?.browseResultsChangedHandler = { results, changes in
            var currentInstances: [DiscoveredInstance] = []
            for result in results {
                if case .service(let service) = result.endpoint {
                    // We have a service name, now we need to resolve its address
                    // The resolution part will be added in a subsequent step/refinement
                    // For now, let's store based on name and a placeholder for host/port
                    // In a real scenario, you'd resolve the TXT record for more details
                    // and the A/AAAA records for IP addresses.

                    // This is a simplified placeholder. Resolution is more complex.
                    // Typically, you'd use NWConnection to resolve the endpoint or a separate resolver.
                    // For this initial step, we'll just use the service name.
                    // Actual host/port resolution will be implemented properly later.

                    // Example: Extracting host and port requires resolving the endpoint.
                    // This is often done by establishing a connection or using a more specific resolver.
                    // For now, we'll simulate finding some details.
                    // In a full implementation, you would use an NWConnection to the result.endpoint,
                    // or NWResolver if you only need to resolve.

                    // Placeholder for actual resolution logic:
                    // We need to resolve the result.endpoint to get an IP address and port.
                    // This is an asynchronous operation.

                    // Let's assume a placeholder until proper resolution is implemented
                    // For example, if result.metadata has NWPath information with an address

                    if let path = result.metadata.path {
                         // This is a simplified way to get host and port.
                         // A robust solution would involve proper service resolution.
                        if let ipv4 = path.localEndpoint?.interface?.ipv4Address?.debugDescription,
                           let port = result.endpoint.port {
                            let instance = DiscoveredInstance(name: service.name, host: ipv4, port: Int(port) ?? 8123)
                            if !currentInstances.contains(where: { $0.name == instance.name && $0.host == instance.host }) {
                                 currentInstances.append(instance)
                             }
                        } else if let ipv6 = path.localEndpoint?.interface?.ipv6Address?.debugDescription,
                                  let port = result.endpoint.port {
                            let instance = DiscoveredInstance(name: service.name, host: ipv6, port: Int(port) ?? 8123)
                            if !currentInstances.contains(where: { $0.name == instance.name && $0.host == instance.host }) {
                                 currentInstances.append(instance)
                             }
                        } else {
                            // Fallback if direct address is not easily available from path
                            // This part definitely needs a proper resolver.
                            // print("Could not determine host/port for \(service.name). Endpoint: \(result.endpoint)")
                        }
                    }
                }
            }
            // Update the main list on the main thread
            DispatchQueue.main.async {
                // This logic needs to be smarter about merging updates, not just replacing.
                // For now, let's just update with what's currently seen.
                // A set might be better for discoveredInstances to handle duplicates naturally.

                // A more robust way to update:
                var updatedInstances = self.discoveredInstances
                for change in changes {
                    switch change {
                    case .added(let addedResult):
                        if case .service(let service) = addedResult.endpoint {
                            // Attempt to resolve and add
                            self.resolveService(result: addedResult) { instance in
                                if let instance = instance, !self.discoveredInstances.contains(where: { $0.name == instance.name && $0.host == instance.host && $0.port == instance.port }) {
                                    self.discoveredInstances.append(instance)
                                }
                            }
                        }
                    case .removed(let removedResult):
                        if case .service(let service) = removedResult.endpoint {
                            // This also needs resolution to match correctly if host/port were part of identity
                            self.discoveredInstances.removeAll { $0.name == service.name } // Simplified removal
                        }
                    case .changed(let changedResult):
                        // Handle changes if necessary, e.g., re-resolve
                        if case .service(let service) = changedResult.newResult.endpoint {
                            self.discoveredInstances.removeAll { $0.name == service.name }
                            self.resolveService(result: changedResult.newResult) { instance in
                                if let instance = instance, !self.discoveredInstances.contains(where: { $0.name == instance.name && $0.host == instance.host && $0.port == instance.port }) {
                                    self.discoveredInstances.append(instance)
                                }
                            }
                        }
                        break // Placeholder
                    }
                }
            }
        }
        browser?.start(queue: .main) // Use .main queue for simplicity, or a dedicated queue
        print("Home Assistant discovery started.")
    }

    private func resolveService(result: NWBrowser.Result, completion: @escaping (DiscoveredInstance?) -> Void) {
        guard case .service(let service) = result.endpoint else {
            completion(nil)
            return
        }

        let connection = NWConnection(to: result.endpoint, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                if let remoteEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = remoteEndpoint {
                    let instance = DiscoveredInstance(name: service.name, host: host.debugDescription, port: Int(port.rawValue))
                    print("Resolved: \(instance.name) at \(instance.host):\(instance.port)")
                    completion(instance)
                } else {
                    completion(nil)
                }
                connection.cancel() // We only needed to resolve
            case .failed(let error):
                print("Failed to resolve \(service.name): \(error.localizedDescription)")
                completion(nil)
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: .main) // Use a dedicated queue for network operations
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        // No need to clear discoveredInstances here, they might still be valid for a bit
        // or the UI might want to show the last known set.
        // If they need to be cleared, add:
        // DispatchQueue.main.async {
        //    self.discoveredInstances.removeAll()
        // }
        print("Home Assistant discovery stopped.")
    }

    // For preview or testing
    static func preview() -> HomeAssistantDiscoveryService {
        let service = HomeAssistantDiscoveryService()
        service.discoveredInstances = [
            DiscoveredInstance(name: "Home Assistant Living Room", host: "192.168.1.100", port: 8123),
            DiscoveredInstance(name: "HA Dev Instance", host: "homeassistant.local", port: 8123)
        ]
        return service
    }
}

// Helper to get port from NWEndpoint.Port (it's an optional NWEndpoint.Port)
extension NWEndpoint {
    var port: String? {
        if case .hostPort(_, let port) = self {
            return port.debugDescription
        }
        return nil
    }
}
