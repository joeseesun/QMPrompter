import SwiftUI
import UIKit

struct ScriptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ScriptStore

    @State private var script: Script
    @State private var showPrompter = false
    @State private var showTitleEditor = false
    @State private var titleDraft = ""
    @State private var showClearConfirmation = false
    @State private var selectedTab: EditorTab = .script
    @State private var autosaveTask: Task<Void, Never>?
    @FocusState private var editorFocused: Bool

    init(script: Script) {
        _script = State(initialValue: script)
    }

    private var canStartPrompting: Bool {
        !script.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isStoredScript: Bool {
        store.script(with: script.id) != nil
    }

    private var canPersistScript: Bool {
        canStartPrompting || isStoredScript
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("编辑区域", selection: $selectedTab) {
                ForEach(EditorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            tabContent
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("修改文稿名", isPresented: $showTitleEditor) {
            TextField("文稿名", text: $titleDraft)
                .textInputAutocapitalization(.never)

            Button("取消", role: .cancel) {}
            Button("保存") {
                let nextTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                script.title = nextTitle.isEmpty ? "未命名文稿" : nextTitle
                saveIfPersistable()
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if selectedTab == .script {
                    editorActions
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button {
                    Haptics.mediumImpact()
                    startPrompting()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 24, height: 24)

                        Text("开始提词")
                            .font(.headline.weight(.semibold))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .editorGlassButton()
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(canStartPrompting ? 1 : 0.48)
                .disabled(!canStartPrompting)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .animation(.snappy(duration: 0.22), value: selectedTab)
            .background {
                EditorDockBackground()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    Haptics.selection()
                    beginTitleEditing()
                } label: {
                    HStack(spacing: 5) {
                        Text(displayTitle)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)

                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("修改文稿名")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    Haptics.success()
                    save()
                    dismiss()
                }
                .disabled(!canPersistScript)
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("完成") {
                    editorFocused = false
                }
                .fontWeight(.semibold)
            }
        }
        .fullScreenCover(isPresented: $showPrompter) {
            PrompterView(script: $script) {
                save()
            }
        }
        .confirmationDialog("清空正文", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("清空正文", role: .destructive) {
                Haptics.warning()
                clearContent()
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("文稿名和显示设置会保留。")
        }
        .onAppear {
            normalizeDisplaySettings()
        }
        .onChange(of: script) { _, _ in
            scheduleAutosave()
        }
        .onDisappear {
            flushPendingAutosave()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .script:
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground).opacity(0.42))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.34), lineWidth: 0.7)
                    )
                    .shadow(color: .black.opacity(0.035), radius: 16, y: 8)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $script.content)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .font(.system(size: 17, weight: .regular, design: .default))
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .focused($editorFocused)

                    if script.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("输入口播正文")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary.opacity(0.64))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 24)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        case .display:
            ScrollView {
                VStack(spacing: 12) {
                    DisplayPreviewPanel(
                        text: displayPreviewText,
                        fontSize: script.fontSize,
                        textColor: script.textColorPreset.color,
                        overlayOpacity: script.overlayOpacity
                    )

                    DisplaySliderCard(
                        title: "字号",
                        systemName: "textformat.size",
                        value: $script.fontSize,
                        range: 12...110,
                        step: 1,
                        label: "\(Int(script.fontSize))"
                    )

                    DisplaySliderCard(
                        title: "速度",
                        systemName: "speedometer",
                        value: $script.scrollSpeed,
                        range: 20...260,
                        step: 2,
                        label: "\(Int(script.scrollSpeed)) 字/分"
                    )

                    TextColorSettingCard(selection: $script.textColorPreset)

                    DisplaySliderCard(
                        title: "摄像头透明度",
                        systemName: "camera.aperture",
                        value: cameraTransparencyBinding,
                        range: 0.18...0.82,
                        step: 0.02,
                        label: "\(Int(cameraTransparency * 100))%"
                    )
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 128)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private func save() {
        if script.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            script.title = "未命名文稿"
        }
        store.save(script)
    }

    private func saveIfPersistable() {
        guard canPersistScript else { return }
        save()
    }

    private func clearContent() {
        script.content = ""
        if isStoredScript {
            cancelScheduledAutosave()
            save()
        }
        editorFocused = true
    }

    private func startPrompting() {
        guard canStartPrompting else { return }

        editorFocused = false
        normalizeDisplaySettings()
        cancelScheduledAutosave()
        save()

        DispatchQueue.main.async {
            showPrompter = true
        }
    }

    private var displayTitle: String {
        let title = script.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "未命名文稿" : title
    }

    private var cameraTransparency: Double {
        min(0.82, max(0.18, 1 - script.overlayOpacity))
    }

    private var cameraTransparencyBinding: Binding<Double> {
        Binding(
            get: { cameraTransparency },
            set: { script.overlayOpacity = min(0.82, max(0.18, 1 - $0)) }
        )
    }

    private var displayPreviewText: String {
        let lines = script.content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let source = lines.first ?? "开始提词"

        if source.count <= 26 {
            return source
        }

        return String(source.prefix(26))
    }

    private var editorActions: some View {
        HStack(spacing: 10) {
            editorIconButton(
                systemName: "doc.on.clipboard",
                label: "粘贴正文"
            ) {
                pasteClipboardContent()
            }

            editorIconButton(
                systemName: "trash",
                label: "清空正文",
                isDisabled: script.content.isEmpty
            ) {
                showClearConfirmation = true
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.24), lineWidth: 0.7)
        )
    }

    private func editorIconButton(
        systemName: String,
        label: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.45) : Color.primary)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.20), lineWidth: 0.7)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }

    private func beginTitleEditing() {
        titleDraft = displayTitle
        showTitleEditor = true
    }

    private func pasteClipboardContent() {
        guard let pasted = UIPasteboard.general.string,
              !pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        if script.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            script.content = pasted
        } else {
            script.content += "\n" + pasted
        }
        editorFocused = true
    }

    private func normalizeDisplaySettings() {
        if !TextColorPreset.editorChoices.contains(script.textColorPreset) {
            script.textColorPreset = .white
        }
        script.fontSize = min(110, max(12, script.fontSize))
    }

    private func scheduleAutosave() {
        guard canPersistScript else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard canPersistScript else { return }
                autosaveTask = nil
                save()
            }
        }
    }

    private func flushPendingAutosave() {
        cancelScheduledAutosave()
        saveIfPersistable()
    }

    private func cancelScheduledAutosave() {
        autosaveTask?.cancel()
        autosaveTask = nil
    }

}

private struct DisplayPreviewPanel: View {
    let text: String
    let fontSize: Double
    let textColor: Color
    let overlayOpacity: Double

    private var previewFontSize: CGFloat {
        min(54, max(22, CGFloat(fontSize) * 0.72))
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cameraLikeGradient)
                .overlay(.black.opacity(overlayOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.36),
                                    .white.opacity(0.10),
                                    .black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.7
                        )
                )

            Text(text)
                .font(.system(size: previewFontSize, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineSpacing(max(5, previewFontSize * 0.12))
                .foregroundStyle(textColor.opacity(0.94))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .shadow(color: .black.opacity(0.42), radius: 8, y: 2)
                .padding(.horizontal, 24)
        }
        .frame(height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
    }

    private var cameraLikeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.72, green: 0.72, blue: 0.69),
                Color(red: 0.38, green: 0.40, blue: 0.42),
                Color(red: 0.15, green: 0.15, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct DisplaySliderCard: View {
    let title: String
    let systemName: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.36), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.46), lineWidth: 0.65)
                    )

                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.72))

                Spacer(minLength: 12)

                Text(label)
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Slider(value: $value, in: range, step: step)
                .tint(.primary.opacity(0.72))
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 14)
        .editorSettingSurface(cornerRadius: 22)
    }
}

private struct TextColorSettingCard: View {
    @Binding var selection: TextColorPreset

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.36), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.46), lineWidth: 0.65)
                    )

                Text("文字颜色")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.72))

                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(TextColorPreset.editorChoices) { preset in
                    Button {
                        Haptics.selection()
                        selection = preset
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .stroke(.black.opacity(preset == .white ? 0.12 : 0), lineWidth: 0.8)
                                )

                            Text(preset.name)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            Capsule()
                                .fill(selection == preset ? .white.opacity(0.58) : .white.opacity(0.18))
                        )
                        .overlay(
                            Capsule()
                                .stroke(selection == preset ? .white.opacity(0.72) : .white.opacity(0.26), lineWidth: 0.7)
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("文字颜色\(preset.name)")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 15)
        .padding(.bottom, 14)
        .editorSettingSurface(cornerRadius: 22)
    }
}

private enum EditorTab: String, CaseIterable, Identifiable {
    case script
    case display

    var id: String { rawValue }

    var title: String {
        switch self {
        case .script: "文稿"
        case .display: "显示"
        }
    }
}

private struct EditorDockBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground).opacity(0),
                Color(.systemGroupedBackground).opacity(0.74),
                Color(.systemGroupedBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private extension View {
    @ViewBuilder
    func editorGlassButton() -> some View {
        let shape = Capsule()

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.06)).interactive(), in: shape)
                .overlay(
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.58),
                                    .white.opacity(0.22),
                                    .white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.62),
                                    .white.opacity(0.22),
                                    .black.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
        }
    }

    @ViewBuilder
    func editorSettingSurface(cornerRadius: CGFloat = 18) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.045)).interactive(), in: shape)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.46), in: shape)
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.54),
                                .white.opacity(0.18),
                                .black.opacity(0.035)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
                )
                .shadow(color: .black.opacity(0.05), radius: 14, y: 8)
        } else {
            background(.ultraThinMaterial, in: shape)
                .background(Color(.secondarySystemGroupedBackground).opacity(0.46), in: shape)
                .overlay(
                    shape.stroke(.white.opacity(0.34), lineWidth: 0.65)
                )
                .shadow(color: .black.opacity(0.045), radius: 12, y: 7)
        }
    }

}

#Preview {
    NavigationStack {
        ScriptEditorView(
            script: Script(title: "试用", content: "第一句。\n第二句。")
        )
        .environmentObject(ScriptStore())
    }
}
