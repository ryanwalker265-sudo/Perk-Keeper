import SwiftUI

// Liquid Glass on iOS 26, frosted material on iOS 17–18.

extension View {
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    func glassChip(tint: Color? = nil) -> some View {
        modifier(GlassChip(tint: tint))
    }

    func glassButton(prominent: Bool = false) -> some View {
        modifier(GlassButton(prominent: prominent))
    }

    func minimizingTabBar() -> some View {
        modifier(TabBarMinimize())
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background((tint ?? .clear).opacity(0.12), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g = Glass.regular
        if let tint { g = g.tint(tint.opacity(0.22)) }
        if interactive { g = g.interactive() }
        return g
    }
}

private struct GlassChip: ViewModifier {
    let tint: Color?
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular, in: .capsule)
        } else {
            content
                .background((tint ?? .clear).opacity(0.18), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct GlassButton: ViewModifier {
    let prominent: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}

private struct TabBarMinimize: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

/// Soft backdrop for the glass to refract: deep green and gold, like a well-kept wallet.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        Group {
            if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.55, 0.5], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1],
                    ],
                    colors: dark ? [
                        Color(red: 0.02, green: 0.13, blue: 0.10), Color(red: 0.03, green: 0.09, blue: 0.10), Color(red: 0.10, green: 0.08, blue: 0.03),
                        Color(red: 0.02, green: 0.10, blue: 0.09), Color(red: 0.04, green: 0.07, blue: 0.08), Color(red: 0.12, green: 0.09, blue: 0.03),
                        Color(red: 0.02, green: 0.05, blue: 0.06), Color(red: 0.03, green: 0.06, blue: 0.06), Color(red: 0.05, green: 0.05, blue: 0.05),
                    ] : [
                        Color(red: 0.84, green: 0.95, blue: 0.89), Color(red: 0.92, green: 0.96, blue: 0.95), Color(red: 0.99, green: 0.94, blue: 0.83),
                        Color(red: 0.90, green: 0.97, blue: 0.93), Color(red: 0.98, green: 0.98, blue: 0.97), Color(red: 1.00, green: 0.95, blue: 0.86),
                        Color(red: 0.93, green: 0.97, blue: 0.96), Color(red: 0.96, green: 0.98, blue: 0.96), Color(red: 0.99, green: 0.97, blue: 0.92),
                    ]
                )
            } else {
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.02, green: 0.12, blue: 0.10), Color(red: 0.06, green: 0.06, blue: 0.05)]
                        : [Color(red: 0.86, green: 0.96, blue: 0.91), Color(red: 0.99, green: 0.95, blue: 0.87)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

struct SectionTitle: View {
    let title: String
    var icon: String? = nil
    var color: Color = .secondary
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).foregroundStyle(color) }
            Text(title)
            Spacer()
            if let trailing { Text(trailing).foregroundStyle(.tertiary) }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }
}

enum Haptics {
    static var on: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
    static func tap() { if on { UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
    static func success() { if on { UINotificationFeedbackGenerator().notificationOccurred(.success) } }
    static func warning() { if on { UINotificationFeedbackGenerator().notificationOccurred(.warning) } }
}
