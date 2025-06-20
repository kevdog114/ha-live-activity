import Foundation
import Network

@Observable
class HomeAssistantDiscoveryService {
    // MARK: - Published Properties

    // The list of discovered Home Assistant instances, published for SwiftUI views.
    private(set) var discoveredInstances: [DiscoveredInstance] = []

    // MARK: - Private Properties

    private var browser: NWBrowser?
    private var activeResolutionConnections: [UUID: NWConnection] = [:]
    private var updateDebounceWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    init() {}

    // MARK: - Discovery Control

    /// Starts the Bonjour (mDNS) discovery process for Home Assistant services.
    func startDiscovery() {
        guard browser == nil else {
            print("Discovery already running.")
            return
        }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let newBrowser = NWBrowser(for: .bonjour(type: "_home-assistant._tcp.", domain: nil), using: parameters)
        self.browser = newBrowser

        newBrowser.stateUpdateHandler = { (newState: NWBrowser.State) in
            switch newState {
            case .ready:
                print("NWBrowser ready to discover Home Assistant instances.")
            case .failed(let error):
                print("NWBrowser failed with error: \(error)")
                self.stopDiscovery()
            default:
                break
            }
        }

        // Set up the browse results changed handler to process changes in discovered services.
        newBrowser.browseResultsChangedHandler = { [weak self] (_, changes) in
            guard let self = self else { return }
            self.updateDebounceWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }

                var tempInstances = Set(self.discoveredInstances)
                let group = DispatchGroup()
                
                var newInstances: [DiscoveredInstance] = []
                let lock = NSLock()

                for change in changes {
                    switch change {
                    case .added(let result), .changed(_, let result, _):
                        group.enter()
                        self.handleAdded(result: result) { newInstance in
                            if let newInstance = newInstance {
                                lock.lock()
                                newInstances.append(newInstance)
                                lock.unlock()
                            }
                            group.leave()
                        }

                    case .removed(let result):
                        self.handleRemoved(result: result, from: &tempInstances)
                    
                    @unknown default:
                        break
                    }
                }
                
                group.notify(queue: DispatchQueue.main) {
                    tempInstances.formUnion(newInstances)
                    self.discoveredInstances = Array(tempInstances).sorted { $0.name < $1.name }
                    print("Discovery update complete. Instances: \(self.discoveredInstances.count)")
                }
            }
            self.updateDebounceWorkItem = workItem
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }

        newBrowser.start(queue: DispatchQueue.global(qos: .background))
        print("Home Assistant discovery started.")
    }

    /// Stops the discovery process and cleans up resources.
    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        updateDebounceWorkItem?.cancel()
        updateDebounceWorkItem = nil
        activeResolutionConnections.values.forEach { $0.cancel() }
        activeResolutionConnections.removeAll()
        print("Home Assistant discovery stopped.")
    }
    
    // MARK: - Change Handling Helpers
    
    private func handleAdded(result: NWBrowser.Result, completion: @escaping (DiscoveredInstance?) -> Void) {
        switch result.endpoint {
        case .hostPort(let host, let port):
            let instance = DiscoveredInstance(name: host.debugDescription, host: host.debugDescription, port: Int(port.rawValue) ?? 8123)
            completion(instance)
            
        case .service:
            self.resolveServiceEndpoint(result.endpoint, completion: completion)
            
        default:
            completion(nil)
            break
        }
    }
    
    /// Handles a removed service synchronously by filtering it out of the provided Set.
    private func handleRemoved(result: NWBrowser.Result, from tempInstances: inout Set<DiscoveredInstance>) {
        switch result.endpoint {
        case .hostPort(let host, _):
            tempInstances = tempInstances.filter { $0.host != host.debugDescription }
            print("Removed HA Instance (Direct HostPort): \(host.debugDescription)")

        case .service(let name, _, _, _):
            tempInstances = tempInstances.filter { $0.name != name }
            print("Removed HA Instance (by name): \(name)")
         
        default:
            break
        }
    }

    // MARK: - Service Resolution Helper

    private func resolveServiceEndpoint(_ endpoint: NWEndpoint, completion: @escaping (DiscoveredInstance?) -> Void) {
        guard case let .service(name, _, _, _) = endpoint else {
            completion(nil)
            return
        }
        
        let resolutionID = UUID()
        let connection = NWConnection(to: endpoint, using: .tcp)
        activeResolutionConnections[resolutionID] = connection
        
        var hasCompleted = false
        let singleCompletion = { (instance: DiscoveredInstance?) in
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }
            guard !hasCompleted else { return }
            hasCompleted = true
            
            completion(instance)
            connection.cancel()
            self.activeResolutionConnections.removeValue(forKey: resolutionID)
        }

        connection.stateUpdateHandler = { [weak self] (newState: NWConnection.State) in
            switch newState {
            case .ready:
                if let remoteEndpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = remoteEndpoint {
                    let instance = DiscoveredInstance(name: name, host: host.debugDescription, port: Int(port.rawValue) ?? 8123)
                    singleCompletion(instance)
                } else {
                    singleCompletion(nil)
                }

            case .failed, .cancelled:
                singleCompletion(nil)
                
            default:
                break
            }
        }
        connection.start(queue: DispatchQueue.global(qos: .utility))
    }

    // MARK: - Preview/Testing Helper

    static func preview() -> HomeAssistantDiscoveryService {
        let service = HomeAssistantDiscoveryService()
        service.discoveredInstances = [
            DiscoveredInstance(name: "Home Assistant Living Room", host: "192.168.1.100", port: 8123),
            DiscoveredInstance(name: "HA Dev Instance", host: "homeassistant.local", port: 8123)
        ]
        return service
    }
}
