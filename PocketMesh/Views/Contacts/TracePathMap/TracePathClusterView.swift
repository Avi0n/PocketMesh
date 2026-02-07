import MapKit
import UIKit

/// Cluster annotation view for grouped repeater pins
final class TracePathClusterView: MKAnnotationView {

    private let countLabel = UILabel()
    private let circleView = UIView()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        let size: CGFloat = 32

        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.backgroundColor = .systemCyan
        circleView.layer.cornerRadius = size / 2
        circleView.layer.borderColor = UIColor.white.cgColor
        circleView.layer.borderWidth = 2
        circleView.layer.shadowColor = UIColor.black.cgColor
        circleView.layer.shadowOpacity = 0.3
        circleView.layer.shadowRadius = 2
        circleView.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(circleView)

        countLabel.translatesAutoresizingMaskIntoConstraints = false
        let baseFont = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .bold
        )
        countLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: baseFont)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        circleView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            circleView.widthAnchor.constraint(equalToConstant: size),
            circleView.heightAnchor.constraint(equalToConstant: size),
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor),

            countLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            countLabel.centerYAnchor.constraint(equalTo: circleView.centerYAnchor)
        ])

        frame = CGRect(x: 0, y: 0, width: size, height: size)
        centerOffset = .zero
        canShowCallout = false

        displayPriority = .defaultHigh
        collisionMode = .circle
    }

    func configure(with clusterAnnotation: MKClusterAnnotation) {
        let count = clusterAnnotation.memberAnnotations.count
        countLabel.text = "\(count)"

        isAccessibilityElement = true
        accessibilityLabel = L10n.Contacts.Contacts.Trace.Map.Cluster.label(count)
        accessibilityHint = L10n.Contacts.Contacts.Trace.Map.Cluster.hint
        accessibilityTraits = .button
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        countLabel.text = nil
        accessibilityLabel = nil
        accessibilityHint = nil
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        if let cluster = annotation as? MKClusterAnnotation {
            configure(with: cluster)
        }
    }
}
