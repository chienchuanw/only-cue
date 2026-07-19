import Foundation

/// Splits an OnlyCue `cueNumber` (Double) into grandMA2's `number` +
/// `sub_number` XML attributes. `sub_number` is **thousandths** (3.5 → 500):
/// MA2 cue numbers carry at most three decimals and thousandths are free of
/// the "3.15 vs 3.150" digit-string ambiguity. Isolated here so a real-rig
/// verification (#683 plan step 13) that contradicts the rule changes one
/// function.
enum MA2CueNumber {

    struct Components: Equatable {
        var number: Int
        var subNumber: Int
    }

    static func components(from value: Double) -> Components {
        // Round in integer thousandths so binary float noise (1.3 → 1300.0002)
        // cannot leak into the sub number.
        let thousandths = Int((value * 1000).rounded())
        return Components(number: thousandths / 1000, subNumber: thousandths % 1000)
    }
}

/// Generates the grandMA2 sequence import XML (#683): one content-empty cue
/// per OnlyCue cue with number, label, info and fades. Structure per the spec's
/// `## XML schemas` section (researched from real v3.9.x console exports);
/// cue-only imports (no `CueDatas`) are proven by TCHelper / MLA.
enum MA2SequenceXMLGenerator {

    static func xml(cues: [Cue], sequenceName: String, showfile: String, datetime: String) -> String {
        ""
    }
}
