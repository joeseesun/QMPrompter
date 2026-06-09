import SwiftUI

struct GlassActionPanel<Content: View>: View {
    let isPresented: Bool
    let onDismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isPresented {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.045)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                VStack(spacing: 0) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: 430)
                .glassPanelSurface(cornerRadius: 28)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.snappy(duration: 0.24), value: isPresented)
        }
    }
}

struct GlassActionRow: View {
    let systemName: String
    let title: String
    let subtitle: String?
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(.primary)
                    .opacity(isDestructive ? 0.86 : 1)
                    .background(.white.opacity(0.24), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.36), lineWidth: 0.6)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.38), lineWidth: 0.55)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var rowBackground: some ShapeStyle {
        isDestructive ? AnyShapeStyle(.white.opacity(0.24)) : AnyShapeStyle(.white.opacity(0.26))
    }
}

private extension View {
    @ViewBuilder
    func glassPanelSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.05)).interactive(), in: shape)
                .background(.white.opacity(0.18), in: shape)
                .overlay(panelBorder(shape))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(panelBorder(shape))
                .shadow(color: .black.opacity(0.08), radius: 22, y: 11)
        }
    }

    private func panelBorder(_ shape: RoundedRectangle) -> some View {
        shape.stroke(
            LinearGradient(
                colors: [
                    .white.opacity(0.52),
                    .white.opacity(0.18),
                    .black.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.7
        )
    }
}
