import MapKit
import UIKit
import PocketMeshServices

/// Custom pin view for repeaters in line of sight map with selection state and clustering
final class LOSRepeaterPinView: MKAnnotationView {
    static let reuseIdentifier = "LOSRepeaterPinView"
    static let clusteringID = "losRepeater"

    // MARK: - Tap Handling

    var onTap: (() -> Void)?

    // MARK: - UI Components

    private let circleView = UIView()
    private let iconImageView = UIImageView()
    private let triangleImageView = UIImageView()
    private let selectionRing = UIView()
    private var pointBadge: UILabel?
    private var nameLabel: UILabel?
    private var nameLabelContainer: UIView?

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
        let circleSize: CGFloat = 36
        let iconSize: CGFloat = 16
        let triangleSize: CGFloat = 10
        let ringSize: CGFloat = 44

        // Selection ring (behind circle)
        selectionRing.translatesAutoresizingMaskIntoConstraints = false
        selectionRing.backgroundColor = .clear
        selectionRing.layer.borderWidth = 3
        selectionRing.layer.cornerRadius = ringSize / 2
        selectionRing.isHidden = true
        addSubview(selectionRing)

        // Circle
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = .systemCyan
        circleView.layer.cornerRadius = circleSize / 2
        circleView.layer.shadowColor = UIColor.black.cgColor
        circleView.layer.shadowOpacity = 0.3
        circleView.layer.shadowRadius = 2
        circleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(circleView)

        // Icon
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .white
        iconImageView.image = UIImage(systemName: "antenna.radiowaves.left.and.right")
        circleView.addSubview(iconImageView)

        // Triangle
        triangleImageView.translatesAutoresizingMaskIntoConstraints = false
        triangleImageView.contentMode = .scaleAspectFit
        triangleImageView.image = UIImage(systemName: "triangle.fill")
        triangleImageView.transform = CGAffineTransform(rotationAngle: .pi)
        triangleImageView.tintColor = .systemCyan
        addSubview(triangleImageView)

        NSLayoutConstraint.activate([
            selectionRing.widthAnchor.constraint(equalToConstant: ringSize),
            selectionRing.heightAnchor.constraint(equalToConstant: ringSize),
            selectionRing.centerXAnchor.constraint(equalTo: centerXAnchor),
            selectionRing.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),

            circleView.widthAnchor.constraint(equalToConstant: circleSize),
            circleView.heightAnchor.constraint(equalToConstant: circleSize),
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),
            iconImageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),

            triangleImageView.widthAnchor.constraint(equalToConstant: triangleSize),
            triangleImageView.heightAnchor.constraint(equalToConstant: triangleSize),
            triangleImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            triangleImageView.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: -3)
        ])

        let totalHeight = circleSize + triangleSize + 4
        frame = CGRect(x: 0, y: 0, width: ringSize, height: totalHeight)
        centerOffset = CGPoint(x: 0, y: -totalHeight / 2)

        canShowCallout = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap() {
        onTap?()
    }

    // MARK: - Configuration

    func configure(selectedAs: PointID?, opacity: CGFloat, showLabel: Bool = false) {
        let isSelected = selectedAs != nil

        // Clustering: selected pins always visible, others cluster
        if isSelected {
            clusteringIdentifier = nil
            displayPriority = .required
        } else {
            clusteringIdentifier = Self.clusteringID
            displayPriority = .defaultLow
        }

        // Selection ring color: blue for A, green for B
        if let selectedAs {
            selectionRing.isHidden = false
            selectionRing.layer.borderColor = (selectedAs == .pointA ? UIColor.systemBlue : UIColor.systemGreen).cgColor
            showPointBadge(selectedAs == .pointA ? "A" : "B", color: selectedAs == .pointA ? .systemBlue : .systemGreen)
        } else {
            selectionRing.isHidden = true
            hidePointBadge()
        }

        alpha = opacity

        // Name label
        if showLabel, let repeaterAnnotation = annotation as? LOSRepeaterAnnotation {
            showNameLabel(repeaterAnnotation.repeater.displayName)
        } else {
            hideNameLabel()
        }

        // Accessibility
        isAccessibilityElement = true
        if let repeaterAnnotation = annotation as? LOSRepeaterAnnotation {
            if isSelected {
                accessibilityLabel = repeaterAnnotation.repeater.displayName
                accessibilityTraits = [.button, .selected]
            } else {
                accessibilityLabel = repeaterAnnotation.repeater.displayName
                accessibilityTraits = .button
            }
            accessibilityHint = L10n.Tools.Tools.LineOfSight.RepeaterPin.accessibilityHint
        }
    }

    // MARK: - Point Badge

    private func showPointBadge(_ text: String, color: UIColor) {
        if pointBadge == nil {
            let badge = UILabel()
            badge.translatesAutoresizingMaskIntoConstraints = false
            let baseFont = UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                weight: .bold
            )
            badge.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont)
            badge.adjustsFontForContentSizeCategory = true
            badge.textColor = .white
            badge.textAlignment = .center
            badge.layer.cornerRadius = 9
            badge.layer.masksToBounds = true
            addSubview(badge)

            NSLayoutConstraint.activate([
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
                badge.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
                badge.centerXAnchor.constraint(equalTo: centerXAnchor),
                badge.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 8)
            ])

            pointBadge = badge
        }

        pointBadge?.text = text
        pointBadge?.backgroundColor = color
        pointBadge?.isHidden = false
    }

    private func hidePointBadge() {
        pointBadge?.isHidden = true
    }

    // MARK: - Name Label

    private func showNameLabel(_ name: String) {
        if nameLabelContainer == nil {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            blur.translatesAutoresizingMaskIntoConstraints = false
            blur.layer.cornerRadius = 8
            blur.clipsToBounds = true

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            let baseFont = UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                weight: .medium
            )
            label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .label
            label.textAlignment = .center
            blur.contentView.addSubview(label)

            addSubview(blur)

            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -4),
                label.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -8),

                blur.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
                blur.bottomAnchor.constraint(equalTo: circleView.topAnchor, constant: -4),
            ])

            nameLabelContainer = blur
            nameLabel = label
        }

        nameLabel?.text = name
        nameLabelContainer?.isHidden = false
    }

    private func hideNameLabel() {
        nameLabelContainer?.isHidden = true
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        onTap = nil
        selectionRing.isHidden = true
        hidePointBadge()
        hideNameLabel()
        alpha = 1.0
        accessibilityLabel = nil
        clusteringIdentifier = Self.clusteringID
        displayPriority = .defaultLow
    }
}
