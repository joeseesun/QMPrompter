import SwiftUI

struct ScriptListView: View {
    @EnvironmentObject private var store: ScriptStore
    @StateObject private var apiKeyStore = APIKeyStore()
    @State private var draftScript: Script?
    @State private var searchText = ""
    @State private var path = NavigationPath()
    @State private var showSettings = false
    @State private var showNewScriptOptions = false
    @State private var showAIGeneration = false
    @State private var pendingGeneratedScriptID: Script.ID?
    @State private var pendingNewScriptAction: NewScriptAction?
    @FocusState private var searchFocused: Bool

    private var filteredScripts: [Script] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.scripts }

        return store.scripts.filter { script in
            script.title.localizedCaseInsensitiveContains(query) ||
                script.content.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                HomeAmbientBackground()

                if store.scripts.isEmpty {
                    emptyState
                } else {
                    scriptScrollView
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Script.ID.self) { id in
                if let script = store.script(with: id) {
                    ScriptEditorView(script: script)
                } else {
                    ContentUnavailableView("文稿不存在", systemImage: "doc.text.magnifyingglass")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !store.scripts.isEmpty {
                    HomeSearchBar(text: $searchText, isFocused: $searchFocused)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                        .background(HomeSearchDockBackground())
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.selection()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .homeToolbarSurface()
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设置")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.selection()
                        showNewScriptOptions = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .homeToolbarSurface()
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新建文稿")
                }
            }
            .sheet(isPresented: $showSettings) {
                AppSettingsView(apiKeyStore: apiKeyStore)
            }
            .sheet(isPresented: $showNewScriptOptions, onDismiss: openPendingNewScriptAction) {
                NewScriptOptionsView(
                    onManualInput: { chooseNewScriptAction(.manualInput) },
                    onAIGeneration: { chooseNewScriptAction(.aiGeneration) }
                )
                .presentationDetents([.height(224)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
                .presentationBackground(.ultraThinMaterial)
            }
            .sheet(isPresented: $showAIGeneration, onDismiss: openPendingGeneratedScript) {
                AIGenerationView(apiKeyStore: apiKeyStore) { script in
                    store.save(script)
                    pendingGeneratedScriptID = script.id
                    showAIGeneration = false
                }
            }
            .sheet(item: $draftScript) { script in
                NavigationStack {
                    ScriptEditorView(script: script)
                }
            }
        }
    }

    private func chooseNewScriptAction(_ action: NewScriptAction) {
        Haptics.selection()
        pendingNewScriptAction = action
        showNewScriptOptions = false
    }

    private func openPendingNewScriptAction() {
        guard let action = pendingNewScriptAction else { return }
        pendingNewScriptAction = nil
        performNewScriptAction(action)
    }

    private func performNewScriptAction(_ action: NewScriptAction) {
        switch action {
        case .manualInput:
            draftScript = store.createDraft()
        case .aiGeneration:
            showAIGeneration = true
        }
    }

    private var scriptScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "提词器文稿" : "搜索结果")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 10)

                if filteredScripts.isEmpty {
                    searchEmptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 64)
                } else {
                    ForEach(filteredScripts) { script in
                        Button {
                            Haptics.selection()
                            searchFocused = false
                            path.append(script.id)
                        } label: {
                            ScriptCard(script: script)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Haptics.warning()
                                store.delete(script)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 112)
        }
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, height: 72)
                .homeToolbarSurface()

            Text("开始一篇文稿")
                .font(.headline.weight(.semibold))

            HStack(spacing: 12) {
                NewScriptOptionButton(
                    title: "手动输入",
                    systemName: "square.and.pencil",
                    action: {
                        Haptics.selection()
                        performNewScriptAction(.manualInput)
                    }
                )

                NewScriptOptionButton(
                    title: "AI 生成",
                    systemName: "sparkles",
                    action: {
                        Haptics.selection()
                        performNewScriptAction(.aiGeneration)
                    }
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("没有找到文稿")
                .font(.headline.weight(.semibold))

            Text("换个关键词试试")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func openPendingGeneratedScript() {
        guard let scriptID = pendingGeneratedScriptID else { return }
        pendingGeneratedScriptID = nil
        path.append(scriptID)
    }
}

private enum NewScriptAction {
    case manualInput
    case aiGeneration
}

private struct NewScriptOptionsView: View {
    let onManualInput: () -> Void
    let onAIGeneration: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("新建文稿")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                NewScriptOptionButton(
                    title: "手动输入",
                    systemName: "square.and.pencil",
                    action: onManualInput
                )

                NewScriptOptionButton(
                    title: "AI 生成",
                    systemName: "sparkles",
                    action: onAIGeneration
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct NewScriptOptionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.38), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.52), lineWidth: 0.7)
                    )

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 112)
            .liquidCardSurface(cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct HomeSearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)

            TextField("搜索文稿", text: $text)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused(isFocused)

            if !text.isEmpty {
                Button {
                    Haptics.selection()
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(height: 56)
        .liquidSearchSurface()
    }
}

private struct HomeAmbientBackground: View {
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

private struct HomeSearchDockBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground).opacity(0),
                Color(.systemBackground).opacity(0.72),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct ScriptCard: View {
    let script: Script
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(script.title.isEmpty ? "未命名文稿" : script.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text("\(script.content.count) 字")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.48), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.46), lineWidth: 0.5)
                    )
            }

            Text(script.preview.isEmpty ? "还没有正文" : script.preview)
                .font(.subheadline)
                .foregroundStyle(.secondary.opacity(0.88))
                .lineLimit(2)

            Text("更新 \(dateString(script.updatedAt))")
            .font(.caption2)
            .foregroundStyle(.secondary.opacity(0.72))
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCardSurface(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func dateString(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}

private extension View {
    @ViewBuilder
    func liquidCardSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.04)).interactive(), in: shape)
                .background(cardFill(shape))
                .overlay(cardBorder(shape))
                .shadow(color: .black.opacity(0.055), radius: 16, y: 8)
                .shadow(color: .white.opacity(0.44), radius: 1, y: -0.5)
        } else {
            background(.ultraThinMaterial, in: shape)
                .background(cardFill(shape))
                .overlay(cardBorder(shape))
                .shadow(color: .black.opacity(0.05), radius: 16, y: 8)
        }
    }

    @ViewBuilder
    func liquidSearchSurface() -> some View {
        let shape = Capsule()

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.05)).interactive(), in: shape)
                .background(.white.opacity(0.34), in: shape)
                .overlay(
                    shape.stroke(.white.opacity(0.46), lineWidth: 0.65)
                )
                .shadow(color: .black.opacity(0.065), radius: 18, y: 8)
        } else {
            background(.ultraThinMaterial, in: shape)
                .background(.white.opacity(0.32), in: shape)
                .overlay(
                    shape.stroke(.white.opacity(0.40), lineWidth: 0.65)
                )
                .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
        }
    }

    @ViewBuilder
    func homeToolbarSurface() -> some View {
        let shape = Circle()

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.04)).interactive(), in: shape)
                .background(.white.opacity(0.28), in: shape)
                .overlay(
                    shape.stroke(.white.opacity(0.45), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.055), radius: 14, y: 7)
        } else {
            background(.ultraThinMaterial, in: shape)
                .background(.white.opacity(0.26), in: shape)
                .overlay(
                    shape.stroke(.white.opacity(0.38), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.05), radius: 13, y: 7)
        }
    }

    private func cardFill(_ shape: RoundedRectangle) -> some View {
        shape.fill(
            LinearGradient(
                colors: [
                    .white.opacity(0.34),
                    .white.opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func cardBorder(_ shape: RoundedRectangle) -> some View {
        shape.stroke(
            LinearGradient(
                colors: [
                    .white.opacity(0.58),
                    .white.opacity(0.16),
                    .black.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 0.55
        )
    }
}

#Preview {
    ScriptListView()
        .environmentObject(ScriptStore())
}
