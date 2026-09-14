using System.Text.Json.Serialization;

namespace OnlyCue.Core.Document;

/// <summary>
/// The timecode-event command written for each cue when pushing to grandMA2
/// (#683). The persisted spellings are the contract — do not rename.
/// </summary>
public enum Ma2TimecodeCommand
{
    Go,

    /// <summary>The default: a Goto lands on the exact cue when jumping around
    /// in rehearsal, while Go only ever steps forward and drifts out of sync.</summary>
    Goto
}

/// <summary>
/// Per-clip grandMA2 push destination (#683), persisted so a re-push of the
/// same song lands in the same console slots on any machine. Mirrors Swift
/// <c>MA2PushTarget</c>. Schema v17.
/// </summary>
public sealed class Ma2PushTarget
{
    public int SequenceSlot { get; set; }

    public int TimecodeSlot { get; set; }

    /// <summary><c>null</c> = leave the sequence unassigned (#764). Page and
    /// number are set or cleared together.</summary>
    public int? ExecutorPage { get; set; }

    public int? ExecutorNumber { get; set; }

    public Ma2TimecodeCommand TimecodeCommand { get; set; }

    /// <summary>
    /// Cue-type filter used for the last push; empty = all types.
    /// </summary>
    /// <remarks>
    /// A <c>Set&lt;UUID&gt;</c> on the Swift side, so its JSON order is
    /// <i>randomised per process</i> — Swift seeds its hasher per launch. The
    /// golden vector sorts this array before comparing for exactly that reason;
    /// nothing here may depend on the order it arrives in.
    /// </remarks>
    [JsonPropertyName("includedTypeIDs")]
    public List<Guid> IncludedTypeIds { get; set; } = [];

    /// <summary><c>null</c> = derive from the clip's sanitised resolved name at
    /// push time (#686). Schema v18.</summary>
    public string? SequenceName { get; set; }

    /// <summary>
    /// The executor as a page/number pair when assigned, else <c>null</c> (#764).
    /// The two are only meaningful together, so a half-set executor resolves to
    /// <c>null</c>. Mirrors Swift's <c>MA2PushTarget.executor</c>.
    /// </summary>
    [JsonIgnore]
    public (int Page, int Number)? Executor =>
        (ExecutorPage, ExecutorNumber) is ({ } page, { } number) ? (page, number) : null;

    /// <summary>
    /// Console slots, pages and executors are 1-based; anything below 1 would
    /// emit invalid XML indices and telnet commands. The executor is optional
    /// (#764): valid when both fields are cleared or both are 1-based.
    /// </summary>
    [JsonIgnore]
    public bool IsValid
    {
        get
        {
            if (SequenceSlot < 1 || TimecodeSlot < 1)
            {
                return false;
            }

            return (ExecutorPage, ExecutorNumber) switch
            {
                (null, null) => true,
                ({ } page, { } number) => page >= 1 && number >= 1,
                _ => false  // half-set executor
            };
        }
    }
}
