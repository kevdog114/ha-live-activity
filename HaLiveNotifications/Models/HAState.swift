import Foundation

struct HAState: Codable, Identifiable, Hashable {
    var id: String { entityId } // Conform to Identifiable using entity_id
    let entityId: String
    let state: String
    let attributes: [String: AnyCodableValue] // Using a helper for mixed-type attributes
    let lastChanged: String // ISO 8601 Date String
    let lastUpdated: String // ISO 8601 Date String
    // context can also be decoded if needed

    enum CodingKeys: String, CodingKey {
        case entityId = "entity_id"
        case state
        case attributes
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    // Conform to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(entityId)
    }

    // Conform to Equatable (implicitly provided by Hashable if all stored properties are Equatable, but entityId is sufficient for identity)
    static func == (lhs: HAState, rhs: HAState) -> Bool {
        lhs.entityId == rhs.entityId
    }
}

// Helper to decode mixed type dictionaries like 'attributes'
struct AnyCodableValue: Codable, Hashable {
    let value: Any

    init<T>(_ value: T?) {
        self.value = value ?? ()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let arrayVal = try? container.decode([AnyCodableValue].self) {
            value = arrayVal.map { $0.value }
        } else if let dictVal = try? container.decode([String: AnyCodableValue].self) {
            value = dictVal.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = value as? Int {
            try container.encode(intVal)
        } else if let doubleVal = value as? Double {
            try container.encode(doubleVal)
        } else if let stringVal = value as? String {
            try container.encode(stringVal)
        } else if let boolVal = value as? Bool {
            try container.encode(boolVal)
        } else if let arrayVal = value as? [Any] {
            try container.encode(arrayVal.map { AnyCodableValue($0) })
        } else if let dictVal = value as? [String: Any] {
            try container.encode(dictVal.mapValues { AnyCodableValue($0) })
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type for AnyCodableValue"))
        }
    }

    // Basic Hashable conformance
    func hash(into hasher: inout Hasher) {
        if let val = value as? AnyHashable {
            hasher.combine(val)
        } else {
            // Fallback for non-Hashable types, or handle more gracefully
            // For simplicity, just hash the description, but this is not ideal for complex types
            hasher.combine(String(describing: value))
        }
    }

    static func == (lhs: AnyCodableValue, rhs: AnyCodableValue) -> Bool {
        // Basic equality check, might need to be more robust for collections
        return String(describing: lhs.value) == String(describing: rhs.value)
    }
}
