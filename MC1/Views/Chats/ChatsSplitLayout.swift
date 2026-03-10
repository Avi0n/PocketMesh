import SwiftUI

struct ChatsSplitLayout<Sidebar: View, Detail: View>: View {
    let detailID: UUID?
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        NavigationSplitView {
            NavigationStack {
                sidebar()
            }
        } detail: {
            NavigationStack {
                detail()
            }
            .id(detailID)
        }
    }
}
