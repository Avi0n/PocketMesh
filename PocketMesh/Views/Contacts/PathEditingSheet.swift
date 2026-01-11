import PocketMeshServices
import SwiftUI

/// Sheet for editing a contact's routing path
struct PathEditingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PathManagementViewModel
    let contact: ContactDTO

    // Haptic feedback triggers (SwiftUI native approach)
    @State private var dragHapticTrigger = 0
    @State private var addHapticTrigger = 0

    var body: some View {
        NavigationStack {
            List {
                headerSection
                currentPathSection
                addRepeaterSection
            }
            .navigationTitle("Edit Path")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.saveEditedPath(for: contact)
                            dismiss()
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .sensoryFeedback(.impact(weight: .light), trigger: dragHapticTrigger)
            .sensoryFeedback(.impact(weight: .light), trigger: addHapticTrigger)
        }
        .presentationDragIndicator(.visible)
        .presentationSizing(.page)
    }

    private var headerSection: some View {
        Section {
            Text("Customize the route messages take to reach \(contact.displayName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var currentPathSection: some View {
        Section {
            // ForEach always present (renders nothing when empty, preserving view identity)
            ForEach(viewModel.editablePath) { hop in
                let index = viewModel.editablePath.firstIndex { $0.id == hop.id } ?? 0
                PathHopRow(
                    hop: hop,
                    index: index,
                    totalCount: viewModel.editablePath.count
                )
            }
            .onMove { source, destination in
                dragHapticTrigger += 1
                viewModel.moveRepeater(from: source, to: destination)
            }
            .onDelete { indexSet in
                withAnimation {
                    for index in indexSet.sorted().reversed() {
                        viewModel.removeRepeater(at: index)
                    }
                }
            }
        } header: {
            Text("Current Path")
        } footer: {
            if viewModel.editablePath.isEmpty {
                Text("No path set (direct or flood routing)")
            } else {
                Text("Drag to reorder. Tap to remove.")
            }
        }
    }

    private var addRepeaterSection: some View {
        Section {
            if viewModel.filteredAvailableRepeaters.isEmpty {
                ContentUnavailableView(
                    "No Repeaters Available",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Repeaters appear here once they're discovered in your mesh network.")
                )
            } else {
                ForEach(viewModel.filteredAvailableRepeaters) { repeater in
                    Button {
                        addHapticTrigger += 1
                        viewModel.addRepeater(repeater)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(repeater.displayName)
                                Text(String(format: "%02X", repeater.publicKey[0]))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.tint)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Add \(repeater.displayName) to path")
                }
            }
        } header: {
            Text("Add Repeater")
        } footer: {
            if !viewModel.filteredAvailableRepeaters.isEmpty {
                Text("Tap a repeater to add it to the path.")
            }
        }
    }
}

/// Row displaying a single hop in the path
private struct PathHopRow: View {
    let hop: PathHop
    let index: Int
    let totalCount: Int

    var body: some View {
        VStack(alignment: .leading) {
            if let name = hop.resolvedName {
                Text(name)
                Text(String(format: "%02X", hop.hashByte))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: "%02X", hop.hashByte))
                    .font(.body.monospaced())
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if let name = hop.resolvedName {
            return "Hop \(index + 1) of \(totalCount): \(name)"
        } else {
            return "Hop \(index + 1) of \(totalCount): repeater \(String(format: "%02X", hop.hashByte))"
        }
    }
}
