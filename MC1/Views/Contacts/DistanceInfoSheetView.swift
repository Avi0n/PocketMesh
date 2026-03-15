import SwiftUI
import MC1Services

/// Sheet explaining distance calculation details and limitations
struct DistanceInfoSheetView: View {
    let result: TraceResult
    @Bindable var viewModel: TracePathViewModel
    @Binding var showingDistanceInfo: Bool

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isDistanceUsingFallback {
                    Section {
                        Text(L10n.Contacts.Contacts.Results.partialDistanceExplanation)
                    } header: {
                        Label(L10n.Contacts.Contacts.Results.partialDistanceHeader, systemImage: "location.slash")
                    }
                    Section {
                        Text(L10n.Contacts.Contacts.Results.fullPathTip)
                    } header: {
                        Label(L10n.Contacts.Contacts.Results.fullPathHeader, systemImage: "lightbulb")
                    }
                } else if result.hops.filter({ !$0.isStartNode && !$0.isEndNode }).count < 2 {
                    Section {
                        Text(L10n.Contacts.Contacts.Results.needsRepeaters)
                    }
                } else if viewModel.repeatersWithoutLocation.isEmpty {
                    Section {
                        Text(L10n.Contacts.Contacts.Results.distanceError)
                    }
                } else {
                    Section {
                        Text(L10n.Contacts.Contacts.Results.missingLocations)
                    }
                    Section(L10n.Contacts.Contacts.Results.repeatersWithoutLocations) {
                        ForEach(viewModel.repeatersWithoutLocation, id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isDistanceUsingFallback ? L10n.Contacts.Contacts.Results.distanceInfoTitlePartial : L10n.Contacts.Contacts.Results.distanceInfoTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Contacts.Contacts.Common.done) {
                        showingDistanceInfo = false
                    }
                }
            }
        }
    }
}
