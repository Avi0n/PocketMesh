import MapKit
import UIKit

/// Annotation view displaying stats badge with liquid glass styling
final class StatsBadgeView: MKAnnotationView {
    static let reuseIdentifier = "StatsBadgeView"

    private let containerView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let label = UILabel()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        // Container with blur
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 12
        containerView.layer.masksToBounds = true
        addSubview(containerView)

        // Shadow
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)

        // Label with Dynamic Type
        label.translatesAutoresizingMaskIntoConstraints = false
        let baseFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize, weight: .medium)
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: baseFont)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        containerView.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            label.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10)
        ])

        canShowCallout = false
        isEnabled = false
    }

    func configure(with annotation: StatsBadgeAnnotation) {
        label.text = annotation.displayString

        // Size to fit content
        label.sizeToFit()
        let size = CGSize(
            width: label.frame.width + 20,
            height: label.frame.height + 12
        )
        frame = CGRect(origin: .zero, size: size)
        centerOffset = CGPoint(x: 0, y: 0)

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = "Distance: \(annotation.distanceString), Signal: \(Int(annotation.snrDB)) decibels"
        accessibilityTraits = .staticText
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.text = nil
        accessibilityLabel = nil
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        if let statsAnnotation = annotation as? StatsBadgeAnnotation {
            configure(with: statsAnnotation)
        }
    }
}
