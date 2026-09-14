import Foundation
@testable import OnlyCue

/// Builds `CuePresentationGoldenVector` by *running* the Swift implementations
/// over the fixtures. Nothing here spells an expected value: macOS is the source
/// of truth, and a hand-written expectation would only pin the author's belief.
///
/// The independent correctness pins live in `CuePresentationGoldenVectorTests`,
/// which is where a wrong Swift implementation is supposed to be caught before
/// it is frozen into the contract.
enum CuePresentationGolden {

    // MARK: - Fade

    private static func fadeParseCases() -> [CuePresentationGoldenVector.FadeParseCase] {
        CuePresentationFadeFixtures.parseInputs.map { fixture in
            let parsed = FadeTime.parse(fixture.input)
            return .init(
                name: fixture.name,
                input: fixture.input,
                expectFadeIn: GoldenDouble(parsed?.fadeIn),
                expectFadeOut: GoldenDouble(parsed?.fadeOut)
            )
        }
    }

    private static func fadeFormatCases() -> [CuePresentationGoldenVector.FadeFormatCase] {
        CuePresentationFadeFixtures.formatInputs.map { fixture in
            let fade = FadeTime(fadeIn: fixture.fadeIn, fadeOut: fixture.fadeOut)
            return .init(
                name: fixture.name,
                fadeIn: GoldenDouble(fixture.fadeIn),
                fadeOut: GoldenDouble(fixture.fadeOut),
                expectFormat: fade.format(),
                expectCellDisplay: fade.cellDisplay
            )
        }
    }

    // MARK: - Cue numbers

    private static func result(_ value: CueNumberValidator.Result) -> CuePresentationGoldenVector.ValidationResult {
        switch value {
        case .ok:
            .init(kind: "ok", lowerExclusive: nil, upperExclusive: nil)
        case .invalidFormat:
            .init(kind: "invalidFormat", lowerExclusive: nil, upperExclusive: nil)
        case .duplicate:
            .init(kind: "duplicate", lowerExclusive: nil, upperExclusive: nil)
        case .outOfRange(let lower, let upper):
            .init(
                kind: "outOfRange",
                lowerExclusive: GoldenDouble(lower),
                upperExclusive: GoldenDouble(upper)
            )
        }
    }

    private static func validationCases() throws -> [CuePresentationGoldenVector.CueNumberValidationCase] {
        let seeds = CuePresentationCueNumberFixtures.cues
        let cues = try seeds.map(Self.cue)
        return try CuePresentationCueNumberFixtures.validationInputs.map { input in
            .init(
                name: input.name,
                cues: seeds,
                targetID: input.targetID,
                candidate: GoldenDouble(input.candidate),
                expect: result(
                    CueNumberValidator.validate(
                        candidate: input.candidate,
                        for: try Self.uuid(input.targetID),
                        in: cues
                    )
                )
            )
        }
    }

    private static func errorCases() -> [CuePresentationGoldenVector.CueNumberErrorCase] {
        CuePresentationCueNumberFixtures.errorInputs.map { input in
            .init(
                name: input.name,
                result: result(input.result),
                expect: CueNumberErrorMessage.text(for: input.result)
            )
        }
    }

    // MARK: - Assembly

    static func make() throws -> CuePresentationGoldenVector {
        CuePresentationGoldenVector(
            contract: "cue-presentation",
            version: 1,
            note: Self.note,
            fadeParse: fadeParseCases(),
            fadeFormat: fadeFormatCases(),
            cueNumberValidation: try validationCases(),
            cueNumberErrors: errorCases(),
            sectionCount: CuePresentationRowGolden.sectionCountCases(),
            rowTapIntent: CuePresentationRowGolden.rowTapCases(),
            rowFill: CuePresentationRowGolden.rowFillCases(),
            goFilter: try CuePresentationRowGolden.goFilterCases(),
            rowOpacity: try CuePresentationRowGolden.rowOpacityCases(),
            activeCue: try CuePresentationRowGolden.activeCueCases(),
            emptyState: CuePresentationRowGolden.emptyStateCases()
        )
    }

    /// Deterministic encoding so the committed file is stable and diff-friendly —
    /// identical rules to vectors 1–7.
    static func encoded(_ vector: CuePresentationGoldenVector) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(vector)
    }

    // MARK: - Shared helpers

    /// A fixture id that does not parse is a typo in this file, not a runtime
    /// condition, so it throws rather than silently substituting a fresh UUID —
    /// which would make the committed vector churn every run.
    static func uuid(_ string: String) throws -> UUID {
        guard let parsed = UUID(uuidString: string) else {
            throw CuePresentationGoldenError.malformedFixtureID(string)
        }
        return parsed
    }

    /// The seed *is* the vector's `CueFixture`, so the committed JSON carries the
    /// same values the Swift implementation was run against — no second spelling
    /// to keep in step.
    static func cue(_ seed: CuePresentationCueSeed) throws -> Cue {
        Cue(
            id: try uuid(seed.id),
            typeID: try uuid(seed.typeID),
            cueNumber: seed.cueNumber?.value,
            name: "",
            time: seed.time.value,
            notes: "",
            fadeTime: .zero
        )
    }

    private static let note = """
        macOS-generated golden vectors for OnlyCue's cue-list presentation layer \
        (epic #728, M1d). Eleven groups, each naming the Swift function it was \
        generated from; see \
        docs/superpowers/specs/2026-09-14-windows-m1d-cue-presentation.md. Unlike \
        vectors 1-7 this one pins decisions rather than bytes on a wire, so the \
        expectations are branch names and user-facing strings: compare them \
        exactly, including the U+2013 EN DASH in the cue-number format message. \
        Doubles are carried as round-trip-exact decimal strings; compare the \
        parsed IEEE-754 bit patterns, not the text. Ids are likewise transport: \
        Swift's uuidString uppercases the hex where .NET's Guid.ToString() \
        lowercases it, so compare parsed Guid values and never the strings. To \
        regenerate after a deliberate change, delete \
        golden/cue-presentation-v1.json and re-run the test suite.
        """
}

enum CuePresentationGoldenError: Error {
    case malformedFixtureID(String)
}
