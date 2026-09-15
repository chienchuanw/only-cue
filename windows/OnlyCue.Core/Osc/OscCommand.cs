namespace OnlyCue.Core.Osc;

/// <summary>The app actions an incoming OSC message can decode to.</summary>
public enum OscCommandKind
{
    Play,
    Pause,
    Stop,
    /// <summary>Jump relative to the current playhead. Positive = forward,
    /// negative = back. Seconds.</summary>
    Skip,
    /// <summary>Jump to an absolute time. Seconds, clamped to >= 0 by the
    /// dispatcher.</summary>
    Locate,
    CueAdd,
    CueNext,
    CuePrev,
    /// <summary>Walk to the next cue and start/keep playing (Show-mode GO).
    /// Unlike <see cref="CueNext"/>, which only seeks, this also plays.</summary>
    CueGo
}

/// <summary>
/// A typed app action decoded from an incoming OSC message. A re-implementation
/// of the Swift <c>OSCCommand</c> (<c>OnlyCue/OSC/OSCCommand.swift</c>), kept in
/// lockstep by the golden-vector contract (<c>golden/osc-v1.json</c>, epic #728
/// M1c). The mapping is a pure function so it is fully testable without a live
/// socket; dispatch lives in the document/ViewModel layer.
/// </summary>
/// <param name="Kind">Which action.</param>
/// <param name="Seconds">The numeric argument, for <see cref="OscCommandKind.Skip"/>
/// and <see cref="OscCommandKind.Locate"/> only.</param>
public sealed record OscCommand(OscCommandKind Kind, double? Seconds = null)
{
    /// <summary>
    /// Pure mapping from a parsed message to a command. Unknown addresses — and
    /// addresses missing a required numeric argument — return null; the server
    /// logs them to the recent-messages buffer but takes no action.
    /// </summary>
    /// <remarks>
    /// C#'s string switch is ordinal where Swift's <c>==</c> is canonical
    /// equivalence. The nine literals are pure ASCII with no decomposable
    /// characters, so no string can canonically equal one without being byte-equal
    /// to it, and the two comparisons cannot diverge.
    /// </remarks>
    public static OscCommand? From(OscMessage message) => message.AddressPattern switch
    {
        "/onlycue/play" => new OscCommand(OscCommandKind.Play),
        "/onlycue/pause" => new OscCommand(OscCommandKind.Pause),
        "/onlycue/stop" => new OscCommand(OscCommandKind.Stop),
        "/onlycue/skip" => Numeric(message, OscCommandKind.Skip),
        "/onlycue/locate" => Numeric(message, OscCommandKind.Locate),
        "/onlycue/cue/add" => new OscCommand(OscCommandKind.CueAdd),
        "/onlycue/cue/next" => new OscCommand(OscCommandKind.CueNext),
        "/onlycue/cue/prev" => new OscCommand(OscCommandKind.CuePrev),
        "/onlycue/cue/go" => new OscCommand(OscCommandKind.CueGo),
        _ => null
    };

    /// <summary>Only the <em>first</em> argument is consulted, and only if it is
    /// an int32 or a float32 — a leading string yields no command even when a
    /// number follows it.</summary>
    /// <remarks>
    /// A non-finite argument yields no command either, and that rule exists for
    /// this side of the port specifically. The dispatcher folds
    /// <c>Skip</c> through <c>max(0, currentTime + seconds)</c>, and the two
    /// platforms' <c>max</c> disagree about NaN: Swift's is <c>y &gt;= x ? y : x</c>,
    /// so <c>max(0, nan)</c> is <c>0</c> while <c>max(nan, 0)</c> is <c>nan</c>;
    /// <see cref="Math.Max(double, double)"/> propagates NaN either way round.
    /// The same datagram would rewind the playhead to 0 on macOS and seek to NaN
    /// here. Refusing the argument at this boundary means the dispatcher never
    /// has to be careful, on either platform (#845).
    ///
    /// <see cref="double.IsFinite"/> and Swift's <c>isFinite</c> are the same
    /// IEEE-754 predicate — not NaN, not ±∞ — so unlike <c>max</c> they cannot
    /// drift apart. Int32 arguments widen to a finite double always, so this
    /// only ever bites floats.
    /// </remarks>
    private static OscCommand? Numeric(OscMessage message, OscCommandKind kind) =>
        message.Arguments.Count > 0
        && message.Arguments[0].NumericValue is { } seconds
        && double.IsFinite(seconds)
            ? new OscCommand(kind, seconds)
            : null;
}
