import SwiftUI

/// A map-pin badge: a rounded rectangle body with a centered downward pointer
/// at the bottom (Figma 318:1303 CueMarker pin).
struct CuePinShape: Shape {

    var pointerHeight: CGFloat = 4
    var cornerRadius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let bodyHeight = max(0, rect.height - pointerHeight)
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bodyHeight),
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
        )
        // Downward pointer centered on the body's bottom edge.
        path.move(to: CGPoint(x: rect.midX - pointerHeight, y: bodyHeight))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX + pointerHeight, y: bodyHeight))
        path.closeSubpath()
        return path
    }
}
