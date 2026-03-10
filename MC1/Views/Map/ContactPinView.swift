import MapKit
import SwiftUI
import PocketMeshServices

/// Custom annotation view displaying a colored circle with icon and pointer triangle
final class ContactPinView: MKAnnotationView {
    static let reuseIdentifier = "ContactPinView"

    // MARK: - UI Components

    private let circleView = UIView()
    private let iconImageView = UIImageView()
    private let triangleImageView = UIImageView()
    private var nameLabel: UILabel?
    private var nameLabelContainer: UIView?
    private var nameLabelShadow: UIView?
    private var hostingController: UIHostingController<ContactCalloutContent>?

    // MARK: - Configuration

    var showsNameLabel: Bool = false {
        didSet { updateNameLabel() }
    }

    /// Callbacks for callout actions
    var onDetail: (() -> Void)?
    var onMessage: (() -> Void)?

    // MARK: - Initialization

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupViews()
        canShowCallout = true
        clusteringIdentifier = "contact"
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        // Configure circle
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.layer.shadowColor = UIColor.black.cgColor
        circleView.layer.shadowOpacity = 0.3
        circleView.layer.shadowRadius = 2
        circleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(circleView)

        // Configure icon
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .white
        circleView.addSubview(iconImageView)

        // Configure triangle pointer
        triangleImageView.translatesAutoresizingMaskIntoConstraints = false
        triangleImageView.contentMode = .scaleAspectFit
        triangleImageView.image = UIImage(systemName: "triangle.fill")
        triangleImageView.transform = CGAffineTransform(rotationAngle: .pi)
        addSubview(triangleImageView)

        // Initial layout for unselected state
        updateLayout(selected: false)
    }

    // MARK: - Configuration

    func configure(for contact: ContactDTO) {
        // Set colors based on contact type
        let backgroundColor = pinColor(for: contact)
        circleView.backgroundColor = backgroundColor
        triangleImageView.tintColor = backgroundColor

        // Set icon
        let iconName = iconName(for: contact)
        iconImageView.image = UIImage(systemName: iconName)

        // Set display priority
        displayPriority = contact.isFavorite ? .defaultHigh : .defaultLow

        // Update layout
        updateLayout(selected: isSelected)
    }

    // MARK: - Selection

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
                self.updateLayout(selected: selected)
            }
        } else {
            updateLayout(selected: selected)
        }

        // Update name label visibility since it depends on isSelected state
        updateNameLabel()

        // Configure callout content when selected
        if selected, let contactAnnotation = annotation as? ContactAnnotation {
            configureCalloutContent(for: contactAnnotation.contact)
        }
    }

    private func configureCalloutContent(for contact: ContactDTO) {
        let calloutContent = ContactCalloutContent(
            contact: contact,
            onDetail: { [weak self] in self?.onDetail?() },
            onMessage: { [weak self] in self?.onMessage?() }
        )

        let hosting = UIHostingController(rootView: calloutContent)
        hosting.view.backgroundColor = .clear

        // Size the hosting view - MKMapView uses intrinsic content size for callout layout
        let size = hosting.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        hosting.view.frame = CGRect(origin: .zero, size: size)

        detailCalloutAccessoryView = hosting.view
        hostingController = hosting
    }

    // MARK: - Layout

    private func updateLayout(selected: Bool) {
        let circleSize: CGFloat = selected ? 44 : 36
        let iconSize: CGFloat = selected ? 20 : 16
        let triangleSize: CGFloat = 10

        // Remove existing constraints
        circleView.constraints.forEach { circleView.removeConstraint($0) }
        iconImageView.constraints.forEach { iconImageView.removeConstraint($0) }
        triangleImageView.constraints.forEach { triangleImageView.removeConstraint($0) }

        // Circle constraints
        NSLayoutConstraint.activate([
            circleView.widthConstraint(circleSize),
            circleView.heightConstraint(circleSize),
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.topAnchor.constraint(equalTo: topAnchor)
        ])

        // Icon constraints
        NSLayoutConstraint.activate([
            iconImageView.widthConstraint(iconSize),
            iconImageView.heightConstraint(iconSize),
            iconImageView.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: circleView.centerYAnchor)
        ])

        // Triangle constraints
        NSLayoutConstraint.activate([
            triangleImageView.widthConstraint(triangleSize),
            triangleImageView.heightConstraint(triangleSize),
            triangleImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            triangleImageView.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: -3)
        ])

        // Update circle corner radius
        circleView.layer.cornerRadius = circleSize / 2

        // Update border for selected state
        if selected {
            circleView.layer.borderWidth = 3
            circleView.layer.borderColor = UIColor.white.cgColor
        } else {
            circleView.layer.borderWidth = 0
        }

        // Update frame
        let totalHeight = circleSize + triangleSize - 3
        frame = CGRect(x: 0, y: 0, width: circleSize, height: totalHeight)
        centerOffset = CGPoint(x: 0, y: -totalHeight / 2)
    }

    // MARK: - Name Label

    private func updateNameLabel() {
        if showsNameLabel && !isSelected {
            if nameLabel == nil {
                // Blur background matching app's material style
                let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
                blur.translatesAutoresizingMaskIntoConstraints = false
                blur.layer.cornerRadius = 8
                blur.layer.masksToBounds = true
                addSubview(blur)

                // Shadow container (separate from blur since blur clips)
                let shadow = UIView()
                shadow.translatesAutoresizingMaskIntoConstraints = false
                shadow.backgroundColor = .clear
                shadow.layer.shadowColor = UIColor.black.cgColor
                shadow.layer.shadowOpacity = 0.3
                shadow.layer.shadowRadius = 3
                shadow.layer.shadowOffset = CGSize(width: 0, height: 1.5)
                insertSubview(shadow, belowSubview: blur)
                nameLabelContainer = blur
                nameLabelShadow = shadow

                // Label with Dynamic Type support
                let label = UILabel()
                let baseFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize, weight: .medium)
                label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = .label
                label.textAlignment = .center
                label.translatesAutoresizingMaskIntoConstraints = false
                blur.contentView.addSubview(label)
                nameLabel = label

                NSLayoutConstraint.activate([
                    blur.centerXAnchor.constraint(equalTo: centerXAnchor),
                    blur.bottomAnchor.constraint(equalTo: topAnchor, constant: -4),
                    shadow.topAnchor.constraint(equalTo: blur.topAnchor),
                    shadow.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
                    shadow.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                    shadow.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
                    label.topAnchor.constraint(equalTo: blur.topAnchor, constant: 4),
                    label.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -4),
                    label.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 8),
                    label.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -8)
                ])
            }

            if let contactAnnotation = annotation as? ContactAnnotation {
                nameLabel?.text = contactAnnotation.contact.displayName
            }
            nameLabelContainer?.isHidden = false
            nameLabelShadow?.isHidden = false
        } else {
            nameLabelContainer?.isHidden = true
            nameLabelShadow?.isHidden = true
        }
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        onDetail = nil
        onMessage = nil
        hostingController = nil
        detailCalloutAccessoryView = nil
        nameLabelContainer?.isHidden = true
        nameLabelShadow?.isHidden = true
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()

        if let contactAnnotation = annotation as? ContactAnnotation {
            configure(for: contactAnnotation.contact)
        }
    }

    // MARK: - Helpers

    private func pinColor(for contact: ContactDTO) -> UIColor {
        switch contact.type {
        case .chat:
            UIColor(red: 204.0 / 255.0, green: 122.0 / 255.0, blue: 92.0 / 255.0, alpha: 1) // coral #cc7a5c
        case .repeater:
            UIColor(red: 0, green: 170.0 / 255.0, blue: 1, alpha: 1) // MeshCore cyan #00aaff
        case .room:
            UIColor(red: 1, green: 136.0 / 255.0, blue: 0, alpha: 1) // orange #ff8800 (matches Nodes)
        }
    }

    private func iconName(for contact: ContactDTO) -> String {
        switch contact.type {
        case .chat:
            "person.fill"
        case .repeater:
            "antenna.radiowaves.left.and.right"
        case .room:
            "person.3.fill"
        }
    }
}

// MARK: - Constraint Helpers

private extension UIView {
    func widthConstraint(_ constant: CGFloat) -> NSLayoutConstraint {
        widthAnchor.constraint(equalToConstant: constant)
    }

    func heightConstraint(_ constant: CGFloat) -> NSLayoutConstraint {
        heightAnchor.constraint(equalToConstant: constant)
    }
}
