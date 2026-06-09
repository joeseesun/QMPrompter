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
    @State private var generationTask: Task<Void, Never>?

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
                        noticeCard("请先在首页左上角设置 DeepSeek API Key。", systemName: "key")
                    }

                    if let message = errorMessage ?? dictation.errorMessage {
                        noticeCard(message, systemName: "exclamationmark.triangle")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)
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
            }
            .safeAreaInset(edge: .bottom) {
                VoiceInputButton(
                    isRecording: dictation.isRecording,
                    isDisabled: isGenerating
                ) {
                    Haptics.lightImpact()
                    toggleDictation()
                }
                .padding(.top, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: dictation.transcript) { _, transcript in
                guard !transcript.isEmpty else { return }
                prompt = mergedDictationPrompt(with: transcript)
            }
            .onDisappear {
                cancelGeneration()
                dictation.stop()
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

                if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入或说出你想生成的内容。")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary.opacity(0.78))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
        .aiGenerationGlassSurface(cornerRadius: 24)
    }

    private func noticeCard(_ text: String, systemName: String) -> some View {
        Label(text, systemImage: systemName)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .aiGenerationGlassSurface(cornerRadius: 18)
    }

    private func startGeneration() {
        guard canGenerate else { return }
        Haptics.mediumImpact()
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

        promptBeforeDictation = prompt
        dictation.start()
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
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 88, height: 88)
                .voiceButtonSurface(isRecording: isRecording)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.62 : 1)
        .scaleEffect(isRecording ? 1.04 : 1)
        .animation(.snappy(duration: 0.22), value: isRecording)
        .accessibilityLabel(isRecording ? "停止语音输入" : "开始语音输入")
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
