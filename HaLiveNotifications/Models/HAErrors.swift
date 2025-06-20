import Foundation

enum HAErrors: Error, LocalizedError {
    case swiftDataError(String)
    case networkError(String)
    case authenticationError(String)
    case configurationError(String)
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .swiftDataError(let message):
            return "Database error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationError(let message):
            return "Authentication failed: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .unknownError(let message):
            return "An unknown error occurred: \(message)"
        }
    }
}
