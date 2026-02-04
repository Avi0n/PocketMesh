import SwiftUI

/// A collapsible section that auto-loads data when expanded
/// More iOS-native than explicit "Load" buttons
struct ExpandableSettingsSection<Content: View>: View {
    let title: String
    let icon: String

    @Binding var isExpanded: Bool
    let isLoaded: () -> Bool  // Closure instead of binding (supports computed properties)
    @Binding var isLoading: Bool
    @Binding var error: String?

    let onLoad: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                // Always show content - individual fields handle nil/loading states
                // with "loading..." overlays when their values haven't arrived yet
                content()

                // Show error banner if something failed
                if let error, !isLoaded() {
                    VStack(spacing: 12) {
                        Label(L10n.Localizable.Common.Error.failedToLoad, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L10n.Localizable.Common.tryAgain) {
                            Task { await onLoad() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                }
            } label: {
                HStack {
                    Label(title, systemImage: icon)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing)
                    } else if isLoaded() {
                        Button {
                            Task { await onLoad() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .padding(.trailing)
                    }
                }
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded && !isLoaded() && !isLoading {
                Task { await onLoad() }
            }
        }
        .task {
            // Trigger initial load if section starts expanded
            // (onChange only fires when value changes, not on initial render)
            if isExpanded && !isLoaded() && !isLoading {
                await onLoad()
            }
        }
    }
}

#Preview {
    @Previewable @State var isExpanded = false
    @Previewable @State var isLoading = false
    @Previewable @State var error: String? = nil
    @Previewable @State var data: String? = nil

    Form {
        ExpandableSettingsSection(
            title: "Device Info",
            icon: "info.circle",
            isExpanded: $isExpanded,
            isLoaded: { data != nil },
            isLoading: $isLoading,
            error: $error,
            onLoad: {
                isLoading = true
                try? await Task.sleep(for: .seconds(1))
                data = "Loaded!"
                isLoading = false
            }
        ) {
            Text(data ?? "")
        }
    }
}
