import MapKit
import UIKit

/// Crosshairs pin view for the simulated repeater target on the line of sight map
final class LOSRepeaterTargetPinView: MKAnnotationView {
    static let reuseIdentifier = "LOSRepeaterTargetPinView"

    // MARK: - UI Components

    private let crosshairLayer = CAShapeLayer()
    private var badgeLabel: UILabel?
    private var badgeBackground: UIView?

    // MARK: - Initialization

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        let size: CGFloat = 44
        let gapRadius: CGFloat = 4
        let outerRadius = size / 2

        frame = CGRect(x: 0, y: 0, width: size, height: size + 24)
        centerOffset = CGPoint(x: 0, y: 12)
        canShowCallout = false
        displayPriority = .required

        // Crosshair lines
        let center = CGPoint(x: size / 2, y: size / 2)
        let path = UIBezierPath()

        // Top
        path.move(to: CGPoint(x: center.x, y: center.y - outerRadius))
        path.addLine(to: CGPoint(x: center.x, y: center.y - gapRadius))
        // Bottom
        path.move(to: CGPoint(x: center.x, y: center.y + gapRadius))
        path.addLine(to: CGPoint(x: center.x, y: center.y + outerRadius))
        // Left
        path.move(to: CGPoint(x: center.x - outerRadius, y: center.y))
        path.addLine(to: CGPoint(x: center.x - gapRadius, y: center.y))
        // Right
        path.move(to: CGPoint(x: center.x + gapRadius, y: center.y))
        path.addLine(to: CGPoint(x: center.x + outerRadius, y: center.y))

        crosshairLayer.path = path.cgPath
        crosshairLayer.strokeColor = UIColor.systemPurple.cgColor
        crosshairLayer.lineWidth = 2
        crosshairLayer.fillColor = nil
        crosshairLayer.shadowColor = UIColor.black.cgColor
        crosshairLayer.shadowOpacity = 0.3
        crosshairLayer.shadowRadius = 2
        crosshairLayer.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(crosshairLayer)

        // "R" badge below
        let bg = UIView()
        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.backgroundColor = .systemPurple
        bg.layer.cornerRadius = 9
        addSubview(bg)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        let baseFont = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
            weight: .bold
        )
        label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.text = "R"
        bg.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bg.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -6),

            bg.centerXAnchor.constraint(equalTo: centerXAnchor),
            bg.topAnchor.constraint(equalTo: topAnchor, constant: size + 2)
        ])

        badgeLabel = label
        badgeBackground = bg

        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = L10n.Tools.Tools.LineOfSight.repeater
        accessibilityHint = L10n.Tools.Tools.LineOfSight.RepeaterTarget.accessibilityHint
    }

    // MARK: - Configuration

    func configure(opacity: CGFloat) {
        alpha = opacity
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        alpha = 1.0
    }
}
