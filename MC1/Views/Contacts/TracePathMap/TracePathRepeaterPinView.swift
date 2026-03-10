import MapKit
import UIKit
import PocketMeshServices

/// Custom pin view for repeaters in trace path map with selection state
final class TracePathRepeaterPinView: MKAnnotationView {
    static let reuseIdentifier = "TracePathRepeaterPinView"
    static let clusteringID = "repeater"

    // MARK: - Tap Handling

    var onTap: (() -> Void)?

    // MARK: - UI Components

    private let circleView = UIView()
    private let iconImageView = UIImageView()
    private let triangleImageView = UIImageView()
    private let selectionRing = UIView()
    private var numberBadge: UILabel?
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
        selectionRing.layer.borderColor = UIColor.white.cgColor
        selectionRing.layer.borderWidth = 2
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

        // All constraints use constant values — activate once
        NSLayoutConstraint.activate([
            // Selection ring
            selectionRing.widthAnchor.constraint(equalToConstant: ringSize),
            selectionRing.heightAnchor.constraint(equalToConstant: ringSize),
            selectionRing.centerXAnchor.constraint(equalTo: centerXAnchor),
            selectionRing.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),

            // Circle
            circleView.widthAnchor.constraint(equalToConstant: circleSize),
            circleView.heightAnchor.constraint(equalToConstant: circleSize),
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            // Icon
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),
            iconImageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),

            // Triangle
            triangleImageView.widthAnchor.constraint(equalToConstant: triangleSize),
            triangleImageView.heightAnchor.constraint(equalToConstant: triangleSize),
            triangleImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            triangleImageView.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: -3)
        ])

        let totalHeight = circleSize + triangleSize + 4
        frame = CGRect(x: 0, y: 0, width: ringSize, height: totalHeight)
        centerOffset = CGPoint(x: 0, y: -totalHeight / 2)

        canShowCallout = false

        // Tap gesture fires immediately, bypassing MapKit's ~300ms selection delay
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
    }

    @objc private func handleTap() {
        onTap?()
    }

    // MARK: - Configuration

    func configure(
        for repeater: ContactDTO,
        inPath: Bool,
        hopIndex: Int?,
        isLastHop: Bool,
        showLabel: Bool
    ) {
        // Clustering: in-path pins are always visible, others cluster
        if inPath {
            clusteringIdentifier = nil
            displayPriority = .required
        } else {
            clusteringIdentifier = Self.clusteringID
            displayPriority = .defaultLow
        }

        // Update selection ring
        selectionRing.isHidden = !inPath

        // Update number badge
        if let index = hopIndex {
            showNumberBadge(index)
        } else {
            hideNumberBadge()
        }

        // Update name label
        if showLabel {
            showNameLabel(repeater.displayName)
        } else {
            hideNameLabel()
        }

        // Accessibility
        isAccessibilityElement = true
        if inPath {
            if isLastHop {
                accessibilityLabel = L10n.Contacts.Contacts.Trace.Map.Pin.inPathLabel(repeater.displayName, hopIndex ?? 0)
                accessibilityHint = L10n.Contacts.Contacts.Trace.Map.Pin.removableHint
                accessibilityTraits = [.button, .selected]
            } else {
                accessibilityLabel = L10n.Contacts.Contacts.Trace.Map.Pin.inPathLabel(repeater.displayName, hopIndex ?? 0)
                accessibilityHint = L10n.Contacts.Contacts.Trace.Map.Pin.notRemovableHint
                accessibilityTraits = [.button, .selected, .notEnabled]
            }
        } else {
            accessibilityLabel = L10n.Contacts.Contacts.Trace.Map.Pin.availableLabel(repeater.displayName)
            accessibilityHint = L10n.Contacts.Contacts.Trace.Map.Pin.addHint
            accessibilityTraits = .button
        }
    }

    // MARK: - Number Badge

    private func showNumberBadge(_ number: Int) {
        if numberBadge == nil {
            let badge = UILabel()
            badge.translatesAutoresizingMaskIntoConstraints = false
            // Dynamic Type with caption2 style
            let baseFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .bold)
            badge.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont)
            badge.adjustsFontForContentSizeCategory = true
            badge.textColor = .black
            badge.textAlignment = .center
            badge.backgroundColor = .white
            badge.layer.cornerRadius = 9
            badge.layer.masksToBounds = true
            addSubview(badge)

            NSLayoutConstraint.activate([
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
                badge.heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
                badge.trailingAnchor.constraint(equalTo: circleView.trailingAnchor, constant: 4),
                badge.topAnchor.constraint(equalTo: circleView.topAnchor, constant: -4)
            ])

            numberBadge = badge
        }

        numberBadge?.text = "\(number)"
        numberBadge?.isHidden = false
    }

    private func hideNumberBadge() {
        numberBadge?.isHidden = true
    }

    // MARK: - Name Label

    private func showNameLabel(_ name: String) {
        if nameLabelContainer == nil {
            let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            blur.translatesAutoresizingMaskIntoConstraints = false
            blur.layer.cornerRadius = 8
            blur.layer.masksToBounds = true
            addSubview(blur)

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            // Dynamic Type with caption2 style
            let baseFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .medium)
            label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .label
            label.textAlignment = .center
            blur.contentView.addSubview(label)

            // Internal + position constraints (all set once at creation time)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: blur.topAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -4),
                label.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -8),
                blur.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
                blur.bottomAnchor.constraint(equalTo: circleView.topAnchor, constant: -4)
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
        hideNumberBadge()
        hideNameLabel()
        accessibilityLabel = nil
        accessibilityHint = nil
        clusteringIdentifier = Self.clusteringID
        displayPriority = .defaultLow
    }
}
