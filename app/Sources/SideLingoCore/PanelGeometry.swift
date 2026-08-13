import AppKit

public enum PanelGeometry {
    public static func centeredFrame(size: NSSize, visibleFrame: NSRect) -> NSRect {
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        return NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
