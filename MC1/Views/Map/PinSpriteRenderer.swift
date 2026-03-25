import MapLibre
import UIKit

enum PinSpriteRenderer {
    /// Height of a standard pin sprite in points (circle + triangle pointer).
    /// Used by the map Coordinator to position callout anchors above the pin icon.
    static let standardHeight: CGFloat = 43 // 36 (circle) + 10 (triangle) - 3 (overlap)

    private nonisolated(unsafe) static var cachedImages: [String: UIImage]?

    /// Registers base pin sprites into the style. Hop-ring variants are rendered
    /// lazily via `renderOnDemand(name:into:)` when MapLibre requests a missing image.
    static func renderAll(into style: MLNStyle) {
        let images: [String: UIImage]
        if let cached = cachedImages {
            images = cached
        } else {
            var rendered: [String: UIImage] = [:]
            for spec in allSpecs {
                rendered[spec.name] = render(spec)
            }
            rendered["pin-badge"] = UIGraphicsImageRenderer(
                size: CGSize(width: 1, height: 1), format: .preferred()
            ).image { _ in }
            rendered["pill-bg"] = renderPillBackground()
            cachedImages = rendered
            images = rendered
        }

        for (name, image) in images {
            style.setImage(image, forName: name)
        }
    }

    /// Renders a hop-ring sprite on demand when MapLibre requests a missing image name.
    /// Returns `true` if the name was recognized and the image was registered.
    @discardableResult
    static func renderOnDemand(name: String, into style: MLNStyle) -> Bool {
        guard name.hasPrefix("pin-repeater-ring-white-hop-") else { return false }

        // Check the cache first (may have been rendered for a different style load)
        if let cached = cachedImages?[name] {
            style.setImage(cached, forName: name)
            return true
        }

        guard let hopString = name.split(separator: "-").last,
              let hop = Int(hopString),
              (1...20).contains(hop),
              let ringWhiteSpec = allSpecs.first(where: { $0.name == "pin-repeater-ring-white" }) else {
            return false
        }

        let image = render(ringWhiteSpec, hopIndex: hop)
        cachedImages?[name] = image
        style.setImage(image, forName: name)
        return true
    }

    // MARK: - Sprite specifications

    private struct SpriteSpec {
        let name: String
        let circleColor: UIColor
        let iconName: String?    // SF Symbol name
        let text: String?        // e.g. "A", "B" for point pins
        let ringColor: UIColor?  // selection ring
        let isCrosshair: Bool
    }

    private static let allSpecs: [SpriteSpec] = [
        // Main map contacts
        SpriteSpec(name: "pin-chat", circleColor: UIColor(red: 204 / 255, green: 122 / 255, blue: 92 / 255, alpha: 1),
                   iconName: "person.fill", text: nil, ringColor: nil, isCrosshair: false),
        SpriteSpec(name: "pin-repeater", circleColor: .systemCyan,
                   iconName: "antenna.radiowaves.left.and.right", text: nil, ringColor: nil, isCrosshair: false),
        SpriteSpec(name: "pin-room", circleColor: UIColor(red: 1, green: 136 / 255, blue: 0, alpha: 1),
                   iconName: "person.3.fill", text: nil, ringColor: nil, isCrosshair: false),

        // LOS/TracePath repeater states
        SpriteSpec(name: "pin-repeater-ring-blue", circleColor: .systemCyan,
                   iconName: "antenna.radiowaves.left.and.right", text: nil, ringColor: .systemBlue, isCrosshair: false),
        SpriteSpec(name: "pin-repeater-ring-green", circleColor: .systemCyan,
                   iconName: "antenna.radiowaves.left.and.right", text: nil, ringColor: .systemGreen, isCrosshair: false),
        SpriteSpec(name: "pin-repeater-ring-white", circleColor: .systemCyan,
                   iconName: "antenna.radiowaves.left.and.right", text: nil, ringColor: .white, isCrosshair: false),

        // LOS point pins
        SpriteSpec(name: "pin-point-a", circleColor: .systemBlue,
                   iconName: nil, text: "A", ringColor: nil, isCrosshair: false),
        SpriteSpec(name: "pin-point-b", circleColor: .systemGreen,
                   iconName: nil, text: "B", ringColor: nil, isCrosshair: false),

        // LOS crosshair target
        SpriteSpec(name: "pin-crosshair", circleColor: .systemPurple,
                   iconName: nil, text: "R", ringColor: nil, isCrosshair: true),
    ]

    // MARK: - Rendering

    private static func render(_ spec: SpriteSpec, hopIndex: Int? = nil) -> UIImage {
        if spec.isCrosshair {
            return renderCrosshair(spec)
        }

        let circleSize: CGFloat = 36
        let iconSize: CGFloat = 16
        let triangleSize: CGFloat = 10
        let ringPadding: CGFloat = spec.ringColor != nil ? 4 : 0
        let ringSize: CGFloat = spec.ringColor != nil ? 44 : 0
        let totalWidth = max(circleSize, ringSize)
        let totalHeight = circleSize + triangleSize - 3 + ringPadding

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight), format: .preferred())
        return renderer.image { ctx in
            let cgContext = ctx.cgContext
            let centerX = totalWidth / 2

            // Selection ring
            if let ringColor = spec.ringColor {
                let ringRect = CGRect(
                    x: centerX - ringSize / 2,
                    y: ringPadding,
                    width: ringSize,
                    height: ringSize
                )
                ringColor.setStroke()
                cgContext.setLineWidth(3)
                cgContext.strokeEllipse(in: ringRect.insetBy(dx: 1.5, dy: 1.5))
            }

            // Circle shadow
            cgContext.saveGState()
            cgContext.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            let circleRect = CGRect(
                x: centerX - circleSize / 2,
                y: ringPadding,
                width: circleSize,
                height: circleSize
            )
            spec.circleColor.setFill()
            cgContext.fillEllipse(in: circleRect)
            cgContext.restoreGState()

            // Circle (again without shadow for crisp edge)
            spec.circleColor.setFill()
            cgContext.fillEllipse(in: circleRect)

            // Icon or text
            if let iconName = spec.iconName {
                let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
                if let icon = UIImage(systemName: iconName, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                    let iconRect = CGRect(
                        x: centerX - icon.size.width / 2,
                        y: circleRect.midY - icon.size.height / 2,
                        width: icon.size.width,
                        height: icon.size.height
                    )
                    icon.draw(in: iconRect)
                }
            } else if let text = spec.text {
                let font = UIFont.systemFont(ofSize: 14, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let size = (text as NSString).size(withAttributes: attrs)
                let textRect = CGRect(
                    x: centerX - size.width / 2,
                    y: circleRect.midY - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                (text as NSString).draw(in: textRect, withAttributes: attrs)
            }

            // Triangle pointer
            let triangleTop = circleRect.maxY - 3
            let path = UIBezierPath()
            path.move(to: CGPoint(x: centerX - triangleSize / 2, y: triangleTop))
            path.addLine(to: CGPoint(x: centerX + triangleSize / 2, y: triangleTop))
            path.addLine(to: CGPoint(x: centerX, y: triangleTop + triangleSize))
            path.close()
            spec.circleColor.setFill()
            path.fill()

            // Hop badge overlay (ring pins only)
            if let hopIndex, spec.ringColor != nil {
                let badgeSize: CGFloat = 18
                let badgeX = circleRect.maxX + 4 - badgeSize
                let badgeY = circleRect.minY
                let badgeRect = CGRect(x: badgeX, y: badgeY, width: badgeSize, height: badgeSize)

                UIColor.systemBlue.setFill()
                cgContext.fillEllipse(in: badgeRect)

                let text = "\(hopIndex)"
                let font = UIFont.systemFont(ofSize: 11, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let textSize = (text as NSString).size(withAttributes: attrs)
                let textRect = CGRect(
                    x: badgeRect.midX - textSize.width / 2,
                    y: badgeRect.midY - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                (text as NSString).draw(in: textRect, withAttributes: attrs)
            }
        }
    }

    // MARK: - Pill sprites

    /// Semi-transparent stretchable pill for name labels and stats badges.
    /// Registered as a resizable image so MapLibre's `iconTextFit` can stretch
    /// the flat center while preserving the rounded caps.
    private static func renderPillBackground() -> UIImage {
        let cornerRadius: CGFloat = 4
        let size: CGFloat = 2 * cornerRadius + 2
        let shadowPadding: CGFloat = 1
        let totalSize = size + shadowPadding * 2
        let capInset = cornerRadius + shadowPadding

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalSize, height: totalSize), format: .preferred())
        let image = renderer.image { ctx in
            let cgContext = ctx.cgContext
            let pillRect = CGRect(x: shadowPadding, y: shadowPadding, width: size, height: size)
            let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: cornerRadius)

            // Shadow pass
            cgContext.saveGState()
            cgContext.setShadow(
                offset: CGSize(width: 0, height: 0.5),
                blur: 1,
                color: UIColor.black.withAlphaComponent(0.15).cgColor
            )
            UIColor.white.setFill()
            pillPath.fill()
            cgContext.restoreGState()

            // Single fill at reduced opacity to approximate translucent blur
            UIColor.secondarySystemBackground.withAlphaComponent(0.75).setFill()
            pillPath.fill()
        }

        return image.resizableImage(
            withCapInsets: UIEdgeInsets(top: capInset, left: capInset, bottom: capInset, right: capInset),
            resizingMode: .stretch
        )
    }

    private static func renderCrosshair(_ spec: SpriteSpec) -> UIImage {
        let size: CGFloat = 44
        let gapRadius: CGFloat = 4
        let outerRadius = size / 2
        let badgeHeight: CGFloat = 20
        let totalHeight = size + badgeHeight + 2

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: totalHeight), format: .preferred())
        return renderer.image { ctx in
            let cgContext = ctx.cgContext
            let center = CGPoint(x: size / 2, y: size / 2)

            // Crosshair lines
            cgContext.setStrokeColor(UIColor.systemPurple.cgColor)
            cgContext.setLineWidth(2)

            // Vertical
            cgContext.move(to: CGPoint(x: center.x, y: center.y - outerRadius))
            cgContext.addLine(to: CGPoint(x: center.x, y: center.y - gapRadius))
            cgContext.move(to: CGPoint(x: center.x, y: center.y + gapRadius))
            cgContext.addLine(to: CGPoint(x: center.x, y: center.y + outerRadius))

            // Horizontal
            cgContext.move(to: CGPoint(x: center.x - outerRadius, y: center.y))
            cgContext.addLine(to: CGPoint(x: center.x - gapRadius, y: center.y))
            cgContext.move(to: CGPoint(x: center.x + gapRadius, y: center.y))
            cgContext.addLine(to: CGPoint(x: center.x + outerRadius, y: center.y))
            cgContext.strokePath()

            // "R" badge
            let badgeWidth: CGFloat = 20
            let badgeRect = CGRect(x: center.x - badgeWidth / 2, y: size + 2, width: badgeWidth, height: badgeHeight)
            let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 9)
            UIColor.systemPurple.setFill()
            badgePath.fill()

            let font = UIFont.systemFont(ofSize: 11, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let textSize = ("R" as NSString).size(withAttributes: attrs)
            let textRect = CGRect(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            )
            ("R" as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }
}
