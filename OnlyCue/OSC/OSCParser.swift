import Foundation

/// Minimal OSC 1.0 message parser — the subset OnlyCue needs as a receive-only
/// endpoint. Handles plain messages (address pattern, type-tag string,
/// int32/float32/string args plus the zero-byte `T`/`F`/`N`/`I` types) with
/// 4-byte alignment, and flattens `#bundle` containers by parsing each
/// element. Returns nil / empty on anything malformed — a bad datagram is
/// simply ignored, never crashes.
enum OSCParser {

    /// Parse a single datagram. For a bundle, returns the first contained
    /// message (sufficient for OnlyCue's command-per-button usage; senders
    /// that bundle multiple commands are rare and out of scope for v1).
    static func parse(_ data: Data) -> OSCMessage? {
        parseMessages(data).first
    }

    /// Parse a datagram into zero or more messages. A plain message yields
    /// one; a `#bundle` yields its (recursively flattened) contents.
    static func parseMessages(_ data: Data) -> [OSCMessage] {
        var reader = Reader(data)
        guard let head = reader.readOSCString() else { return [] }
        if head == "#bundle" {
            return parseBundle(&reader)
        }
        guard head.hasPrefix("/") else { return [] }
        guard let message = parsePlainMessage(address: head, &reader) else { return [] }
        return [message]
    }

    // MARK: - Branches

    /// `#bundle` body: an 8-byte time tag, then `[Int32 size][element bytes]` ×N.
    private static func parseBundle(_ reader: inout Reader) -> [OSCMessage] {
        guard reader.skip(8) else { return [] }
        var out: [OSCMessage] = []
        while reader.remaining >= 4 {
            guard let size = reader.readInt32(), size > 0,
                  let element = reader.readBytes(Int(size)) else { break }
            out.append(contentsOf: parseMessages(element))
        }
        return out
    }

    /// `address` has already been read; consume the type-tag string + args.
    /// A message with no type-tag string is technically malformed in OSC 1.1+
    /// but some senders omit it for no-arg messages — the address-only form is
    /// accepted.
    private static func parsePlainMessage(address: String, _ reader: inout Reader) -> OSCMessage? {
        guard let typeTags = reader.readOSCString(), typeTags.hasPrefix(",") else {
            return OSCMessage(addressPattern: address, arguments: [])
        }
        guard let args = parseArguments(typeTags: typeTags, &reader) else { return nil }
        return OSCMessage(addressPattern: address, arguments: args)
    }

    /// One argument per char in `typeTags` (after the leading `,`). Returns nil
    /// if any value is short or an unknown type tag is hit (rather than
    /// guessing at the byte layout).
    private static func parseArguments(typeTags: String, _ reader: inout Reader) -> [OSCArgument]? {
        var args: [OSCArgument] = []
        for tag in typeTags.dropFirst() {
            guard let argument = parseArgument(tag: tag, &reader) else { return nil }
            args.append(argument)
        }
        return args
    }

    private static func parseArgument(tag: Character, _ reader: inout Reader) -> OSCArgument? {
        switch tag {
        case "i": reader.readInt32().map(OSCArgument.int32)
        case "f": reader.readFloat32().map(OSCArgument.float32)
        case "s": reader.readOSCString().map(OSCArgument.string)
        case "T": .true
        case "F": .false
        case "N": .null
        case "I": .impulse
        default: nil
        }
    }

    // MARK: - Reader

    /// 4-byte-aligned cursor over a `Data` blob with the OSC primitives.
    private struct Reader {
        private let data: Data
        private var offset: Int
        init(_ data: Data) { self.data = data; self.offset = data.startIndex }

        var remaining: Int { data.endIndex - offset }

        mutating func skip(_ count: Int) -> Bool {
            guard remaining >= count else { return false }
            offset += count
            return true
        }

        mutating func readBytes(_ count: Int) -> Data? {
            guard remaining >= count else { return nil }
            let slice = data.subdata(in: offset ..< offset + count)
            offset += count
            return slice
        }

        /// Null-terminated, then padded with NULs to the next 4-byte boundary.
        mutating func readOSCString() -> String? {
            guard let nulIndex = data[offset...].firstIndex(of: 0) else { return nil }
            let strBytes = data.subdata(in: offset ..< nulIndex)
            guard let value = String(data: strBytes, encoding: .utf8) else { return nil }
            let consumed = (nulIndex - offset) + 1
            let padded = (consumed + 3) & ~3
            guard remaining >= padded else { return nil }
            offset += padded
            return value
        }

        mutating func readInt32() -> Int32? {
            guard remaining >= 4 else { return nil }
            let bytes = data.subdata(in: offset ..< offset + 4)
            offset += 4
            return bytes.withUnsafeBytes { Int32(bigEndian: $0.loadUnaligned(as: Int32.self)) }
        }

        mutating func readFloat32() -> Float? {
            guard let bits = readUInt32() else { return nil }
            return Float(bitPattern: bits)
        }

        private mutating func readUInt32() -> UInt32? {
            guard remaining >= 4 else { return nil }
            let bytes = data.subdata(in: offset ..< offset + 4)
            offset += 4
            return bytes.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
        }
    }
}
