import SwiftUI

struct AIGenerationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var apiKeyStore: APIKeyStore
    let onGenerated: (Script) -> Void

    @StateObject private var dictation = PromptDictation()
    @State private var prompt = ""
    @State private var promptBeforeDictation = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var generationTask: Task<Void, Never>?
    @FocusState private var promptFocused: Bool

    private var canGenerate: Bool {
        apiKeyStore.hasDeepSeekAPIKey &&
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isGenerating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    promptInputCard

                    if !apiKeyStore.hasDeepSeekAPIKey {
                        apiKeySetupCard
                    }

                    if isGenerating {
                        generationStatusCard
                    }

                    if let message = errorMessage {
                        generationErrorCard(message)
                    } else if let message = dictation.errorMessage {
                        noticeCard(message, systemName: "exclamationmark.triangle")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 118)
            }
            .scrollIndicators(.hidden)
            .background(AIGenerationBackground())
            .navigationTitle("AI 生成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        cancelGeneration()
                        close()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        startGeneration()
                    } label: {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Text("生成")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canGenerate)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button("完成") {
                        promptFocused = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ZStack {
                    AIVoiceDockBackground()

                    VoiceInputButton(
                        isRecording: dictation.isRecording,
                        isDisabled: isGenerating
                    ) {
                        Haptics.lightImpact()
                        toggleDictation()
                    }
                }
                .frame(height: 116)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: dictation.transcript) { _, transcript in
                guard !transcript.isEmpty else { return }
                prompt = mergedDictationPrompt(with: transcript)
            }
            .onChange(of: prompt) { _, _ in
                clearTransientErrors()
            }
            .onChange(of: apiKeyStore.deepSeekAPIKey) { _, _ in
                clearTransientErrors()
            }
            .onDisappear {
                cancelGeneration()
                dictation.stop()
            }
            .sheet(isPresented: $showSettings) {
                AppSettingsView(apiKeyStore: apiKeyStore)
            }
        }
    }

    private var promptInputCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt)
                    .frame(minHeight: 260)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 17))
                    .lineSpacing(4)
                    .disabled(isGenerating)
                    .focused($promptFocused)

                if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("想生成什么？")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.78))
                        .padding(.top, 7)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
        .aiGenerationGlassSurface(cornerRadius: 24)
    }

    private var apiKeySetupCard: some View {
        Button {
            Haptics.selection()
            showSettings = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.36), in: Circle())

                Text("填写 DeepSeek API Key")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .aiGenerationGlassSurface(cornerRadius: 18)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("填写 DeepSeek API Key")
    }

    private var generationStatusCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            VStack(alignment: .leading, spacing: 3) {
                Text("正在生成文稿")
                    .font(.system(size: 15, weight: .semibold))

                Text("完成后会自动进入编辑页")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                Haptics.selection()
                cancelGeneration()
            } label: {
                Text("取消")
                    .font(.system(size: 13, weight: .semibold))
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
            .accessibilityLabel("取消生成")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .aiGenerationGlassSurface(cornerRadius: 18)
    }

    private func noticeCard(_ text: String, systemName: String) -> some View {
        Label(text, systemImage: systemName)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .aiGenerationGlassSurface(cornerRadius: 18)
    }

    private func generationErrorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.34), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("生成失败")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                Haptics.selection()
                startGeneration()
            } label: {
                Text("重试")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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
            .disabled(!canGenerate)
            .opacity(canGenerate ? 1 : 0.46)
            .accessibilityLabel("重试生成")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .aiGenerationGlassSurface(cornerRadius: 18)
    }

    private func startGeneration() {
        guard canGenerate else { return }
        Haptics.mediumImpact()
        promptFocused = false
        generationTask?.cancel()
        generationTask = Task {
            await generate()
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func close() {
        dictation.stop()
        dismiss()
    }

    private func toggleDictation() {
        if dictation.isRecording {
            dictation.stop()
            return
        }

        clearTransientErrors()
        promptBeforeDictation = prompt
        promptFocused = false
        dictation.start()
    }

    private func clearTransientErrors() {
        errorMessage = nil
        dictation.clearError()
    }

    private func mergedDictationPrompt(with transcript: String) -> String {
        let base = promptBeforeDictation.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !base.isEmpty else { return spoken }
        guard !spoken.isEmpty else { return base }
        return base + "\n" + spoken
    }

    private func generate() async {
        let cleanedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiKeyStore.hasDeepSeekAPIKey, !cleanedPrompt.isEmpty, !isGenerating else { return }

        dictation.stop()
        errorMessage = nil
        isGenerating = true
        defer {
            isGenerating = false
            generationTask = nil
        }

        do {
            let generator = DeepSeekScriptGenerator(apiKey: apiKeyStore.deepSeekAPIKey)
            let content = try await generator.generateScript(for: cleanedPrompt)
            guard !Task.isCancelled else { return }
            createScript(from: content, prompt: cleanedPrompt)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func createScript(from generatedContent: String, prompt: String) {
        let content = generatedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        let script = Script(title: scriptTitle(from: prompt), content: content)
        Haptics.success()
        onGenerated(script)
        dismiss()
    }

    private func scriptTitle(from prompt: String) -> String {
        let cleaned = prompt
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "AI 生成文稿" }
        let prefix = String(cleaned.prefix(16))
        return prefix.count < cleaned.count ? "\(prefix)..." : prefix
    }
}

private struct VoiceInputButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(isRecording ? 0.34 : 0), lineWidth: 1.2)
                    .frame(width: 104, height: 104)
                    .scaleEffect(isRecording ? 1.10 : 0.94)
                    .opacity(isRecording ? 1 : 0)

                Circle()
                    .stroke(.white.opacity(isRecording ? 0.22 : 0), lineWidth: 1)
                    .frame(width: 118, height: 118)
                    .scaleEffect(isRecording ? 1.14 : 0.90)
                    .opacity(isRecording ? 1 : 0)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 88, height: 88)
                    .voiceButtonSurface(isRecording: isRecording)
            }
            .frame(width: 124, height: 108)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.62 : 1)
        .scaleEffect(isRecording ? 1.03 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isRecording)
        .accessibilityLabel(isRecording ? "停止语音输入" : "开始语音输入")
    }
}

private struct AIVoiceDockBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground).opacity(0),
                Color(.systemBackground).opacity(0.78),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct AIGenerationBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground).opacity(0.34),
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
    func aiGenerationGlassSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.05)).interactive(), in: shape)
                .background(.white.opacity(0.28), in: shape)
                .overlay(aiGenerationBorder(shape))
                .shadow(color: .black.opacity(0.07), radius: 18, y: 9)
        } else {
            background(.ultraThinMaterial, in: shape)
                .background(.white.opacity(0.26), in: shape)
                .overlay(aiGenerationBorder(shape))
                .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        }
    }

    private func aiGenerationBorder(_ shape: RoundedRectangle) -> some View {
        shape.stroke(
            LinearGradient(
                colors: [
                    .white.opacity(0.64),
                    .white.opacity(0.22),
                    .black.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.7
        )
    }

    @ViewBuilder
    func voiceButtonSurface(isRecording: Bool) -> some View {
        let shape = Circle()

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(isRecording ? 0.09 : 0.04)).interactive(), in: shape)
                .background(.white.opacity(isRecording ? 0.36 : 0.26), in: shape)
                .overlay(voiceButtonBorder(shape))
                .shadow(color: .black.opacity(0.10), radius: 22, y: 10)
                .shadow(color: .white.opacity(0.42), radius: 1, y: -0.5)
        } else {
            background(.ultraThinMaterial, in: shape)
                .background(.white.opacity(isRecording ? 0.36 : 0.26), in: shape)
                .overlay(voiceButtonBorder(shape))
                .shadow(color: .black.opacity(0.09), radius: 20, y: 9)
        }
    }

    private func voiceButtonBorder(_ shape: Circle) -> some View {
        shape.stroke(
            LinearGradient(
                colors: [
                    .white.opacity(0.72),
                    .white.opacity(0.26),
                    .black.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.8
        )
    }
}
