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
    @AppStorage("pathEditIncludeDiscovered") private var includeDiscovered = false

    private var hashSize: Int { viewModel.hashSize }

    private var filteredNodes: [PickerNode] {
        var nodes: [PickerNode] = viewModel.filteredAvailableRepeaters.map { .contact($0) }
        if includeDiscovered {
            let contactKeys = Set(nodes.compactMap {
                if case .contact(let c) = $0 { c.publicKey } else { nil }
            })
            nodes += viewModel.discoveredRepeaters
                .filter { !contactKeys.contains($0.publicKey) }
                .map { .discovered($0) }
        }
        return nodes
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                currentPathSection
                addRepeaterSection
            }
            .navigationTitle(L10n.Contacts.Contacts.PathEdit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Contacts.Contacts.Common.cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Contacts.Contacts.Common.save) {
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
            Text(L10n.Contacts.Contacts.PathEdit.description(contact.displayName))
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
            Text(L10n.Contacts.Contacts.PathEdit.currentPath)
        } footer: {
            if viewModel.editablePath.isEmpty {
                Text(L10n.Contacts.Contacts.PathEdit.emptyFooter)
            } else {
                Text(L10n.Contacts.Contacts.PathEdit.instructionsFooter)
            }
        }
    }

    private var addRepeaterSection: some View {
        Section {
            Toggle(L10n.Contacts.Contacts.Trace.List.includeDiscovered, isOn: $includeDiscovered)

            if filteredNodes.isEmpty {
                ContentUnavailableView(
                    L10n.Contacts.Contacts.PathEdit.NoRepeaters.title,
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text(L10n.Contacts.Contacts.PathEdit.NoRepeaters.description)
                )
            } else {
                ForEach(filteredNodes) { node in
                    Button {
                        addHapticTrigger += 1
                        viewModel.addNode(node.underlying)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(node.displayName)
                                    if node.isDiscovered {
                                        NodeKindBadge(text: L10n.Contacts.Contacts.NodeKind.discovered, color: .blue)
                                    }
                                }
                                Text(node.publicKeyHex)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.tint)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel(L10n.Contacts.Contacts.PathEdit.addToPath(node.displayName))
                }
            }
        } header: {
            Text(L10n.Contacts.Contacts.PathEdit.addRepeater)
        } footer: {
            if !filteredNodes.isEmpty {
                Text(L10n.Contacts.Contacts.PathEdit.addFooter)
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
                Text(hop.hashHex)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text(hop.hashHex)
                    .font(.body.monospaced())
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if let name = hop.resolvedName {
            return L10n.Contacts.Contacts.PathEdit.hopWithName(index + 1, totalCount, name)
        } else {
            return L10n.Contacts.Contacts.PathEdit.hopWithHex(index + 1, totalCount, hop.hashHex)
        }
    }
}
