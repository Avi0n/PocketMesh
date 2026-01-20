import SwiftUI

extension View {
    /// Applies liquid glass effect on iOS 26+, falls back to regularMaterial on earlier versions
    @ViewBuilder
    func liquidGlass(in shape: some Shape = .rect(cornerRadius: 12)) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// Applies glass button style on iOS 26+, falls back to borderedProminent on earlier versions
    @ViewBuilder
    func liquidGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Applies prominent glass button style with tint on iOS 26+, falls back to borderedProminent on earlier versions
    @ViewBuilder
    func liquidGlassProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Applies interactive liquid glass effect on iOS 26+, falls back to thinMaterial on earlier versions
    @ViewBuilder
    func liquidGlassInteractive(in shape: some Shape = .circle) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.thinMaterial, in: shape)
        }
    }

    #if os(iOS)
    /// Applies visible toolbar backgrounds for full-screen content views.
    /// On iOS 26+, explicitly sets visibility so system applies liquid glass.
    /// On iOS 18, uses regularMaterial background.
    @ViewBuilder
    func liquidGlassToolbarBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        } else {
            self
                .toolbarBackground(.regularMaterial, for: .navigationBar, .tabBar)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar, .tabBar)
        }
    }
    #endif
}

/// A container that uses GlassEffectContainer on iOS 26+, passes through content on earlier versions
struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
