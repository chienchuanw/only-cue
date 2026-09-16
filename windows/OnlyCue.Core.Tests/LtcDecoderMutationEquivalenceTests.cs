using OnlyCue.Core.Ltc;
using Xunit;

namespace OnlyCue.Core.Tests;

/// <summary>
/// The three mutants that survived the slice-3 mutation run, kept alive as
/// assertions instead of as a paragraph in a merged PR.
/// </summary>
/// <remarks>
/// <para>
/// Ten mutants were seeded into <see cref="LtcDecoder"/> and run against the whole
/// <c>ltc-decode-v1</c> matrix. Seven died immediately; two more (moving the
/// 80-bit advance inside the validity check, and never skipping at all) survived
/// and were killed by growing the contract — see
/// <c>spurious-sync-after-a-broken-frame</c>. Three are still alive:
/// </para>
/// <list type="number">
/// <item><b>threshold computed in <c>double</c></b> — <c>(double)0.3f * reference</c>
/// instead of the <c>float</c> product.</item>
/// <item><b><c>&lt;=</c> instead of <c>&lt;</c></b> in the half-bit cluster
/// filter.</item>
/// <item><b>banker's rounding</b> instead of half-away-from-zero in
/// <see cref="LtcDecoder.FramesPerSecond"/>.</item>
/// </list>
/// <para>
/// The spec's rule for a survivor is "prove equivalence over the reachable domain
/// empirically, or fix the contract". Each of these is equivalent <i>over this
/// contract's signals</i> — not in general — and the reason is always that the
/// mutated boundary falls in a gap the signals never reach. That is a property of
/// the matrix, so it is asserted per signal rather than argued once: add a signal
/// that does reach one of these boundaries and the corresponding test goes red,
/// which is the notice that the survivor has become a real gap and the mutant must
/// be re-run.
/// </para>
/// <para>
/// Each test also reports the measured margin, so a reviewer can see how much
/// headroom the claim has rather than only that it holds.
/// </para>
/// </remarks>
public class LtcDecoderMutationEquivalenceTests
{
    /// <summary>Every distinct signal in the contract, once. The <c>decode</c> op is
    /// emitted for all of them, so it is the complete list.</summary>
    private static IEnumerable<LtcDecodeCase> Signals =>
        LtcDecodeVector.Load().Cases.Where(c => c.Op == "decode");

    /// <summary>
    /// <b>Mutant 2 — the threshold's arithmetic width.</b> The comparator computes
    /// <c>0.3f * reference</c> as a <c>float</c> and compares <c>float</c> samples
    /// against it. Widening the product to <c>double</c> moves the boundary by up
    /// to an ulp of the threshold; the mutant is observable only if some sample
    /// lands inside that sub-ulp window.
    /// <para>
    /// None does. The signals are square waves with a handful of distinct
    /// magnitudes, and the closest any of them comes to the threshold is the DC
    /// ladder's 0.5146 rung, which was placed within ~1e-5 of the <i>latch root</i>.
    /// Measured worst case over the whole matrix: the nearest sample sits
    /// <b>9.44e4 widening-gaps</b> from the boundary, at
    /// <c>dc-offset/d0.5146</c>. Both branches are checked, because the negative one
    /// compares against <c>-threshold</c> and negation is exact in neither width's
    /// favour.
    /// </para>
    /// </summary>
    [Fact]
    public void ThresholdWidth_IsUnobservable_BecauseNoSampleLandsInTheSubUlpWindow()
    {
        var worst = double.PositiveInfinity;
        var worstLabel = "(none)";

        foreach (var goldenCase in Signals)
        {
            var samples = LtcDecodeRecipe.Samples(goldenCase.Input);
            var reference = LtcDecoder.Rms(samples);
            if (!(reference >= LtcDecoder.SilenceRmsFloor))
            {
                continue;  // the comparator never runs, so the threshold is unreached
            }

            var asFloat = LtcDecoder.ThresholdFraction * reference;
            var asDouble = (double)LtcDecoder.ThresholdFraction * reference;
            var gap = Math.Abs(asDouble - asFloat);

            foreach (var sample in samples)
            {
                Assert.Equal(sample > asFloat, sample > asDouble);
                Assert.Equal(sample < -asFloat, sample < -asDouble);

                // How far the nearest sample sits from the widened boundary,
                // measured in multiples of the gap the widening opens up.
                var margin = Math.Abs(Math.Abs((double)sample) - asDouble);
                var headroom = gap > 0 ? margin / gap : double.PositiveInfinity;
                if (headroom < worst)
                {
                    worst = headroom;
                    worstLabel = goldenCase.Label;
                }
            }
        }

        Assert.True(
            worst > 1,
            $"a sample now sits within one widening-gap of the threshold ({worstLabel}, "
            + $"{worst:G4} gaps) — mutant 2 is no longer equivalent and must be re-run");
    }

    /// <summary>
    /// <b>Mutant 5 — <c>&lt;</c> versus <c>&lt;=</c> in the cluster filter.</b> The
    /// two differ only on an interval exactly equal to <c>1.5 × smallest</c>.
    /// <para>
    /// Biphase-mark intervals are bimodal: a half-bit period <c>h</c> and a whole
    /// bit <c>2h</c>, each rounded to whole samples. <c>1.5h</c> sits strictly
    /// between the two modes, so no interval can land on it — which is why the
    /// mutant survives, and also why it is safe. Measured worst case over the whole
    /// matrix: <b>3.5 samples</b> clear of the boundary (interval 10 against a
    /// boundary of 13.5, at <c>clean/30@44100</c>). Asserted rather than argued,
    /// because a future signal at some other sample rate could in principle produce
    /// a rounding that lands there.
    /// </para>
    /// </summary>
    [Fact]
    public void ClusterFilterBoundary_IsUnobservable_BecauseNoIntervalLandsOnIt()
    {
        var worst = double.PositiveInfinity;
        var worstLabel = "(none)";

        foreach (var goldenCase in Signals)
        {
            var transitions = LtcDecoder.TransitionIndices(LtcDecodeRecipe.Samples(goldenCase.Input));
            var intervals = transitions.Skip(1)
                .Zip(transitions, (next, previous) => next - previous)
                .ToList();
            if (intervals.Count == 0)
            {
                continue;
            }

            var boundary = 1.5 * intervals.Min();
            foreach (var interval in intervals.Distinct())
            {
                var margin = Math.Abs(interval - boundary);
                if (margin < worst)
                {
                    worst = margin;
                    worstLabel = $"{goldenCase.Label} (interval {interval}, boundary {boundary})";
                }
            }
        }

        Assert.True(
            worst > 0,
            $"an interval now sits exactly on 1.5x the smallest ({worstLabel}) — mutant 5 "
            + "is no longer equivalent and must be re-run");
    }

    /// <summary>
    /// <b>Mutant 6 — half-away-from-zero versus banker's rounding.</b> The two
    /// differ only when <c>bitRate / 80</c> lands exactly on a <c>.5</c> tie.
    /// <para>
    /// No signal here produces one, and the recipe format cannot easily express one:
    /// the declared sample rate is also the rate the signal was generated at, so the
    /// measured half-bit period tracks it and the quotient lands on (or beside) the
    /// integer framerate. Measured worst case over the whole matrix: <b>0.363</b>
    /// from the nearest tie (<c>bitRate/80 = 30.137…</c>, at
    /// <c>clean/30df@44100</c>). The rounding mode is still the contract — it is
    /// what makes a genuinely off-rate recording round the same way on both
    /// platforms — so the distance to the nearest tie is measured rather than
    /// assumed to be large.
    /// </para>
    /// </summary>
    [Fact]
    public void RoundingMode_IsUnobservable_BecauseNoSignalLandsOnATie()
    {
        var worst = double.PositiveInfinity;
        var worstLabel = "(none)";

        foreach (var goldenCase in Signals)
        {
            var transitions = LtcDecoder.TransitionIndices(LtcDecodeRecipe.Samples(goldenCase.Input));
            if (transitions.Count < 3 || LtcDecoder.EstimateHalfBitSamples(transitions) is not { } halfBit)
            {
                continue;
            }

            var sampleRate = LtcDecodeRecipe.SampleRateOf(goldenCase.Input);
            var quotient = sampleRate / (2.0 * halfBit) / 80.0;
            var margin = Math.Abs(quotient - Math.Floor(quotient) - 0.5);
            if (margin < worst)
            {
                worst = margin;
                worstLabel = $"{goldenCase.Label} (bitRate/80 = {quotient:G17})";
            }
        }

        Assert.True(
            worst > 0,
            $"a signal now lands exactly on a rounding tie ({worstLabel}) — mutant 6 is no "
            + "longer equivalent and must be re-run");
    }
}
