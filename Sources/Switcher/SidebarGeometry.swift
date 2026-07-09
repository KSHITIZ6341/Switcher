import CoreGraphics

enum SidebarGeometry {
    static let hiddenPeekWidth: CGFloat = 4
    static let edgeTriggerDistance: CGFloat = 8

    static func clampedSidebarWidth(_ width: CGFloat, displayFrame: CGRect) -> CGFloat {
        let displayMaximum = max(220, displayFrame.width * 0.95)
        let upperBound = min(PinnedAppConfig.maxWidth, displayMaximum)
        let lowerBound = min(PinnedAppConfig.minWidth, upperBound)
        return min(max(width, lowerBound), upperBound)
    }

    static func stackedFrames(
        count: Int,
        displayFrame: CGRect,
        edge: SidebarEdge,
        collapsed: Bool,
        width: CGFloat
    ) -> [CGRect] {
        guard count > 0 else {
            return []
        }

        let width = clampedSidebarWidth(width, displayFrame: displayFrame)
        let segmentHeight = displayFrame.height / CGFloat(count)
        let visibleX = edge == .left ? displayFrame.minX : displayFrame.maxX - width
        let collapsedX = edge == .left
            ? displayFrame.minX - width + hiddenPeekWidth
            : displayFrame.maxX - hiddenPeekWidth

        var frames: [CGRect] = []
        frames.reserveCapacity(count)

        for index in 0..<count {
            let top = displayFrame.maxY - (CGFloat(index) * segmentHeight)
            let bottom: CGFloat
            if index == count - 1 {
                bottom = displayFrame.minY
            } else {
                bottom = displayFrame.maxY - (CGFloat(index + 1) * segmentHeight)
            }

            frames.append(
                CGRect(
                    x: (collapsed ? collapsedX : visibleX).rounded(.toNearestOrAwayFromZero),
                    y: bottom.rounded(.toNearestOrAwayFromZero),
                    width: width.rounded(.toNearestOrAwayFromZero),
                    height: (top - bottom).rounded(.toNearestOrAwayFromZero)
                )
            )
        }

        return frames
    }

    static func regionFrame(
        for displayFrame: CGRect,
        edge: SidebarEdge,
        collapsed: Bool,
        width: CGFloat
    ) -> CGRect {
        let width = clampedSidebarWidth(width, displayFrame: displayFrame)
        let visibleX = edge == .left ? displayFrame.minX : displayFrame.maxX - width
        let collapsedX = edge == .left
            ? displayFrame.minX - width + hiddenPeekWidth
            : displayFrame.maxX - hiddenPeekWidth

        return CGRect(
            x: collapsed ? collapsedX : visibleX,
            y: displayFrame.minY,
            width: width,
            height: displayFrame.height
        )
    }

    static func edgeNear(point: CGPoint, displayFrame: CGRect) -> SidebarEdge? {
        if abs(point.x - displayFrame.minX) <= edgeTriggerDistance {
            return .left
        }

        if abs(point.x - displayFrame.maxX) <= edgeTriggerDistance {
            return .right
        }

        return nil
    }

    static func isNearEdge(_ point: CGPoint, displayFrame: CGRect, edge: SidebarEdge) -> Bool {
        guard point.y >= displayFrame.minY, point.y <= displayFrame.maxY else {
            return false
        }

        switch edge {
        case .left:
            return abs(point.x - displayFrame.minX) <= edgeTriggerDistance
        case .right:
            return abs(point.x - displayFrame.maxX) <= edgeTriggerDistance
        }
    }

    static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }

    static func hasManualFrameBreak(actual: CGRect, expected: CGRect, tolerance: CGFloat) -> Bool {
        frameDistance(actual, expected) > tolerance
    }

    static func convertQuartzBoundsToAppKit(_ quartzBounds: CGRect, screenFrames: [CGRect]) -> CGRect {
        let virtualDesktop = screenFrames.reduce(CGRect.null) { partial, screenFrame in
            partial.union(screenFrame)
        }

        guard !virtualDesktop.isNull else {
            return quartzBounds
        }

        let convertedY = virtualDesktop.maxY - quartzBounds.origin.y - quartzBounds.height
        return CGRect(x: quartzBounds.origin.x, y: convertedY, width: quartzBounds.width, height: quartzBounds.height)
    }

    static func appKitFrameContainsCursor(
        quartzBounds: CGRect,
        cursor: CGPoint,
        screenFrames: [CGRect]
    ) -> Bool {
        let appKitFrame = convertQuartzBoundsToAppKit(quartzBounds, screenFrames: screenFrames)
        return appKitFrame.contains(cursor)
    }
}
