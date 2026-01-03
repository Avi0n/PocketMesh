import SwiftUI
import Testing
@testable import PocketMesh

@Suite("ChartCoordinateSpace Tests")
struct ChartCoordinateSpaceTests {

    @Test("xPixel returns leading padding at xRange.lowerBound")
    func xPixelAtLowerBound() {
        let space = ChartCoordinateSpace(
            canvasSize: CGSize(width: 400, height: 200),
            padding: EdgeInsets(top: 20, leading: 40, bottom: 30, trailing: 50),
            xRange: 0...10000,
            yRange: 0...500
        )

        let pixel = space.xPixel(0)
        #expect(pixel == 40) // leading padding
    }

    @Test("xPixel returns width minus trailing padding at xRange.upperBound")
    func xPixelAtUpperBound() {
        let space = ChartCoordinateSpace(
            canvasSize: CGSize(width: 400, height: 200),
            padding: EdgeInsets(top: 20, leading: 40, bottom: 30, trailing: 50),
            xRange: 0...10000,
            yRange: 0...500
        )

        let pixel = space.xPixel(10000)
        #expect(pixel == 350) // 400 - 50 trailing
    }

    @Test("yPixel returns height minus bottom padding at yRange.lowerBound (inverted)")
    func yPixelAtLowerBound() {
        let space = ChartCoordinateSpace(
            canvasSize: CGSize(width: 400, height: 200),
            padding: EdgeInsets(top: 20, leading: 40, bottom: 30, trailing: 50),
            xRange: 0...10000,
            yRange: 0...500
        )

        // At y=0 (lowest elevation), should be at bottom of plot area
        let pixel = space.yPixel(0)
        #expect(pixel == 170) // 200 - 30 bottom padding
    }

    @Test("yPixel returns top padding at yRange.upperBound (inverted)")
    func yPixelAtUpperBound() {
        let space = ChartCoordinateSpace(
            canvasSize: CGSize(width: 400, height: 200),
            padding: EdgeInsets(top: 20, leading: 40, bottom: 30, trailing: 50),
            xRange: 0...10000,
            yRange: 0...500
        )

        // At y=500 (highest elevation), should be at top of plot area
        let pixel = space.yPixel(500)
        #expect(pixel == 20) // top padding
    }

    @Test("point combines xPixel and yPixel")
    func pointCombinesXAndY() {
        let space = ChartCoordinateSpace(
            canvasSize: CGSize(width: 400, height: 200),
            padding: EdgeInsets(top: 20, leading: 40, bottom: 30, trailing: 50),
            xRange: 0...10000,
            yRange: 0...500
        )

        let pt = space.point(x: 5000, y: 250)
        #expect(pt.x == 195) // midpoint of plot area x
        #expect(pt.y == 95)  // midpoint of plot area y
    }

    @Test("xLabel converts meters to km string")
    func xLabelFormatsKm() {
        let space = ChartCoordinateSpace(
            canvasSize: CGSize(width: 400, height: 200),
            padding: EdgeInsets(top: 20, leading: 40, bottom: 30, trailing: 50),
            xRange: 0...10000,
            yRange: 0...500
        )

        #expect(space.xLabel(0) == "0.0")
        #expect(space.xLabel(5000) == "5.0")
        #expect(space.xLabel(10000) == "10.0")
    }
}
