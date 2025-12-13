import PocketMeshKit
import SwiftUI

/// Sheet for editing a contact's routing path
struct PathEditingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: PathManagementViewModel
    let contact: ContactDTO

    // Haptic feedback triggers (SwiftUI native approach)
    @State private var dragHapticTrigger = 0
    @State private var addHapticTrigger = 0
    @State private var editMode: EditMode = .inactive

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
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .onChange(of: editMode) { oldValue, newValue in
                // Auto-save when exiting edit mode
                if oldValue == .active, newValue == .inactive {
                    Task {
                        await viewModel.saveEditedPath(for: contact)
                    }
                }
            }
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
            if viewModel.editablePath.isEmpty {
                Text("No path set (direct or flood routing)")
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44) // Minimum touch target
            } else {
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
                    for index in indexSet.sorted().reversed() {
                        viewModel.removeRepeater(at: index)
                    }
                }
                .animation(.default, value: viewModel.editablePath.map(\.id))
            }
        } header: {
            Text("Current Path")
        } footer: {
            if !viewModel.editablePath.isEmpty {
                if editMode == .active {
                    Text("Drag to reorder. Tap delete to remove.")
                } else {
                    Text("Tap Edit to reorder or remove hops.")
                }
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
