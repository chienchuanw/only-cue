import CoreGraphics
import Foundation

enum CueMarkersGeometry {

    static func position(forTime time: TimeInterval, width: CGFloat, duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    static func time(originalTime: TimeInterval, dx: CGFloat, width: CGFloat, duration: TimeInterval) -> TimeInterval {
        guard width > 0 else { return originalTime }
        let proposed = originalTime + Double(dx / width) * duration
        return min(max(proposed, 0), duration)
    }
}
