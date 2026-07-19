import Foundation

/// Shared MA2 command-name quoting (double quotes, no documented escape for
/// embedded quotes → strip them) used by both the XML planner and the telnet
/// command planner (#683).
enum MA2CommandQuoting {
    static func quotable(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "")
    }
}

/// Pure planner for the telnet-command push (#683, Approach A): a media item's
/// filtered cues → the exact ordered command list that rebuilds the target
/// sequence as `Trig=Timecode` / `TrigTime` cues. No FTP, no XML, no
/// timecode-pool object; the sequence's timecode slot is left at grandMA2's
/// default ("link selected"), so the operator's selected TC slot — fed by
/// OnlyCue's LTC — drives the chase. `Delete Sequence` first makes re-push
/// idempotent (an empty slot returns a WARNING, not an `Error #`).
enum MA2CommandPlanner {

    static func commands(
        cues: [Cue],
        target: MA2PushTarget,
        sequenceName: String,
        startTimecodeFrames: Int,
        framerate: SMPTEFramerate
    ) -> [String] {
        let seq = target.sequenceSlot
        // MA2 sequences are number-ordered; emit cues in cue-number order.
        let ordered = cues.sorted { ($0.cueNumber ?? 0) < ($1.cueNumber ?? 0) }

        var commands: [String] = ["Delete Sequence \(seq) /nc"]

        for cue in ordered {
            let num = MA2CueNumber.commandString(from: cue.cueNumber ?? 0)
            let name = MA2CommandQuoting.quotable(cue.name)
            commands.append("Store Sequence \(seq) Cue \(num) \"\(name)\" /nc")
            commands.append("Assign Sequence \(seq) Cue \(num) /Trig=Timecode")
            let trig = MA2TrigTime.command(
                cueTime: cue.time, startTimecodeFrames: startTimecodeFrames, framerate: framerate
            )
            commands.append("Assign Sequence \(seq) Cue \(num) /TrigTime=\(trig)")
            if cue.fadeTime.fadeIn > 0 {
                commands.append(
                    "Assign Sequence \(seq) Cue \(num) /fade=\(FadeTime.formatNumber(cue.fadeTime.fadeIn))"
                )
            }
            if cue.fadeTime.fadeOut > 0 {
                commands.append(
                    "Assign Sequence \(seq) Cue \(num) /outfade=\(FadeTime.formatNumber(cue.fadeTime.fadeOut))"
                )
            }
            if !cue.notes.isEmpty {
                // Newlines would split the CRLF-framed telnet line; quotes would break
                // the quoted argument. Collapse to one line, strip embedded quotes.
                let info = MA2CommandQuoting.quotable(
                    cue.notes.split(whereSeparator: \.isNewline).joined(separator: " ")
                )
                commands.append("Assign Sequence \(seq) Cue \(num) /info=\"\(info)\"")
            }
        }

        commands.append("Label Sequence \(seq) \"\(MA2CommandQuoting.quotable(sequenceName))\"")
        commands.append("Assign Sequence \(seq) At Exec \(target.executorPage).\(target.executorNumber)")
        return commands
    }
}
