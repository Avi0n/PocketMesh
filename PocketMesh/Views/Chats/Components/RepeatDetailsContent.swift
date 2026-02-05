// PocketMesh/Views/Chats/Components/RepeatDetailsContent.swift
import CoreLocation
import PocketMeshServices
import SwiftUI

/// Inline content for repeat details, extracted from RepeatDetailsSheet.
/// Shows repeat rows, a loading spinner, or an empty state.
struct RepeatDetailsContent: View {
    let repeats: [MessageRepeatDTO]?
    let contacts: [ContactDTO]
    let userLocation: CLLocation?

    private var repeaters: [ContactDTO] {
        contacts.filter { $0.type == .repeater }
    }

    var body: some View {
        if let repeats {
            if repeats.isEmpty {
                ContentUnavailableView(
                    L10n.Chats.Chats.Repeats.EmptyState.title,
                    systemImage: "arrow.triangle.branch",
                    description: Text(L10n.Chats.Chats.Repeats.EmptyState.description)
                )
            } else {
                ForEach(repeats) { repeatEntry in
                    RepeatRowView(
                        repeatEntry: repeatEntry,
                        repeaters: repeaters,
                        userLocation: userLocation
                    )
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }
}
