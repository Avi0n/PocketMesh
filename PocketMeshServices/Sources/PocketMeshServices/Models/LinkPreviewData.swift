import Foundation
import SwiftData

/// Cached link preview metadata, keyed by URL for cross-message deduplication.
/// Multiple messages with the same URL reference a single LinkPreviewData row.
@Model
public final class LinkPreviewData {
    /// The URL this preview is for (unique key)
    @Attribute(.unique)
    public var url: String

    /// Title from link metadata
    public var title: String?

    /// Preview image data (hero image)
    public var imageData: Data?

    /// Icon/favicon data
    public var iconData: Data?

    /// When this preview was fetched
    public var fetchedAt: Date

    public init(
        url: String,
        title: String? = nil,
        imageData: Data? = nil,
        iconData: Data? = nil,
        fetchedAt: Date = Date()
    ) {
        self.url = url
        self.title = title
        self.imageData = imageData
        self.iconData = iconData
        self.fetchedAt = fetchedAt
    }
}
