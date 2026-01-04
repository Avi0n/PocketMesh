import SwiftUI

/// Canvas-based terrain profile visualization with Fresnel zone
struct TerrainProfileCanvas: View {
    let elevationProfile: [ElevationSample]
    let pointAHeight: Double
    let pointBHeight: Double
    let frequencyMHz: Double
    let refractionK: Double

    // MARK: - Colors (Colorblind-Safe)

    private let terrainFill = Color(red: 0.76, green: 0.70, blue: 0.60)
    private let terrainStroke = Color(red: 0.55, green: 0.47, blue: 0.36)
    private let fresnelOuter = Color.teal.opacity(0.25)
    private let fresnelInner = Color.teal.opacity(0.50)
    private let fresnelObstructed = Color.orange.opacity(0.9)
    private let fresnelBoundary = Color.teal.opacity(0.6)
    private let losLineColor = Color.primary
    private let gridColor = Color.gray.opacity(0.3)

    // MARK: - Layout Constants

    private let padding = EdgeInsets(top: 24, leading: 45, bottom: 28, trailing: 16)
    private let chartHeight: CGFloat = 200

    // MARK: - Computed Properties

    private var profileSamples: [ProfileSample] {
        FresnelZoneRenderer.buildProfileSamples(
            from: elevationProfile,
            pointAHeight: pointAHeight,
            pointBHeight: pointBHeight,
            frequencyMHz: frequencyMHz,
            refractionK: refractionK
        )
    }

    private var xRange: ClosedRange<Double> {
        guard let last = elevationProfile.last else { return 0...1 }
        return 0...max(1, last.distanceFromAMeters)
    }

    private var yRange: ClosedRange<Double> {
        guard !profileSamples.isEmpty else { return 0...100 }

        var minY = Double.infinity
        var maxY = -Double.infinity

        for sample in profileSamples {
            minY = min(minY, sample.yTerrain)
            maxY = max(maxY, sample.yTop)
        }

        guard minY.isFinite, maxY.isFinite, maxY > minY else { return 0...100 }

        let range = maxY - minY
        return (minY - range * 0.1)...(maxY + range * 0.2)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if elevationProfile.isEmpty {
                emptyState
            } else {
                chartCanvas
                legendView
                attributionText
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Data",
            systemImage: "chart.xyaxis.line",
            description: Text("Select two points to analyze")
        )
        .frame(height: chartHeight)
    }

    private var chartCanvas: some View {
        Canvas { context, size in
            let coords = ChartCoordinateSpace(
                canvasSize: size,
                padding: padding,
                xRange: xRange,
                yRange: yRange
            )

            drawGrid(context: context, coords: coords)
            drawFresnelZone(context: context, coords: coords)
            drawFresnelBoundary(context: context, coords: coords)
            drawTerrain(context: context, coords: coords)
            drawLOSLine(context: context, coords: coords)
            drawEndpointMarkers(context: context, coords: coords)
        }
        .frame(height: chartHeight)
    }

    private var legendView: some View {
        HStack(spacing: 16) {
            legendItem(color: terrainStroke, label: "Terrain")
            legendItem(color: losLineColor, label: "LOS")
            legendItem(color: fresnelOuter, label: "Clear")
            legendItem(color: fresnelObstructed, label: "Obstructed")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }

    private var attributionText: some View {
        Text("Elevation data: Copernicus DEM GLO-90 via Open-Meteo")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Axis Helpers

extension TerrainProfileCanvas {

    /// Calculate a "nice" step value for axis ticks
    /// Returns a step that produces clean numbers like 10, 25, 50, 100, etc.
    private func niceStep(for range: Double, targetDivisions: Int) -> Double {
        guard range > 0, targetDivisions > 0 else { return 1 }

        let roughStep = range / Double(targetDivisions)
        let magnitude = pow(10, floor(log10(roughStep)))
        let normalized = roughStep / magnitude

        // Snap to nice values: 1, 2, 2.5, 5, 10
        let niceNormalized: Double
        if normalized <= 1 {
            niceNormalized = 1
        } else if normalized <= 2 {
            niceNormalized = 2
        } else if normalized <= 2.5 {
            niceNormalized = 2.5
        } else if normalized <= 5 {
            niceNormalized = 5
        } else {
            niceNormalized = 10
        }

        return niceNormalized * magnitude
    }

    /// Generate tick values that start at a nice boundary
    private func tickValues(for range: ClosedRange<Double>, step: Double) -> [Double] {
        guard step > 0 else { return [] }

        let start = ceil(range.lowerBound / step) * step
        var ticks: [Double] = []
        var current = start

        while current <= range.upperBound {
            ticks.append(current)
            current += step
        }

        return ticks
    }
}

// MARK: - Draw Functions

extension TerrainProfileCanvas {

    private func drawGrid(context: GraphicsContext, coords: ChartCoordinateSpace) {
        // Calculate nice step values
        let yStep = niceStep(for: yRange.upperBound - yRange.lowerBound, targetDivisions: 4)
        let xStep = niceStep(for: xRange.upperBound - xRange.lowerBound, targetDivisions: 5)

        let yTicks = tickValues(for: yRange, step: yStep)
        let xTicks = tickValues(for: xRange, step: xStep)

        // Draw horizontal grid lines
        let gridPath = Path { path in
            for y in yTicks {
                let startPoint = coords.point(x: xRange.lowerBound, y: y)
                let endPoint = coords.point(x: xRange.upperBound, y: y)
                path.move(to: startPoint)
                path.addLine(to: endPoint)
            }
        }

        context.stroke(
            gridPath,
            with: .color(gridColor),
            style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])
        )

        // Y-axis labels (elevation in meters)
        for (index, y) in yTicks.enumerated() {
            let labelPoint = coords.point(x: xRange.lowerBound, y: y)
            let isLast = index == yTicks.count - 1
            let labelText = isLast ? "\(Int(y)) m" : "\(Int(y))"
            let label = Text(labelText)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            context.draw(label, at: CGPoint(x: labelPoint.x - 8, y: labelPoint.y), anchor: .trailing)
        }

        // X-axis labels (distance in km)
        for (index, x) in xTicks.enumerated() {
            let labelPoint = coords.point(x: x, y: yRange.lowerBound)
            let kmValue = x / 1000
            let isLast = index == xTicks.count - 1

            // Format based on step size - use integers for whole km values
            let labelText: String
            if xStep >= 1000 && kmValue.truncatingRemainder(dividingBy: 1) == 0 {
                labelText = isLast ? "\(Int(kmValue)) km" : "\(Int(kmValue))"
            } else {
                labelText = isLast
                    ? String(format: "%.1f km", kmValue)
                    : String(format: "%.1f", kmValue)
            }

            let label = Text(labelText)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            context.draw(label, at: CGPoint(x: labelPoint.x, y: labelPoint.y + 10), anchor: .top)
        }
    }

    private func drawFresnelZone(context: GraphicsContext, coords: ChartCoordinateSpace) {
        guard profileSamples.count >= 2 else { return }

        drawOuterFresnelFill(context: context, coords: coords)
        drawInnerFresnelFill(context: context, coords: coords)
        drawObstructionOverlay(context: context, coords: coords)
    }

    private func drawOuterFresnelFill(context: GraphicsContext, coords: ChartCoordinateSpace) {
        var path = Path()

        // Top edge: left to right
        if let first = profileSamples.first {
            path.move(to: coords.point(x: first.x, y: first.yTop))
        }
        for sample in profileSamples.dropFirst() {
            path.addLine(to: coords.point(x: sample.x, y: sample.yTop))
        }

        // Bottom edge: right to left (clamped to terrain)
        for sample in profileSamples.reversed() {
            path.addLine(to: coords.point(x: sample.x, y: sample.yVisibleBottom))
        }

        path.closeSubpath()
        context.fill(path, with: .color(fresnelOuter))
    }

    private func drawInnerFresnelFill(context: GraphicsContext, coords: ChartCoordinateSpace) {
        var path = Path()

        // Top edge: left to right
        if let first = profileSamples.first {
            path.move(to: coords.point(x: first.x, y: first.yTop60))
        }
        for sample in profileSamples.dropFirst() {
            path.addLine(to: coords.point(x: sample.x, y: sample.yTop60))
        }

        // Bottom edge: right to left (clamped to terrain)
        for sample in profileSamples.reversed() {
            path.addLine(to: coords.point(x: sample.x, y: sample.yVisibleBottom60))
        }

        path.closeSubpath()
        context.fill(path, with: .color(fresnelInner))
    }

    private func drawObstructionOverlay(context: GraphicsContext, coords: ChartCoordinateSpace) {
        // Find contiguous obstructed regions and draw orange overlay
        var inObstructedRegion = false
        var regionStart = 0

        for (index, sample) in profileSamples.enumerated() {
            if sample.isObstructed && !inObstructedRegion {
                // Start of obstructed region
                inObstructedRegion = true
                regionStart = index
            } else if !sample.isObstructed && inObstructedRegion {
                // End of obstructed region
                drawObstructedRegion(
                    context: context,
                    coords: coords,
                    startIndex: regionStart,
                    endIndex: index - 1
                )
                inObstructedRegion = false
            }
        }

        // Handle region that extends to end
        if inObstructedRegion {
            drawObstructedRegion(
                context: context,
                coords: coords,
                startIndex: regionStart,
                endIndex: profileSamples.count - 1
            )
        }
    }

    private func drawObstructedRegion(
        context: GraphicsContext,
        coords: ChartCoordinateSpace,
        startIndex: Int,
        endIndex: Int
    ) {
        guard startIndex <= endIndex else { return }

        let regionSamples = Array(profileSamples[startIndex...endIndex])
        guard let first = regionSamples.first else { return }

        var path = Path()

        // Top edge: left to right
        path.move(to: coords.point(x: first.x, y: first.yTop))
        for sample in regionSamples.dropFirst() {
            path.addLine(to: coords.point(x: sample.x, y: sample.yTop))
        }

        // Bottom edge: right to left (clamped to terrain)
        for sample in regionSamples.reversed() {
            path.addLine(to: coords.point(x: sample.x, y: sample.yVisibleBottom))
        }

        path.closeSubpath()
        context.fill(path, with: .color(fresnelObstructed))
    }

    private func drawFresnelBoundary(context: GraphicsContext, coords: ChartCoordinateSpace) {
        guard profileSamples.count >= 2 else { return }

        // Top boundary (theoretical ellipse top)
        var topPath = Path()
        if let first = profileSamples.first {
            topPath.move(to: coords.point(x: first.x, y: first.yTop))
        }
        for sample in profileSamples.dropFirst() {
            topPath.addLine(to: coords.point(x: sample.x, y: sample.yTop))
        }

        // Bottom boundary (theoretical ellipse bottom)
        var bottomPath = Path()
        if let first = profileSamples.first {
            bottomPath.move(to: coords.point(x: first.x, y: first.yBottom))
        }
        for sample in profileSamples.dropFirst() {
            bottomPath.addLine(to: coords.point(x: sample.x, y: sample.yBottom))
        }

        let style = StrokeStyle(lineWidth: 1, dash: [4, 3])
        context.stroke(topPath, with: .color(fresnelBoundary), style: style)
        context.stroke(bottomPath, with: .color(fresnelBoundary), style: style)
    }

    private func drawTerrain(context: GraphicsContext, coords: ChartCoordinateSpace) {
        guard profileSamples.count >= 2 else { return }

        // Build terrain fill path
        var fillPath = Path()

        // Start at bottom-left
        let bottomLeft = coords.point(x: xRange.lowerBound, y: yRange.lowerBound)
        fillPath.move(to: bottomLeft)

        // Trace terrain line
        for sample in profileSamples {
            fillPath.addLine(to: coords.point(x: sample.x, y: sample.yTerrain))
        }

        // Close at bottom-right and back
        let bottomRight = coords.point(x: xRange.upperBound, y: yRange.lowerBound)
        fillPath.addLine(to: bottomRight)
        fillPath.closeSubpath()

        // Fill terrain
        context.fill(fillPath, with: .color(terrainFill))

        // Build terrain stroke path (just the top edge)
        var strokePath = Path()
        if let first = profileSamples.first {
            strokePath.move(to: coords.point(x: first.x, y: first.yTerrain))
        }
        for sample in profileSamples.dropFirst() {
            strokePath.addLine(to: coords.point(x: sample.x, y: sample.yTerrain))
        }

        // Stroke terrain outline
        context.stroke(
            strokePath,
            with: .color(terrainStroke),
            style: StrokeStyle(lineWidth: 1.5)
        )
    }

    private func drawLOSLine(context: GraphicsContext, coords: ChartCoordinateSpace) {
        guard let first = profileSamples.first,
              let last = profileSamples.last else { return }

        var path = Path()
        path.move(to: coords.point(x: first.x, y: first.yLOS))
        path.addLine(to: coords.point(x: last.x, y: last.yLOS))

        context.stroke(
            path,
            with: .color(losLineColor),
            style: StrokeStyle(lineWidth: 2)
        )
    }

    private func drawEndpointMarkers(context: GraphicsContext, coords: ChartCoordinateSpace) {
        guard let first = profileSamples.first,
              let last = profileSamples.last else { return }

        let markerRadius: CGFloat = 6
        let markerColor = Color.orange

        // Point A marker
        let pointA = coords.point(x: first.x, y: first.yLOS)
        let circleA = Path(ellipseIn: CGRect(
            x: pointA.x - markerRadius,
            y: pointA.y - markerRadius,
            width: markerRadius * 2,
            height: markerRadius * 2
        ))
        context.fill(circleA, with: .color(markerColor))

        // Point B marker
        let pointB = coords.point(x: last.x, y: last.yLOS)
        let circleB = Path(ellipseIn: CGRect(
            x: pointB.x - markerRadius,
            y: pointB.y - markerRadius,
            width: markerRadius * 2,
            height: markerRadius * 2
        ))
        context.fill(circleB, with: .color(markerColor))

        // Labels
        context.draw(
            Text("A").font(.caption2).bold(),
            at: CGPoint(x: pointA.x + 12, y: pointA.y - 8)
        )
        context.draw(
            Text("B").font(.caption2).bold(),
            at: CGPoint(x: pointB.x - 12, y: pointB.y - 8)
        )
    }
}

#Preview("Canvas Profile") {
    let sampleProfile: [ElevationSample] = (0...20).map { i in
        let distance = Double(i) * 500
        let baseElevation = 100.0
        let hillFactor = sin(Double(i) / 20.0 * .pi) * 150

        return ElevationSample(
            coordinate: .init(latitude: 37.7749 + Double(i) * 0.001, longitude: -122.4194),
            elevation: baseElevation + hillFactor,
            distanceFromAMeters: distance
        )
    }

    return TerrainProfileCanvas(
        elevationProfile: sampleProfile,
        pointAHeight: 10,
        pointBHeight: 15,
        frequencyMHz: 906,
        refractionK: 4.0 / 3.0
    )
    .padding()
}
