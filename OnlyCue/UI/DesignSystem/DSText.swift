import SwiftUI

extension DS {

    /// Typography tokens. SF Pro (native semantic styles, Dynamic-Type aware)
    /// for chrome; SF Mono for every number and timecode.
    enum Text {
        static let title     = Font.title3.weight(.semibold)
        static let heading   = Font.body.weight(.semibold)
        static let body      = Font.body
        static let label     = Font.caption
        static let caption   = Font.system(size: 10, weight: .semibold)
        /// 11 pt sans — small secondary body text (e.g. the LTC strip clip-name
        /// header, Figma Inter Regular 11; #553). Sans, NOT monospaced.
        static let small     = Font.system(size: 11)
        static let monoHero  = Font.system(size: 21, weight: .semibold, design: .monospaced)
        static let mono      = Font.system(size: 13, design: .monospaced)
        static let monoSmall = Font.system(size: 11, design: .monospaced)
        /// 10 pt monospaced — sidebar clip length (Figma 318:1238, Roboto Mono 10).
        /// Size is exposed so `ItemRowMetrics.durationFontSize` (the fidelity
        /// gate) pins the value this token actually renders, not a parallel copy.
        static let monoLabelSize: CGFloat = 10
        static let monoLabel = Font.system(size: monoLabelSize, design: .monospaced)
        /// 9 pt monospaced — ruler tick labels (LTC strip, waveform time ruler).
        static let monoMicro = Font.system(size: 9, design: .monospaced)

        /// Tracking applied to `caption` for uppercase micro-labels.
        static let captionTracking: CGFloat = 0.7
    }
}
