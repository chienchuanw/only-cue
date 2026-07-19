import XCTest
@testable import OnlyCue

/// #683 — the timecode-show import XML pushed to grandMA2. Structure verified
/// against a real v3.9.60 console export (spec `## XML schemas`): `Timecode →
/// Track(Object = executor <No>30/1/page/exec</No>) → SubTrack(0) → Event
/// (time in **frames**, omitted at frame 0) → Cue(<No>1/seq/index</No>)`.
/// Events run in time order; the cue reference index is the **number-sorted**
/// 1-based position matching `MA2SequenceXMLGenerator`'s ordering.
final class MA2TimecodeXMLGeneratorTests: XCTestCase {

    private func cue(number: Double, name: String = "", time: TimeInterval = 0) -> Cue {
        Cue(
            id: UUID(),
            typeID: UUID(),
            cueNumber: number,
            name: name,
            time: time,
            notes: "",
            fadeTime: FadeTime(fadeIn: 0, fadeOut: 0)
        )
    }

    private func xml(
        cues: [Cue],
        timecodeSlot: Int = 3,
        sequenceSlot: Int = 18,
        command: MA2TimecodeCommand = .goto,
        startTimecodeFrames: Int = 0,
        lengthFrames: Int = 900,
        framerate: SMPTEFramerate = .fps30
    ) -> String {
        MA2TimecodeXMLGenerator.xml(
            cues: cues,
            timecodeSlot: timecodeSlot,
            timecodeName: "Opening TC",
            sequenceSlot: sequenceSlot,
            sequenceName: "Opening",
            executorPage: 2,
            executorNumber: 3,
            command: command,
            startTimecodeFrames: startTimecodeFrames,
            lengthFrames: lengthFrames,
            framerate: framerate,
            showfile: "MyShow",
            datetime: "2026-07-19T12:00:00"
        )
    }

    func test_fullDocument_goldenSkeleton() {
        // Cue 1 at 0 s (frame 0 → no `time` attribute), cue 2.5 at 15 s
        // (frame 450 at 30 FPS — the real export's documented example).
        let cues = [
            cue(number: 1, name: "Intro", time: 0),
            cue(number: 2.5, name: "Drop", time: 15)
        ]
        let expected = """
        <?xml version="1.0" encoding="utf-8"?>
        <?xml-stylesheet type="text/xsl" href="styles/timecode@sheet.xsl"?>
        <MA xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://schemas.malighting.de/grandma2/xml/MA" xsi:schemaLocation="http://schemas.malighting.de/grandma2/xml/MA http://schemas.malighting.de/grandma2/xml/3.9.60/MA.xsd" major_vers="3" minor_vers="9" stream_vers="60">
        \t<Info datetime="2026-07-19T12:00:00" showfile="MyShow" />
        \t<Timecode index="2" name="Opening TC" lenght="900" play_mode="Play" frame_format="30 FPS">
        \t\t<Track index="0" active="true" expanded="true">
        \t\t\t<Object name="Opening 2.3">
        \t\t\t\t<No>30</No>
        \t\t\t\t<No>1</No>
        \t\t\t\t<No>2</No>
        \t\t\t\t<No>3</No>
        \t\t\t</Object>
        \t\t\t<SubTrack index="0">
        \t\t\t\t<Event index="0" command="Goto" pressed="true" step="1">
        \t\t\t\t\t<Cue name="Intro">
        \t\t\t\t\t\t<No>1</No>
        \t\t\t\t\t\t<No>18</No>
        \t\t\t\t\t\t<No>1</No>
        \t\t\t\t\t</Cue>
        \t\t\t\t</Event>
        \t\t\t\t<Event index="1" time="450" command="Goto" pressed="true" step="2">
        \t\t\t\t\t<Cue name="Drop">
        \t\t\t\t\t\t<No>1</No>
        \t\t\t\t\t\t<No>18</No>
        \t\t\t\t\t\t<No>2</No>
        \t\t\t\t\t</Cue>
        \t\t\t\t</Event>
        \t\t\t</SubTrack>
        \t\t</Track>
        \t</Timecode>
        </MA>
        """
        XCTAssertEqual(xml(cues: cues), expected)
    }

    func test_eventTime_isFramesAtProjectFramerate() {
        // 2 s → 48 / 50 / 60 / 60 frames. Drop-frame is a 30 fps timeline in
        // OnlyCue v1 (only the labels drop), so it converts like fps30.
        let cases: [(SMPTEFramerate, String)] = [
            (.fps24, "time=\"48\""),
            (.fps25, "time=\"50\""),
            (.fps30, "time=\"60\""),
            (.fps30drop, "time=\"60\"")
        ]
        for (framerate, fragment) in cases {
            let document = xml(cues: [cue(number: 1, time: 2)], framerate: framerate)
            XCTAssertTrue(document.contains(fragment), "\(framerate): missing \(fragment)")
        }
    }

    func test_eventTime_addsStartTimecodeOffset() {
        // Clip starts at 01:00:00:00 (108000 frames at 30 FPS); a cue 1.5 s in
        // lands at frame 108045. Frame 0 omission only applies to actual frame 0.
        let document = xml(cues: [cue(number: 1, time: 1.5)], startTimecodeFrames: 108_000)
        XCTAssertTrue(document.contains("time=\"108045\""))

        let offsetStart = xml(cues: [cue(number: 1, time: 0)], startTimecodeFrames: 108_000)
        XCTAssertTrue(offsetStart.contains("time=\"108000\""))
    }

    func test_command_goEmitsCapitalizedGo() {
        let document = xml(cues: [cue(number: 1, time: 1)], command: .go)
        XCTAssertTrue(document.contains("command=\"Go\""))
        XCTAssertFalse(document.contains("command=\"Goto\""))
    }

    func test_cueReference_usesNumberSortedIndex_eventsStayInTimeOrder() {
        // Cue number 5 fires first (t=1), cue number 1 second (t=2). Events are
        // time-ordered, but the third <No> is the number-sorted sequence index
        // (1 → index 1, 5 → index 2) matching MA2SequenceXMLGenerator.
        let cues = [
            cue(number: 5, name: "Early", time: 1),
            cue(number: 1, name: "Late", time: 2)
        ]
        let document = xml(cues: cues)
        let expectedEvents = """
        \t\t\t\t<Event index="0" time="30" command="Goto" pressed="true" step="1">
        \t\t\t\t\t<Cue name="Early">
        \t\t\t\t\t\t<No>1</No>
        \t\t\t\t\t\t<No>18</No>
        \t\t\t\t\t\t<No>2</No>
        \t\t\t\t\t</Cue>
        \t\t\t\t</Event>
        \t\t\t\t<Event index="1" time="60" command="Goto" pressed="true" step="2">
        \t\t\t\t\t<Cue name="Late">
        \t\t\t\t\t\t<No>1</No>
        \t\t\t\t\t\t<No>18</No>
        \t\t\t\t\t\t<No>1</No>
        \t\t\t\t\t</Cue>
        \t\t\t\t</Event>
        """
        XCTAssertTrue(document.contains(expectedEvents))
    }

    func test_emptyCueName_omitsNameAttribute() {
        let document = xml(cues: [cue(number: 1, time: 1)])
        XCTAssertTrue(document.contains("<Cue>"))
        XCTAssertFalse(document.contains("<Cue name="))
    }

    func test_lenghtAttribute_carriesLengthFrames() {
        // MA2's real export misspells it `lenght`; we must match.
        let document = xml(cues: [cue(number: 1)], lengthFrames: 89_171)
        XCTAssertTrue(document.contains("lenght=\"89171\""))
        XCTAssertFalse(document.contains("length="))
    }
}
