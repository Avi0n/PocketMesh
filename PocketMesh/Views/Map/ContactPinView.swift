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
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        // Size the hosting view
        hosting.view.layoutIfNeeded()
        let size = hosting.view.intrinsicContentSize
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
                let label = UILabel()
                label.font = .preferredFont(forTextStyle: .caption2)
                label.textColor = .label
                label.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
                label.layer.cornerRadius = 4
                label.layer.masksToBounds = true
                label.textAlignment = .center
                label.translatesAutoresizingMaskIntoConstraints = false
                addSubview(label)

                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: centerXAnchor),
                    label.bottomAnchor.constraint(equalTo: topAnchor, constant: -4)
                ])

                nameLabel = label
            }

            if let contactAnnotation = annotation as? ContactAnnotation {
                nameLabel?.text = " \(contactAnnotation.contact.displayName) "
            }
            nameLabel?.isHidden = false
        } else {
            nameLabel?.isHidden = true
        }
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        onDetail = nil
        onMessage = nil
        hostingController = nil
        detailCalloutAccessoryView = nil
        nameLabel?.isHidden = true
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
            contact.isFavorite ? .systemOrange : .systemBlue
        case .repeater:
            .systemGreen
        case .room:
            .systemPurple
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
