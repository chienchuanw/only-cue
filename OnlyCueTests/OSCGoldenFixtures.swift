import Foundation

// Hand-built OSC datagram fixtures for the cross-platform golden vector (epic
// #728, M1c — vector 6 of the seven in
// `docs/superpowers/specs/2026-09-14-windows-m1-contract-design.md`).
//
// OnlyCue is a receive-only OSC endpoint, so there is no encoder to round-trip
// through — and that is the point. Every datagram below is assembled byte by
// byte from the OSC 1.0 wire format, which makes the fixtures an independent
// statement of the format rather than a mirror of `OSCParser`'s assumptions.

/// One case: a datagram, and the name it is matched by on both sides.
struct OSCGoldenCase {
    let name: String
    let datagram: Data

    init(_ name: String, _ datagram: Data) {
        self.name = name
        self.datagram = datagram
    }
}

// MARK: - Wire-format packer

/// The four OSC primitives OnlyCue's parser reads, written by hand.
enum OSCPack {

    /// NUL-terminated, then padded with NULs to the next 4-byte boundary.
    static func string(_ text: String) -> Data {
        terminated(Data(text.utf8))
    }

    /// The same padding applied to arbitrary bytes, so a fixture can carry a
    /// payload that is deliberately not valid UTF-8.
    static func terminated(_ body: Data) -> Data {
        var data = body
        data.append(0)
        while !data.count.isMultiple(of: 4) {
            data.append(0)
        }
        return data
    }

    static func int32(_ value: Int32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    static func float32(_ value: Float) -> Data {
        withUnsafeBytes(of: value.bitPattern.bigEndian) { Data($0) }
    }

    /// `address [type-tag string] [argument bytes...]`. Omitting `typeTags`
    /// produces the address-only form some senders use for no-arg messages.
    static func message(_ address: String, _ typeTags: String? = nil, _ arguments: [Data] = []) -> Data {
        var data = string(address)
        if let typeTags {
            data.append(string(typeTags))
        }
        for argument in arguments {
            data.append(argument)
        }
        return data
    }

    /// `#bundle`, an 8-byte time tag, then `[Int32 size][element]` × N.
    static func bundle(_ elements: [Data]) -> Data {
        var payload = Data()
        for element in elements {
            payload.append(int32(Int32(element.count)))
            payload.append(element)
        }
        return rawBundle(payload)
    }

    /// `payload` wrapped in `levels` nested `#bundle` containers, for the
    /// depth-cap cases. `levels` counts containers, so the payload sits at
    /// depth `levels`.
    static func nested(_ payload: Data, levels: Int) -> Data {
        var data = payload
        for _ in 0 ..< levels {
            data = bundle([data])
        }
        return data
    }

    /// A bundle whose body is supplied verbatim, for the malformed size cases.
    /// The time tag is OSC's "immediate" value; nothing reads it.
    static func rawBundle(_ payload: Data) -> Data {
        var data = string("#bundle")
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 1] as [UInt8])
        data.append(payload)
        return data
    }
}

// MARK: - Cases

enum OSCGoldenCases {

    /// Every supported address, so the mapping table is pinned entry by entry.
    private static let addresses: [OSCGoldenCase] = [
        .init("play maps from an empty type-tag string", OSCPack.message("/onlycue/play", ",")),
        .init("pause maps", OSCPack.message("/onlycue/pause", ",")),
        .init("stop maps", OSCPack.message("/onlycue/stop", ",")),
        .init("cue add maps", OSCPack.message("/onlycue/cue/add", ",")),
        .init("cue next maps", OSCPack.message("/onlycue/cue/next", ",")),
        .init("cue prev maps", OSCPack.message("/onlycue/cue/prev", ",")),
        .init("cue go maps", OSCPack.message("/onlycue/cue/go", ",")),
        .init("an address with no type-tag string at all is accepted", OSCPack.message("/onlycue/play")),
        .init("an unknown address parses but maps to nothing",
              OSCPack.message("/onlycue/unknown", ",i", [OSCPack.int32(1)]))
    ]

    /// The two addresses that read a numeric argument, including the forms that
    /// deliberately produce no command.
    private static let arguments: [OSCGoldenCase] = [
        .init("skip takes an int argument", OSCPack.message("/onlycue/skip", ",i", [OSCPack.int32(5)])),
        .init("skip takes a negative int argument", OSCPack.message("/onlycue/skip", ",i", [OSCPack.int32(-5)])),
        .init("skip takes a float argument", OSCPack.message("/onlycue/skip", ",f", [OSCPack.float32(2.5)])),
        .init("locate takes an int argument", OSCPack.message("/onlycue/locate", ",i", [OSCPack.int32(90)])),
        .init("locate takes a float argument", OSCPack.message("/onlycue/locate", ",f", [OSCPack.float32(90.5)])),
        // Widening a Float to a Double is exact, so this pins the *whole* float
        // bit pattern: 0.1 is unrepresentable in binary32, and the widened
        // double is 0.10000000149011612, not 0.1.
        .init("a float argument widens to the double the float actually holds",
              OSCPack.message("/onlycue/skip", ",f", [OSCPack.float32(0.1)])),
        // Only a bitwise comparison can tell this from `0.0`.
        .init("a float argument keeps its negative zero",
              OSCPack.message("/onlycue/skip", ",f", [OSCPack.float32(-0.0)])),
        .init("a float argument widens infinity",
              OSCPack.message("/onlycue/skip", ",f", [OSCPack.float32(.infinity)])),
        // The case #828 had to leave out: until `GoldenDouble` carried bit
        // patterns there was no spelling both platforms read the same way
        // (#833). The quiet NaN widens to 0x7FF8000000000000 — the pattern .NET
        // cannot name, which is exactly why it is worth pinning.
        .init("a float argument widens a quiet NaN",
              OSCPack.message("/onlycue/skip", ",f", [OSCPack.float32(Float(bitPattern: 0x7FC0_0000))])),
        // Sign and payload ride along through the widening, so a parser that
        // normalised NaN — or compared with `==` — would show up here.
        .init("a float argument keeps a signed NaN payload",
              OSCPack.message("/onlycue/skip", ",f", [OSCPack.float32(Float(bitPattern: 0xFFC0_0001))])),
        .init("a string argument yields no command", OSCPack.message("/onlycue/skip", ",s", [OSCPack.string("5")])),
        .init("an empty argument list yields no command", OSCPack.message("/onlycue/skip", ",")),
        .init("a missing type-tag string yields no command", OSCPack.message("/onlycue/skip")),
        .init("the four zero-byte types carry no payload", OSCPack.message("/onlycue/play", ",TFNI")),
        .init("only the first argument is consulted for a command",
              OSCPack.message(
                  "/onlycue/skip",
                  ",ifs",
                  [OSCPack.int32(3), OSCPack.float32(1.5), OSCPack.string("x")]
              )),
        .init("a leading non-numeric argument yields no command even when a number follows",
              OSCPack.message("/onlycue/skip", ",si", [OSCPack.string("a"), OSCPack.int32(7)]))
    ]

    /// The three padding outcomes, each followed by an int whose value is only
    /// correct if the string consumed exactly the right number of bytes.
    private static let alignment: [OSCGoldenCase] = [
        .init("a 3-byte string argument needs no padding",
              OSCPack.message("/onlycue/skip", ",si", [OSCPack.string("abc"), OSCPack.int32(42)])),
        .init("a 4-byte string argument pads by three",
              OSCPack.message("/onlycue/skip", ",si", [OSCPack.string("abcd"), OSCPack.int32(42)])),
        .init("a 5-byte string argument pads by two",
              OSCPack.message("/onlycue/skip", ",si", [OSCPack.string("abcde"), OSCPack.int32(42)])),
        .init("an empty string argument still consumes a word",
              OSCPack.message("/onlycue/skip", ",si", [OSCPack.string(""), OSCPack.int32(42)])),
        .init("a short address pads to the next word", OSCPack.message("/abc", ",i", [OSCPack.int32(1)]))
    ]

    private static let bundles: [OSCGoldenCase] = [
        .init("a bundle with one message yields it", OSCPack.bundle([OSCPack.message("/onlycue/play", ",")])),
        // `parseMessages` returns all three; `parse` — and therefore the
        // command — takes only the first.
        .init("a bundle with several messages yields all of them",
              OSCPack.bundle([OSCPack.message("/onlycue/skip", ",i", [OSCPack.int32(1)]),
                              OSCPack.message("/onlycue/play", ","),
                              OSCPack.message("/onlycue/stop", ",")])),
        .init("a nested bundle is flattened",
              OSCPack.bundle([OSCPack.bundle([OSCPack.message("/onlycue/cue/go", ",")])])),
        // The loop skips a bad element rather than abandoning the bundle.
        .init("a malformed bundle element is skipped and the next still parses",
              OSCPack.bundle([Data([0x68, 0x69, 0x00, 0x00]), OSCPack.message("/onlycue/stop", ",")])),
        .init("a bundle with trailing bytes shorter than a size word stops cleanly",
              OSCPack.bundle([OSCPack.message("/onlycue/play", ",")]) + Data([1, 2, 3])),
        .init("an empty bundle yields nothing", OSCPack.bundle([])),
        .init("a bundle with no time tag yields nothing", OSCPack.string("#bundle")),
        .init("a bundle with a zero element size yields nothing",
              OSCPack.rawBundle(OSCPack.int32(0) + OSCPack.message("/onlycue/play", ","))),
        .init("a bundle with a negative element size yields nothing",
              OSCPack.rawBundle(OSCPack.int32(-1) + OSCPack.message("/onlycue/play", ","))),
        // A zero size ends the bundle; it is not a skippable empty element. Both
        // readings consume the size word, so only a *well-formed element after
        // the zero* can tell them apart — without one, `size > 0` and `size >= 0`
        // produce the same empty result. (Found by mutation: the case above
        // stayed green when the guard was loosened.)
        .init("a bundle stops at a zero element size rather than skipping past it",
              OSCPack.rawBundle(OSCPack.int32(0) + sized(OSCPack.message("/onlycue/play", ",")))),
        .init("a bundle truncated mid-element yields nothing",
              OSCPack.rawBundle(OSCPack.int32(64) + Data([1, 2, 3, 4]))),
        // Nesting depth cap (#835). Both sides recurse once per level, so an
        // uncapped parser lets the network pick our stack depth. The pair
        // straddles the boundary: a cap of the wrong value, or on one platform
        // only, moves exactly one of these two and goes red.
        .init("a bundle nested to the depth limit still parses",
              OSCPack.nested(OSCPack.message("/onlycue/play", ","), levels: depthLimit)),
        .init("a bundle nested one past the depth limit yields nothing",
              OSCPack.nested(OSCPack.message("/onlycue/play", ","), levels: depthLimit + 1)),
        // Refusing the over-deep branch must not take its siblings with it —
        // the cap follows the same "skip the bad element" rule as a malformed
        // one. A port that bails out of the whole bundle passes both cases
        // above and fails this one.
        .init("an over-deep element is skipped but its sibling still parses",
              OSCPack.bundle([OSCPack.nested(OSCPack.message("/onlycue/play", ","), levels: depthLimit),
                              OSCPack.message("/onlycue/stop", ",")]))
    ]

    /// Spelled out rather than read from `OSCParser.maximumBundleDepth`, and
    /// deliberately so: a fixture derived from the constant would regenerate
    /// itself when the constant changed, and the vector would keep passing
    /// while the contract moved underneath it. A literal makes the drift guard
    /// go red instead, which is the whole point of pinning the boundary.
    private static let depthLimit = 32

    /// An element with its `Int32` length prefix, for the raw-bundle fixtures.
    private static func sized(_ element: Data) -> Data {
        OSCPack.int32(Int32(element.count)) + element
    }

    /// Every branch that returns nil or an empty list. None of them may throw,
    /// hang, or produce a partially parsed message.
    private static let malformed: [OSCGoldenCase] = [
        .init("an empty datagram yields nothing", Data()),
        .init("a head that is neither a bundle nor an address yields nothing", OSCPack.string("hello")),
        .init("an empty address yields nothing", OSCPack.terminated(Data())),
        .init("an unterminated string yields nothing", Data("abcd".utf8)),
        // Swift's `String(data:encoding:.utf8)` refuses these bytes; .NET's
        // default decoder would silently substitute U+FFFD and accept them.
        .init("an address with invalid UTF-8 yields nothing", OSCPack.terminated(Data([0x2F, 0xFF, 0xFE]))),
        .init("a string argument with invalid UTF-8 drops the whole message",
              OSCPack.message("/onlycue/skip", ",s", [Data([0xFF, 0xFE, 0x00, 0x00])])),
        .init("a truncated int argument drops the whole message",
              OSCPack.message("/onlycue/skip", ",i", [Data([0, 0])])),
        .init("an unknown type tag drops the whole message",
              OSCPack.message("/onlycue/skip", ",z", [OSCPack.int32(1)])),
        // The first argument parses; the second does not. The result is no
        // message at all, not a message with one argument.
        .init("a partially parseable argument list drops the whole message",
              OSCPack.message("/onlycue/skip", ",if", [OSCPack.int32(3), Data([0, 0])])),
        // A readable word that is not a type-tag string is treated as "no
        // arguments" — the word is consumed and the message survives.
        .init("a type-tag string without the comma is treated as no arguments",
              OSCPack.message("/onlycue/skip", "hello")),
        .init("unterminated bytes after an address still yield the address-only message",
              OSCPack.string("/onlycue/play") + Data([1, 2, 3]))
    ]

    /// Where Swift's `String` semantics differ from the obvious .NET spelling.
    /// Every case here parses one way char-by-char and another way the way Swift
    /// actually does it, so each one is the difference between a console
    /// responding and a console sitting still.
    private static let unicode: [OSCGoldenCase] = [
        // `String(data:encoding:.utf8)` is NSString-backed and drops exactly one
        // leading U+FEFF. `UTF8Encoding.GetString` keeps it, strict or lenient,
        // and the address then fails the "/" test.
        .init("a byte-order mark before the address is dropped, not kept",
              OSCPack.message("\u{FEFF}/onlycue/play", ",")),
        // Same stripping, and it is what lets the head still read as "#bundle" —
        // a port that keeps the mark takes the plain-message branch and returns
        // nothing instead of flattening the bundle.
        .init("a byte-order mark before #bundle still reads as a bundle",
              bomBundle(sized(OSCPack.message("/onlycue/play", ",")))),
        // Only the leading one: the second survives as a real scalar.
        .init("only the first byte-order mark in a string argument is dropped",
              OSCPack.message("/onlycue/skip", ",s", [OSCPack.terminated(Data(bom + bom + "x".utf8))])),
        // `hasPrefix` compares grapheme clusters: "," plus a combining acute is a
        // single cluster that is not ",". Swift therefore treats the word as "not
        // a type-tag string" and falls through to the address-only form, which
        // still plays. A char-wise `StartsWith(',')` accepts it, then chokes on
        // U+0301 as an unknown tag and drops the message.
        .init("a combining mark on the type-tag comma falls through to address-only",
              OSCPack.message("/onlycue/play", ",\u{0301}")),
        // The same rule on the address: the cluster is "/́", not "/", so the whole
        // datagram is rejected.
        .init("a combining mark on the leading slash rejects the address",
              OSCPack.message("/\u{0301}onlycue/play", ","))
    ]

    private static let bom: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// `rawBundle` with a byte-order mark in front of the `#bundle` word.
    private static func bomBundle(_ payload: Data) -> Data {
        var data = OSCPack.terminated(Data(bom + "#bundle".utf8))
        data.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 1] as [UInt8])
        data.append(payload)
        return data
    }

    static let all: [OSCGoldenCase] = addresses + arguments + alignment + bundles + malformed + unicode
}
