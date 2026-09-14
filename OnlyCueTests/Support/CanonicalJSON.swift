import Foundation

/// A parsed JSON tree that survives a decode→encode round trip without changing
/// shape. `JSONSerialization` would hand back `NSNumber`s that blur `Int` and
/// `Bool`, and `Any` is not `Codable`, so golden vectors that embed a whole model
/// need their own value type.
///
/// This exists so `golden/cuelist-migration-v1.json` can hold the expected model
/// as **readable nested JSON** rather than an escaped string blob. A golden file
/// nobody can read is a golden file nobody will check.
enum CanonicalJSON: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([Self])
    case object([String: Self])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            // Int before Double: `60` must stay an integer or every whole-numbered
            // field would re-encode as `60.0` and read as drift.
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: Self].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "unrepresentable JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension CanonicalJSON {

    /// Every string anywhere in the tree, used to learn which identifiers an input
    /// document already carried.
    var allStrings: [String] {
        switch self {
        case .string(let value): return [value]
        case .array(let values): return values.flatMap(\.allStrings)
        case .object(let values): return values.values.flatMap(\.allStrings)
        default: return []
        }
    }

    /// Replace each string via `transform`, depth-first. Arrays keep their order;
    /// object keys are untouched.
    func mappingStrings(_ transform: (String) -> String) -> CanonicalJSON {
        switch self {
        case .string(let value):
            return .string(transform(value))
        case .array(let values):
            return .array(values.map { $0.mappingStrings(transform) })
        case .object(let values):
            return .object(values.mapValues { $0.mappingStrings(transform) })
        default:
            return self
        }
    }

    /// Sort the string array at `key`, wherever it appears in the tree.
    ///
    /// Needed for `includedTypeIDs`, which is a `Set<UUID>` in Swift. Swift seeds
    /// its hasher per process, so that set encodes in a *different order on every
    /// launch* — measured, not assumed. Left alone it would make the drift guard
    /// fail at random, and a guard that cries wolf is worse than none: the reflex
    /// response to a spurious red is to regenerate the file, which is exactly the
    /// action that hides real drift.
    func sortingStringArray(forKey key: String) -> CanonicalJSON {
        switch self {
        case .array(let values):
            return .array(values.map { $0.sortingStringArray(forKey: key) })
        case .object(let values):
            return .object(values.reduce(into: [:]) { result, entry in
                let (name, value) = entry
                if name == key, case .array(let items) = value {
                    let strings = items.compactMap { element -> String? in
                        if case .string(let text) = element { return text }
                        return nil
                    }
                    if strings.count == items.count {
                        result[name] = .array(strings.sorted().map(Self.string))
                        return
                    }
                }
                result[name] = value.sortingStringArray(forKey: key)
            })
        default:
            return self
        }
    }
}
