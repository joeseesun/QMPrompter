import SwiftUI

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var apiKeyStore: APIKeyStore
    @State private var apiKeyDraft: String
    @FocusState private var keyFieldFocused: Bool

    init(apiKeyStore: APIKeyStore) {
        self.apiKeyStore = apiKeyStore
        _apiKeyDraft = State(initialValue: apiKeyStore.deepSeekAPIKey)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    apiKeyCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(SettingsBackground())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveAPIKeyAndDismiss()
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("完成") {
                        keyFieldFocused = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("DeepSeek API Key", systemImage: "key.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : "已填写")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                SecureField("sk-...", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .focused($keyFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(saveAPIKeyAndDismiss)

                if !apiKeyDraft.isEmpty {
                    Button {
                        apiKeyDraft = ""
                        keyFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.72))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空 API Key")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(keyFieldFocused ? 0.66 : 0.32), lineWidth: keyFieldFocused ? 1 : 0.7)
            )
        }
        .padding(16)
        .settingsGlassSurface(cornerRadius: 22)
    }

    private func saveAPIKeyAndDismiss() {
        apiKeyStore.deepSeekAPIKey = apiKeyDraft
        apiKeyStore.saveDeepSeekAPIKey()
        dismiss()
    }
}

private struct SettingsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground).opacity(0.36),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private extension View {
    @ViewBuilder
    func settingsGlassSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.04)).interactive(), in: shape)
                .background(.white.opacity(0.26), in: shape)
                .overlay(settingsGlassBorder(shape))
                .shadow(color: .black.opacity(0.065), radius: 18, y: 9)
        } else {
            background(.ultraThinMaterial, in: shape)
                .background(.white.opacity(0.24), in: shape)
                .overlay(settingsGlassBorder(shape))
                .shadow(color: .black.opacity(0.055), radius: 16, y: 8)
        }
    }

    private func settingsGlassBorder(_ shape: RoundedRectangle) -> some View {
        shape.stroke(
            LinearGradient(
                colors: [
                    .white.opacity(0.62),
                    .white.opacity(0.20),
                    .black.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.7
        )
    }
}
