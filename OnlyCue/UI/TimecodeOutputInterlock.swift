import Foundation

/// Whether a timecode generator is armed, and the transport therefore locked to
/// 1.0× playback (epic #794).
///
/// Both generators free-run at the nominal framerate rather than chasing the
/// player, so off-speed playback would emit timecode that no longer describes
/// the media. LTC has always blocked this; MTC has exactly the same property, so
/// the gate is about *timecode output* rather than about LTC specifically — which
/// is why `PlaybackRateController` now takes `timecodeOutputEnabled`.
///
/// A one-line rule, given its own type so the OR is stated once and tested,
/// instead of being repeated at each of the five call sites that need it.
enum TimecodeOutputInterlock {

    static func isEngaged(ltcEnabled: Bool, mtcEnabled: Bool) -> Bool {
        ltcEnabled || mtcEnabled
    }

    /// The interlock as the live stores currently see it.
    @MainActor
    static var isEngagedNow: Bool {
        isEngaged(
            ltcEnabled: LTCRoutingStore.shared.settings.isEnabled,
            mtcEnabled: MTCOutputStore.shared.settings.isEnabled
        )
    }
}
