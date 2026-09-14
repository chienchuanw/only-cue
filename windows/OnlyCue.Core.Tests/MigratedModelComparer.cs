using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace OnlyCue.Core.Tests;

/// <summary>
/// Compares a migrated model against a golden expectation, resolving the
/// <c>MINTED-000N</c> placeholders the macOS generator writes for UUIDs the
/// migration invents.
/// </summary>
/// <remarks>
/// <para>Three rungs are not pure functions of their input — v1 and v2 mint a
/// default cue point type (and v1 a media item id), and the v8–v10 tempo fan-out
/// mints a synthetic "Tempo" cue per unmatched section — so those ids differ on
/// every run and on every platform. The macOS side replaces them with numbered
/// placeholders; this side binds each placeholder to whatever UUID the C# core
/// minted and then requires that binding to hold <i>everywhere</i>, in both
/// directions.</para>
///
/// <para>Binding rather than re-deriving the numbering is deliberate. Swift
/// numbers placeholders by first appearance in its <c>sortedKeys</c>-encoded
/// text, and reproducing that would mean reproducing Foundation's key-ordering
/// rule exactly — an assumption that could drift silently. A bijection is the
/// property that actually matters: it fails just as loudly if a rung mints in
/// the wrong place, mints the wrong number of ids, or wires two fields to
/// different ids where the vector says they share one (v1's
/// <c>activeItemID</c> and its item's <c>id</c>, for instance).</para>
///
/// <para>Numbers compare by value, not by token: the golden file is written
/// through a canonical JSON tree that keeps whole-valued doubles as integers, so
/// <c>60</c> there and <c>60</c> here must match without anyone caring which
/// side thought it was a <c>double</c>.</para>
/// </remarks>
internal sealed partial class MigratedModelComparer
{
    /// <summary>Cue-type filters persist as a Swift <c>Set&lt;UUID&gt;</c>, whose
    /// JSON order is randomised per process. Both sides sort before comparing.</summary>
    private const string UnorderedStringArrayKey = "includedTypeIDs";

    private readonly HashSet<string> carriedUuids;
    private readonly Dictionary<string, string> placeholderToActual = [];
    private readonly Dictionary<string, string> actualToPlaceholder = [];
    private readonly List<string> failures = [];

    private MigratedModelComparer(string inputJson)
    {
        carriedUuids = UuidPattern().Matches(inputJson)
            .Select(match => match.Value.ToUpperInvariant())
            .ToHashSet(StringComparer.Ordinal);
    }

    /// <summary>Returns every way <paramref name="actual"/> differs from
    /// <paramref name="expected"/>, or an empty list when they agree. Reporting
    /// all of them beats stopping at the first: a migration that drifts usually
    /// drifts in several fields at once, and one assertion per run would take as
    /// many runs to see the whole picture.</summary>
    public static IReadOnlyList<string> Differences(JsonNode? expected, JsonNode? actual, string inputJson)
    {
        var comparer = new MigratedModelComparer(inputJson);
        comparer.Compare(expected, actual, "$");
        return comparer.failures;
    }

    private void Compare(JsonNode? expected, JsonNode? actual, string path)
    {
        switch (expected)
        {
            case null:
                if (actual is not null)
                {
                    failures.Add($"{path}: expected absent, got {actual.ToJsonString()}");
                }

                return;

            case JsonObject expectedObject:
                CompareObject(expectedObject, actual as JsonObject, path);
                return;

            case JsonArray expectedArray:
                CompareArray(expectedArray, actual as JsonArray, path);
                return;

            default:
                CompareValue(expected, actual, path);
                return;
        }
    }

    private void CompareObject(JsonObject expected, JsonObject? actual, string path)
    {
        if (actual is null)
        {
            failures.Add($"{path}: expected an object");
            return;
        }

        foreach (var key in expected.Select(pair => pair.Key).Union(actual.Select(pair => pair.Key)).Order(StringComparer.Ordinal))
        {
            var hasExpected = expected.TryGetPropertyValue(key, out var expectedValue);
            var hasActual = actual.TryGetPropertyValue(key, out var actualValue);

            if (!hasExpected)
            {
                failures.Add($"{path}.{key}: unexpected key, got {actualValue?.ToJsonString() ?? "null"}");
                continue;
            }

            if (!hasActual)
            {
                failures.Add($"{path}.{key}: missing key, expected {expectedValue?.ToJsonString() ?? "null"}");
                continue;
            }

            if (key == UnorderedStringArrayKey
                && expectedValue is JsonArray expectedArray
                && actualValue is JsonArray actualArray)
            {
                CompareArray(Sorted(expectedArray), Sorted(actualArray), $"{path}.{key}");
                continue;
            }

            Compare(expectedValue, actualValue, $"{path}.{key}");
        }
    }

    private void CompareArray(JsonArray expected, JsonArray? actual, string path)
    {
        if (actual is null)
        {
            failures.Add($"{path}: expected an array");
            return;
        }

        if (expected.Count != actual.Count)
        {
            failures.Add($"{path}: expected {expected.Count} element(s), got {actual.Count}");
            return;
        }

        for (var index = 0; index < expected.Count; index++)
        {
            Compare(expected[index], actual[index], $"{path}[{index}]");
        }
    }

    private void CompareValue(JsonNode expected, JsonNode? actual, string path)
    {
        if (actual is null)
        {
            failures.Add($"{path}: expected {expected.ToJsonString()}, got null");
            return;
        }

        var expectedValue = expected.GetValueKind();
        var actualValue = actual.GetValueKind();

        switch (expectedValue)
        {
            case System.Text.Json.JsonValueKind.Number when actualValue == System.Text.Json.JsonValueKind.Number:
                var expectedNumber = expected.GetValue<double>();
                var actualNumber = actual.GetValue<double>();
                if (!expectedNumber.Equals(actualNumber))
                {
                    failures.Add($"{path}: expected {Format(expectedNumber)}, got {Format(actualNumber)}");
                }

                return;

            case System.Text.Json.JsonValueKind.String when actualValue == System.Text.Json.JsonValueKind.String:
                CompareString(expected.GetValue<string>(), actual.GetValue<string>(), path);
                return;

            default:
                if (expected.ToJsonString() != actual.ToJsonString())
                {
                    failures.Add($"{path}: expected {expected.ToJsonString()}, got {actual.ToJsonString()}");
                }

                return;
        }
    }

    private void CompareString(string expected, string actual, string path)
    {
        if (!expected.StartsWith("MINTED-", StringComparison.Ordinal))
        {
            if (!string.Equals(expected, actual, StringComparison.Ordinal))
            {
                failures.Add($"{path}: expected \"{expected}\", got \"{actual}\"");
            }

            return;
        }

        if (!UuidPattern().IsMatch(actual))
        {
            failures.Add($"{path}: expected a minted UUID for {expected}, got \"{actual}\"");
            return;
        }

        var minted = actual.ToUpperInvariant();
        if (carriedUuids.Contains(minted))
        {
            failures.Add(
                $"{path}: {expected} must be a freshly minted UUID, but \"{actual}\" was carried from the input");
            return;
        }

        if (placeholderToActual.TryGetValue(expected, out var boundActual) && boundActual != minted)
        {
            failures.Add($"{path}: {expected} is already bound to \"{boundActual}\" but here is \"{actual}\"");
            return;
        }

        if (actualToPlaceholder.TryGetValue(minted, out var boundPlaceholder) && boundPlaceholder != expected)
        {
            failures.Add($"{path}: \"{actual}\" is already bound to {boundPlaceholder} but here stands for {expected}");
            return;
        }

        placeholderToActual[expected] = minted;
        actualToPlaceholder[minted] = expected;
    }

    private static JsonArray Sorted(JsonArray array) =>
        new(array
            .Select(node => node?.ToJsonString() ?? "null")
            .Order(StringComparer.Ordinal)
            .Select(json => JsonNode.Parse(json))
            .ToArray());

    private static string Format(double value) => value.ToString("R", CultureInfo.InvariantCulture);

    [GeneratedRegex("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")]
    private static partial Regex UuidPattern();
}
