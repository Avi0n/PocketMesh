import MapLibre
import UIKit

/// Font stack available on the OpenFreeMap glyph server.
/// MapLibre's default ("Open Sans Regular") returns 404, causing silent symbol dropout.
private nonisolated(unsafe) let mapFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])

// MARK: - Layer and source identifiers

enum MapLayerID {
    static let clusterCircles = "cluster-circles"
    static let clusterLabels = "cluster-labels"
    static let unclusteredIcons = "unclustered-icons"
    static let nameLabels = "name-labels"
    static let badgeText = "badge-text"
    static let fixedIcons = "fixed-icons"
    static let fixedNameLabels = "fixed-name-labels"
    static let fixedBadgeText = "fixed-badge-text"
    static let lineLOS = "line-los"
    static let lineTraceUntraced = "line-trace-untraced"
    static let lineTraceWeak = "line-trace-weak"
    static let lineTraceMedium = "line-trace-medium"
    static let lineTraceGood = "line-trace-good"
    static let satelliteLayer = "satellite-layer"
    static let topoLayer = "topo-layer"
}

enum MapSourceID {
    static let points = "points"
    static let fixedPoints = "fixed-points"
    static let lines = "lines"
    static let satelliteTiles = "satellite-tiles"
    static let topoTiles = "topo-tiles"
}

extension MC1MapView.Coordinator {

    // MARK: - Update point source data

    /// Point sources and layers use deferred creation: they are created here
    /// on first data arrival, not during style load. This avoids a MapLibre
    /// bug where sources initialized without features ignore later `.shape`
    /// updates.
    func updatePointSource(mapView: MLNMapView) {
        guard let style = mapView.style else { return }

        var clusterablePoints: [MapPoint] = []
        var fixedPoints: [MapPoint] = []
        for point in currentPoints {
            if point.isClusterable {
                clusterablePoints.append(point)
            } else {
                fixedPoints.append(point)
            }
        }

        // Clustered source — deferred creation on first data arrival
        if let source = clusterSource {
            source.shape = MLNShapeCollectionFeature(
                shapes: clusterablePoints.map { pointFeature(for: $0) }
            )
        } else if !clusterablePoints.isEmpty {
            let features = clusterablePoints.map { pointFeature(for: $0) }
            let source = MLNShapeSource(
                identifier: MapSourceID.points,
                features: features,
                options: [
                    .clustered: true,
                    .clusterRadius: 44,
                    .maximumZoomLevelForClustering: 14,
                ]
            )
            style.addSource(source)
            self.clusterSource = source
            addClusteredPointLayers(source: source, style: style)
        }

        // Fixed source — deferred creation
        if let source = fixedSource {
            source.shape = MLNShapeCollectionFeature(
                shapes: fixedPoints.map { pointFeature(for: $0) }
            )
        } else if !fixedPoints.isEmpty {
            let features = fixedPoints.map { pointFeature(for: $0) }
            let source = MLNShapeSource(identifier: MapSourceID.fixedPoints, features: features, options: nil)
            style.addSource(source)
            self.fixedSource = source
            addFixedPointLayers(source: source, style: style)
        }
    }

    func updateLabelVisibility(mapView: MLNMapView, showLabels: Bool) {
        for layerId in [MapLayerID.nameLabels, MapLayerID.fixedNameLabels] {
            guard let layer = mapView.style?.layer(withIdentifier: layerId) as? MLNSymbolStyleLayer else { continue }
            layer.isVisible = showLabels
        }
    }

    // MARK: - Clustered point layers

    private func addClusteredPointLayers(source: MLNShapeSource, style: MLNStyle) {
        // Cluster circles
        let circleLayer = MLNCircleStyleLayer(identifier: MapLayerID.clusterCircles, source: source)
        circleLayer.predicate = NSPredicate(format: "cluster == YES")
        let radiusStops: [NSNumber: NSNumber] = [0: 18, 50: 24, 100: 30, 200: 38]
        circleLayer.circleRadius = NSExpression(
            forMLNStepping: NSExpression(forKeyPath: "point_count"),
            from: NSExpression(forConstantValue: 18),
            stops: NSExpression(forConstantValue: radiusStops)
        )
        circleLayer.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
        circleLayer.circleOpacity = NSExpression(forConstantValue: 0.85)
        circleLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white.withAlphaComponent(0.8))
        circleLayer.circleStrokeWidth = NSExpression(forConstantValue: 2)
        style.addLayer(circleLayer)

        // Cluster count labels
        let clusterLabelLayer = MLNSymbolStyleLayer(identifier: MapLayerID.clusterLabels, source: source)
        clusterLabelLayer.predicate = NSPredicate(format: "cluster == YES")
        clusterLabelLayer.text = NSExpression(format: "CAST(point_count, 'NSString')")
        clusterLabelLayer.textColor = NSExpression(forConstantValue: UIColor.white)
        clusterLabelLayer.textFontSize = NSExpression(forConstantValue: 13)
        clusterLabelLayer.textFontNames = mapFontNames
        clusterLabelLayer.textAllowsOverlap = NSExpression(forConstantValue: true)
        clusterLabelLayer.textIgnoresPlacement = NSExpression(forConstantValue: true)
        style.addLayer(clusterLabelLayer)

        // Unclustered pin icons
        let iconLayer = MLNSymbolStyleLayer(identifier: MapLayerID.unclusteredIcons, source: source)
        iconLayer.predicate = NSPredicate(format: "cluster != YES")
        iconLayer.iconImageName = NSExpression(forKeyPath: "spriteName")
        iconLayer.iconAnchor = NSExpression(forConstantValue: "bottom")
        iconLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        iconLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        iconLayer.text = nil
        style.addLayer(iconLayer)

        // Name labels (above pins) with pill background
        let nameLabelLayer = MLNSymbolStyleLayer(identifier: MapLayerID.nameLabels, source: source)
        nameLabelLayer.predicate = NSPredicate(format: "cluster != YES AND nameLabel != nil")
        configureNameLabelLayer(nameLabelLayer)
        style.addLayer(nameLabelLayer)

        // Stats badge text (trace path midpoints) with pill background
        let badgeLayer = MLNSymbolStyleLayer(identifier: MapLayerID.badgeText, source: source)
        badgeLayer.predicate = NSPredicate(format: "cluster != YES AND badgeText != nil")
        configureBadgeLayer(badgeLayer)
        style.addLayer(badgeLayer)
    }

    // MARK: - Fixed point layers

    private func addFixedPointLayers(source: MLNShapeSource, style: MLNStyle) {
        let fixedIconLayer = MLNSymbolStyleLayer(identifier: MapLayerID.fixedIcons, source: source)
        fixedIconLayer.iconImageName = NSExpression(forKeyPath: "spriteName")
        fixedIconLayer.iconAnchor = NSExpression(forConstantValue: "bottom")
        fixedIconLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        fixedIconLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        fixedIconLayer.text = nil
        style.addLayer(fixedIconLayer)

        let fixedNameLayer = MLNSymbolStyleLayer(identifier: MapLayerID.fixedNameLabels, source: source)
        fixedNameLayer.predicate = NSPredicate(format: "nameLabel != nil")
        configureNameLabelLayer(fixedNameLayer)
        style.addLayer(fixedNameLayer)

        let fixedBadgeLayer = MLNSymbolStyleLayer(identifier: MapLayerID.fixedBadgeText, source: source)
        fixedBadgeLayer.predicate = NSPredicate(format: "badgeText != nil")
        configureBadgeLayer(fixedBadgeLayer)
        style.addLayer(fixedBadgeLayer)
    }

    // MARK: - Line layers

    func setupLineLayers(style: MLNStyle) {
        guard style.source(withIdentifier: MapSourceID.lines) == nil else { return }
        let source = MLNShapeSource(identifier: MapSourceID.lines, features: [], options: nil)
        style.addSource(source)

        let losLayer = MLNLineStyleLayer(identifier: MapLayerID.lineLOS, source: source)
        losLayer.predicate = NSPredicate(format: "lineStyle == %@", MapLine.LineStyle.los.rawValue)
        losLayer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
        losLayer.lineWidth = NSExpression(forConstantValue: 3)
        losLayer.lineDashPattern = NSExpression(forConstantValue: [8, 4])
        losLayer.lineOpacity = NSExpression(forKeyPath: "segmentOpacity")
        style.addLayer(losLayer)

        let untracedLayer = MLNLineStyleLayer(identifier: MapLayerID.lineTraceUntraced, source: source)
        untracedLayer.predicate = NSPredicate(format: "lineStyle == %@", MapLine.LineStyle.traceUntraced.rawValue)
        untracedLayer.lineColor = NSExpression(forConstantValue: UIColor.systemGray)
        untracedLayer.lineWidth = NSExpression(forConstantValue: 2)
        untracedLayer.lineDashPattern = NSExpression(forConstantValue: [8, 6])
        style.addLayer(untracedLayer)

        let weakLayer = MLNLineStyleLayer(identifier: MapLayerID.lineTraceWeak, source: source)
        weakLayer.predicate = NSPredicate(format: "lineStyle == %@", MapLine.LineStyle.traceWeak.rawValue)
        weakLayer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
        weakLayer.lineWidth = NSExpression(forConstantValue: 3)
        weakLayer.lineDashPattern = NSExpression(forConstantValue: [4, 4])
        style.addLayer(weakLayer)

        let mediumLayer = MLNLineStyleLayer(identifier: MapLayerID.lineTraceMedium, source: source)
        mediumLayer.predicate = NSPredicate(format: "lineStyle == %@", MapLine.LineStyle.traceMedium.rawValue)
        mediumLayer.lineColor = NSExpression(forConstantValue: UIColor.systemYellow)
        mediumLayer.lineWidth = NSExpression(forConstantValue: 3)
        mediumLayer.lineDashPattern = NSExpression(forConstantValue: [12, 4])
        style.addLayer(mediumLayer)

        let goodLayer = MLNLineStyleLayer(identifier: MapLayerID.lineTraceGood, source: source)
        goodLayer.predicate = NSPredicate(format: "lineStyle == %@", MapLine.LineStyle.traceGood.rawValue)
        goodLayer.lineColor = NSExpression(forConstantValue: UIColor.systemGreen)
        goodLayer.lineWidth = NSExpression(forConstantValue: 4)
        style.addLayer(goodLayer)
    }

    func updateLineSource(mapView: MLNMapView) {
        guard let source = mapView.style?.source(withIdentifier: MapSourceID.lines) as? MLNShapeSource else { return }

        let features = currentLines.map { line -> MLNPolylineFeature in
            var coords = line.coordinates
            let feature = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            feature.attributes = [
                "lineStyle": line.style.rawValue,
                "segmentOpacity": line.opacity,
            ]
            return feature
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    // MARK: - Raster tile sources

    func setupRasterSources(style: MLNStyle, mapView: MLNMapView) {
        guard style.source(withIdentifier: MapSourceID.satelliteTiles) == nil else {
            updateRasterLayerVisibility(mapView: mapView)
            return
        }
        let satSource = MLNRasterTileSource(
            identifier: MapSourceID.satelliteTiles,
            tileURLTemplates: [MapTileURLs.esriWorldImagery],
            options: [
                .tileSize: 256,
                .maximumZoomLevel: 19,
                .attributionHTMLString: "<a href=\"https://www.esri.com\">Esri</a>",
            ]
        )
        style.addSource(satSource)
        let satLayer = MLNRasterStyleLayer(identifier: MapLayerID.satelliteLayer, source: satSource)
        satLayer.isVisible = false
        style.addLayer(satLayer)

        let topoSource = MLNRasterTileSource(
            identifier: MapSourceID.topoTiles,
            tileURLTemplates: [MapTileURLs.openTopoMapA],
            options: [
                .tileSize: 256,
                .maximumZoomLevel: 17,
                .attributionHTMLString: "<a href=\"https://opentopomap.org\">OpenTopoMap</a>",
            ]
        )
        style.addSource(topoSource)
        let topoLayer = MLNRasterStyleLayer(identifier: MapLayerID.topoLayer, source: topoSource)
        topoLayer.isVisible = false
        style.addLayer(topoLayer)

        updateRasterLayerVisibility(mapView: mapView)
    }

    func updateRasterLayerVisibility(mapView: MLNMapView) {
        guard let style = mapView.style else { return }
        style.layer(withIdentifier: MapLayerID.satelliteLayer)?.isVisible = currentMapStyle == .satellite
        style.layer(withIdentifier: MapLayerID.topoLayer)?.isVisible = currentMapStyle == .topo
    }

    // MARK: - Shared layer configuration

    private func configureNameLabelLayer(_ layer: MLNSymbolStyleLayer) {
        layer.text = NSExpression(forKeyPath: "nameLabel")
        layer.textFontSize = NSExpression(forConstantValue: 10)
        layer.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
        layer.textColor = NSExpression(forConstantValue: UIColor.black)
        layer.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -4.8)))
        layer.textAnchor = NSExpression(forConstantValue: "bottom")
        layer.textAllowsOverlap = NSExpression(forConstantValue: true)
        layer.textIgnoresPlacement = NSExpression(forConstantValue: true)
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        layer.iconImageName = NSExpression(forConstantValue: "pill-bg")
        layer.iconTextFit = NSExpression(forConstantValue: NSValue(mlnIconTextFit: .both))
        layer.iconTextFitPadding = NSExpression(forConstantValue: NSValue(uiEdgeInsets: UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)))
    }

    private func configureBadgeLayer(_ layer: MLNSymbolStyleLayer) {
        layer.text = NSExpression(forKeyPath: "badgeText")
        layer.textFontSize = NSExpression(forConstantValue: 11)
        layer.textFontNames = mapFontNames
        layer.textColor = NSExpression(forConstantValue: UIColor.black)
        layer.textAllowsOverlap = NSExpression(forConstantValue: true)
        layer.textIgnoresPlacement = NSExpression(forConstantValue: true)
        layer.iconImageName = NSExpression(forConstantValue: "pill-bg")
        layer.iconTextFit = NSExpression(forConstantValue: NSValue(mlnIconTextFit: .both))
        layer.iconTextFitPadding = NSExpression(forConstantValue: NSValue(uiEdgeInsets: UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)))
    }

    // MARK: - Private helpers

    private func pointFeature(for point: MapPoint) -> MLNPointFeature {
        let feature = MLNPointFeature()
        feature.coordinate = point.coordinate
        var attributes: [String: Any] = [
            "pointId": point.id.uuidString,
            "spriteName": spriteName(for: point),
        ]
        if let label = point.label { attributes["nameLabel"] = label }
        if let hopIndex = point.hopIndex { attributes["hopIndex"] = "\(hopIndex)" }
        if let badgeText = point.badgeText { attributes["badgeText"] = badgeText }
        feature.attributes = attributes
        return feature
    }

    private func spriteName(for point: MapPoint) -> String {
        switch point.pinStyle {
        case .contactChat: "pin-chat"
        case .contactRepeater: "pin-repeater"
        case .contactRoom: "pin-room"
        case .repeater: "pin-repeater"
        case .repeaterRingBlue: "pin-repeater-ring-blue"
        case .repeaterRingGreen: "pin-repeater-ring-green"
        case .repeaterRingWhite:
            if let hop = point.hopIndex {
                "pin-repeater-ring-white-hop-\(min(hop, 20))"
            } else {
                "pin-repeater-ring-white"
            }
        case .pointA: "pin-point-a"
        case .pointB: "pin-point-b"
        case .crosshair: "pin-crosshair"
        case .badge: "pin-badge"
        }
    }
}
