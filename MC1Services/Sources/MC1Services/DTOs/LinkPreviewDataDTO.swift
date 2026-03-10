import Foundation

/// Data transfer object for link preview data
public struct LinkPreviewDataDTO: Identifiable, Sendable, Hashable {
    /// URL is the ID (unique key)
    public let id: String
    public let url: String
    public let title: String?
    public let imageData: Data?
    public let iconData: Data?
    public let fetchedAt: Date

    public init(
        url: String,
        title: String? = nil,
        imageData: Data? = nil,
        iconData: Data? = nil,
        fetchedAt: Date = Date()
    ) {
        self.id = url
        self.url = url
        self.title = title
        self.imageData = imageData
        self.iconData = iconData
        self.fetchedAt = fetchedAt
    }

    public init(from model: LinkPreviewData) {
        self.id = model.url
        self.url = model.url
        self.title = model.title
        self.imageData = model.imageData
        self.iconData = model.iconData
        self.fetchedAt = model.fetchedAt
    }
}
