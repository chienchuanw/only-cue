import Foundation

/// A parsed OSC 1.0 message: an address pattern plus an ordered argument list.
/// OnlyCue is a receive-only OSC endpoint, so this is the only OSC value type
/// we need — there's no encoder.
struct OSCMessage: Equatable {
    let addressPattern: String
    let arguments: [OSCArgument]
}

/// The OSC argument types OnlyCue understands. The four zero-byte types
/// (`T`/`F`/`N`/`I`) carry no payload — they're occasionally used by senders
/// for "go" buttons that send `/onlycue/play T`.
enum OSCArgument: Equatable {
    case int32(Int32)
    case float32(Float)
    case string(String)
    case `true`
    case `false`
    case null
    case impulse

    /// Numeric value if this argument is an int32 or float32; nil otherwise.
    /// Lets command mapping treat "`/skip 5`" (int) and "`/skip 5.0`" (float)
    /// uniformly.
    var numericValue: Double? {
        switch self {
        case .int32(let value): Double(value)
        case .float32(let value): Double(value)
        default: nil
        }
    }
}
