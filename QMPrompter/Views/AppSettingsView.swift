import SwiftUI
import UIKit

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var apiKeyStore: APIKeyStore
    @State private var providerDraft: AIProvider
    @State private var apiKeyDraft: String
    @State private var baseURLDraft: String
    @State private var modelDraft: String
    @State private var showAdvancedConnection = false
    @FocusState private var focusedField: SettingsField?

    init(apiKeyStore: APIKeyStore) {
        self.apiKeyStore = apiKeyStore
        _providerDraft = State(initialValue: apiKeyStore.provider)
        _apiKeyDraft = State(initialValue: apiKeyStore.apiKey)
        _baseURLDraft = State(initialValue: apiKeyStore.baseURL)
        _modelDraft = State(initialValue: apiKeyStore.model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    providerCard
                    apiKeyCard
                    connectionCard
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
                        saveSettingsAndDismiss()
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("完成") {
                        focusedField = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label("AI 服务", systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    ForEach(AIProvider.allCases) { provider in
                        Button {
                            changeProvider(to: provider)
                        } label: {
                            Label(provider.title, systemImage: provider == providerDraft ? "checkmark" : "circle")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(providerDraft.title)
                            .font(.system(size: 15, weight: .semibold))

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.white.opacity(0.34), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.42), lineWidth: 0.6)
                    )
                }
                .buttonStyle(.plain)
            }

            Text(providerDraft.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .settingsGlassSurface(cornerRadius: 22)
    }

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("API Key", systemImage: "key.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : "已填写")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                SecureField(providerDraft.keyPlaceholder, text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .focused($focusedField, equals: .apiKey)
                    .submitLabel(.done)
                    .onSubmit(saveSettingsAndDismiss)

                if !apiKeyDraft.isEmpty {
                    Button {
                        apiKeyDraft = ""
                        focusedField = .apiKey
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
                    .stroke(.white.opacity(focusedField == .apiKey ? 0.66 : 0.32), lineWidth: focusedField == .apiKey ? 1 : 0.7)
            )
        }
        .padding(16)
        .settingsGlassSurface(cornerRadius: 22)
    }

    @ViewBuilder
    private var connectionCard: some View {
        if providerDraft == .deepSeek {
            DisclosureGroup(isExpanded: $showAdvancedConnection) {
                connectionFields
                    .padding(.top, 12)
            } label: {
                connectionHeader(title: "连接参数", subtitle: modelSummary)
            }
            .padding(16)
            .settingsGlassSurface(cornerRadius: 22)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                connectionHeader(title: "连接参数", subtitle: modelSummary)
                connectionFields
            }
            .padding(16)
            .settingsGlassSurface(cornerRadius: 22)
        }
    }

    private func connectionHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(subtitle)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var connectionFields: some View {
        VStack(spacing: 10) {
            settingsTextField(
                title: "Base URL",
                placeholder: providerDraft.defaultBaseURL,
                text: $baseURLDraft,
                field: .baseURL,
                keyboardType: .URL
            )

            settingsTextField(
                title: "模型",
                placeholder: providerDraft.defaultModel,
                text: $modelDraft,
                field: .model
            )
        }
    }

    private func settingsTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: SettingsField,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .font(.system(size: 15, weight: .regular, design: field == .model ? .monospaced : .default))
                .focused($focusedField, equals: field)
                .submitLabel(.done)
                .onSubmit(saveSettingsAndDismiss)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.white.opacity(focusedField == field ? 0.66 : 0.30), lineWidth: focusedField == field ? 1 : 0.7)
                )
        }
    }

    private var modelSummary: String {
        let model = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? providerDraft.defaultModel : model
    }

    private func changeProvider(to provider: AIProvider) {
        guard provider != providerDraft else { return }
        let oldProvider = providerDraft
        let currentBaseURL = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentModel = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        providerDraft = provider

        if currentBaseURL.isEmpty || currentBaseURL == oldProvider.defaultBaseURL {
            baseURLDraft = provider.defaultBaseURL
        }

        if currentModel.isEmpty || currentModel == oldProvider.defaultModel {
            modelDraft = provider.defaultModel
        }

        showAdvancedConnection = provider != .deepSeek
    }

    private func saveSettingsAndDismiss() {
        apiKeyStore.provider = providerDraft
        apiKeyStore.apiKey = apiKeyDraft
        apiKeyStore.baseURL = baseURLDraft
        apiKeyStore.model = modelDraft
        apiKeyStore.save()
        dismiss()
    }
}

private enum SettingsField: Hashable {
    case apiKey
    case baseURL
    case model
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
