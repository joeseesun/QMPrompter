import SwiftUI
import UIKit

private struct ProviderSettingsDraft {
    var apiKey: String
    var baseURL: String
    var model: String
}

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var apiKeyStore: APIKeyStore
    @State private var providerDraft: AIProvider
    @State private var apiKeyDraft: String
    @State private var baseURLDraft: String
    @State private var modelDraft: String
    @State private var providerSettingsDrafts: [AIProvider: ProviderSettingsDraft]
    @State private var showAdvancedConnection = false
    @State private var showCustomModelField: Bool
    @State private var remoteModelOptions: [AIModelOption] = []
    @State private var isFetchingModels = false
    @State private var isTestingConnection = false
    @State private var modelFetchMessage: String?
    @State private var connectionTestMessage: String?
    @State private var showModelPicker = false
    @State private var showProviderPicker = false
    @State private var modelFetchTask: Task<Void, Never>?
    @State private var connectionTestTask: Task<Void, Never>?
    @State private var lastModelFetchSignature: String?
    @FocusState private var focusedField: SettingsField?

    init(apiKeyStore: APIKeyStore) {
        let initialProvider = apiKeyStore.provider
        let initialModel = apiKeyStore.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let drafts = Dictionary(
            uniqueKeysWithValues: AIProvider.allCases.map { provider in
                (
                    provider,
                    ProviderSettingsDraft(
                        apiKey: apiKeyStore.apiKey(for: provider),
                        baseURL: apiKeyStore.baseURL(for: provider),
                        model: apiKeyStore.model(for: provider)
                    )
                )
            }
        )

        self.apiKeyStore = apiKeyStore
        _providerDraft = State(initialValue: initialProvider)
        _apiKeyDraft = State(initialValue: apiKeyStore.apiKey)
        _baseURLDraft = State(initialValue: apiKeyStore.baseURL)
        _modelDraft = State(initialValue: apiKeyStore.model)
        _providerSettingsDrafts = State(initialValue: drafts)
        _showCustomModelField = State(initialValue: AppSettingsView.isCustomModel(initialModel, provider: initialProvider))
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
            .sheet(isPresented: $showModelPicker) {
                ModelPickerSheet(
                    providerTitle: providerDraft.title,
                    options: combinedModelOptions,
                    selectedModel: normalizedModel
                ) { model in
                    selectModel(model)
                    showModelPicker = false
                } onCustomModel: {
                    showCustomModelField = true
                    focusedField = .model
                    showModelPicker = false
                }
            }
            .confirmationDialog("AI 服务", isPresented: $showProviderPicker, titleVisibility: .visible) {
                ForEach(AIProvider.allCases) { provider in
                    Button(provider.title) {
                        changeProvider(to: provider)
                    }
                }

                Button("取消", role: .cancel) {}
            }
            .onDisappear {
                modelFetchTask?.cancel()
                connectionTestTask?.cancel()
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

                Button {
                    focusedField = nil
                    showProviderPicker = true
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
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换 AI 服务")
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

            modelSelectionField
            connectionTestButton
        }
    }

    private var modelSelectionField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("模型")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    openModelPicker()
                } label: {
                    modelSelectionLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("搜索选择模型")

                Button {
                    fetchRemoteModels()
                } label: {
                    ZStack {
                        if isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(width: 52, height: 52)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white.opacity(0.30), lineWidth: 0.7)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isFetchingModels)
                .accessibilityLabel("从服务器刷新模型列表")
            }

            if showCustomModelField {
                TextField(providerDraft.defaultModel, text: $modelDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .focused($focusedField, equals: .model)
                    .submitLabel(.done)
                    .onSubmit(saveSettingsAndDismiss)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.white.opacity(focusedField == .model ? 0.66 : 0.30), lineWidth: focusedField == .model ? 1 : 0.7)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let modelFetchMessage {
                Text(modelFetchMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: showCustomModelField)
        .animation(.snappy(duration: 0.18), value: modelFetchMessage)
    }

    private var connectionTestButton: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                testConnection()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "network")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .frame(width: 24)

                    Text(isTestingConnection ? "正在测试" : "测试连接")
                        .font(.system(size: 15, weight: .semibold))

                    Spacer()

                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.white.opacity(0.30), lineWidth: 0.7)
                )
            }
            .buttonStyle(.plain)
            .disabled(isTestingConnection)
            .accessibilityLabel("测试当前 AI 服务连接")

            if let connectionTestMessage {
                Text(connectionTestMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.18), value: connectionTestMessage)
    }

    private var modelSelectionLabel: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedModelTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(normalizedModel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(.white.opacity(0.30), lineWidth: 0.7)
        )
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
        normalizedModel
    }

    private var normalizedModel: String {
        let model = modelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? providerDraft.defaultModel : model
    }

    private var selectedModelTitle: String {
        if let option = combinedModelOptions.first(where: { $0.id == normalizedModel }) {
            return option.detail.isEmpty ? option.title : "\(option.title) · \(option.detail)"
        }
        return "自定义模型"
    }

    private var combinedModelOptions: [AIModelOption] {
        var seen = Set<String>()
        var result: [AIModelOption] = []

        for option in remoteModelOptions + providerDraft.modelOptions {
            let key = option.id.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(option)
        }

        if !normalizedModel.isEmpty, !seen.contains(normalizedModel.lowercased()) {
            result.insert(AIModelOption(normalizedModel, title: "当前模型", detail: "自定义"), at: 0)
        }

        return result
    }

    private var modelFetchSignature: String {
        let apiKey = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let keySignature = apiKey.isEmpty ? "empty" : String(apiKey.hashValue)
        let normalizedBaseURL = resolvedBaseURLDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        return [
            providerDraft.rawValue,
            normalizedBaseURL,
            keySignature
        ].joined(separator: "|")
    }

    private func selectModel(_ model: String) {
        modelDraft = model
        showCustomModelField = false
        focusedField = nil
    }

    private func openModelPicker() {
        focusedField = nil

        guard !isFetchingModels else { return }
        guard lastModelFetchSignature == modelFetchSignature else {
            fetchRemoteModels()
            return
        }

        showModelPicker = true
    }

    private func changeProvider(to provider: AIProvider) {
        guard provider != providerDraft else { return }
        storeCurrentDraft()

        providerDraft = provider
        applyDraft(for: provider)
        showCustomModelField = Self.isCustomModel(modelDraft, provider: provider)
        showAdvancedConnection = provider != .deepSeek
        remoteModelOptions = []
        lastModelFetchSignature = nil
        modelFetchMessage = nil
        connectionTestMessage = nil
    }

    private func storeCurrentDraft() {
        providerSettingsDrafts[providerDraft] = ProviderSettingsDraft(
            apiKey: apiKeyDraft,
            baseURL: baseURLDraft,
            model: modelDraft
        )
    }

    private func applyDraft(for provider: AIProvider) {
        let draft = providerSettingsDrafts[provider] ?? ProviderSettingsDraft(
            apiKey: apiKeyStore.apiKey(for: provider),
            baseURL: apiKeyStore.baseURL(for: provider),
            model: apiKeyStore.model(for: provider)
        )

        apiKeyDraft = draft.apiKey
        baseURLDraft = draft.baseURL
        modelDraft = draft.model
    }

    private func fetchRemoteModels() {
        modelFetchTask?.cancel()
        focusedField = nil
        modelFetchMessage = nil
        let fetchSignature = modelFetchSignature

        if lastModelFetchSignature != fetchSignature {
            remoteModelOptions = []
        }

        let configuration = AIConnectionConfiguration(
            provider: providerDraft,
            apiKey: apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: resolvedBaseURLDraft,
            model: normalizedModel
        )

        modelFetchTask = Task {
            await MainActor.run {
                isFetchingModels = true
            }

            do {
                let models = try await AIModelFetcher(configuration: configuration).fetchModels()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    remoteModelOptions = models
                    lastModelFetchSignature = fetchSignature
                    modelFetchMessage = "已加载 \(models.count) 个服务器模型"
                    isFetchingModels = false
                    showModelPicker = true
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    lastModelFetchSignature = fetchSignature
                    modelFetchMessage = "\(message) 已保留预设模型。"
                    isFetchingModels = false
                    showModelPicker = true
                }
            }
        }
    }

    private func testConnection() {
        connectionTestTask?.cancel()
        focusedField = nil
        connectionTestMessage = nil
        let fetchSignature = modelFetchSignature

        let configuration = AIConnectionConfiguration(
            provider: providerDraft,
            apiKey: apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: resolvedBaseURLDraft,
            model: normalizedModel
        )

        connectionTestTask = Task {
            await MainActor.run {
                isTestingConnection = true
            }

            do {
                let models = try await AIModelFetcher(configuration: configuration).fetchModels()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    remoteModelOptions = models
                    lastModelFetchSignature = fetchSignature
                    connectionTestMessage = "连接可用，已加载 \(models.count) 个模型"
                    modelFetchMessage = nil
                    isTestingConnection = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    connectionTestMessage = message
                    isTestingConnection = false
                }
            }
        }
    }

    private static func isCustomModel(_ model: String, provider: AIProvider) -> Bool {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return false }
        return !provider.modelOptions.contains { $0.id == trimmedModel }
    }

    private func saveSettingsAndDismiss() {
        var drafts = providerSettingsDrafts
        drafts[providerDraft] = ProviderSettingsDraft(
            apiKey: apiKeyDraft,
            baseURL: baseURLDraft,
            model: modelDraft
        )
        providerSettingsDrafts = drafts

        for provider in AIProvider.allCases {
            guard let draft = drafts[provider] else { continue }
            apiKeyStore.saveSettings(
                for: provider,
                apiKey: draft.apiKey,
                baseURL: draft.baseURL,
                model: draft.model
            )
        }

        apiKeyStore.selectProvider(providerDraft)
        dismiss()
    }

    private var resolvedBaseURLDraft: String {
        let value = baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? providerDraft.defaultBaseURL : value
    }
}

private enum SettingsField: Hashable {
    case apiKey
    case baseURL
    case model
}

private struct ModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let providerTitle: String
    let options: [AIModelOption]
    let selectedModel: String
    let onSelect: (String) -> Void
    let onCustomModel: () -> Void

    @State private var searchText = ""

    private var filteredOptions: [AIModelOption] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }

        return options.filter { option in
            option.id.localizedCaseInsensitiveContains(query) ||
                option.title.localizedCaseInsensitiveContains(query) ||
                option.detail.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredOptions) { option in
                        Button {
                            onSelect(option.id)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    Text(option.id)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    if !option.detail.isEmpty {
                                        Text(option.detail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 8)

                                if option.id == selectedModel {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onCustomModel()
                    } label: {
                        Label("自定义模型", systemImage: "pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索模型")
            .navigationTitle(providerTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
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
