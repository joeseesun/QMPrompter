import SwiftUI

struct ScriptListView: View {
    @EnvironmentObject private var store: ScriptStore
    @StateObject private var apiKeyStore = APIKeyStore()
    @State private var draftScript: Script?
    @State private var searchText = ""
    @State private var path = NavigationPath()
    @State private var showSettings = false
    @State private var showAIGeneration = false
    @State private var pendingGeneratedScriptID: Script.ID?

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
            Group {
                if store.scripts.isEmpty {
                    ContentUnavailableView("还没有文稿", systemImage: "doc.badge.plus", description: Text("新建一篇正文后即可开始提词。"))
                } else {
                    List {
                        Section {
                            ForEach(filteredScripts) { script in
                                Button {
                                    path.append(script.id)
                                } label: {
                                    ScriptCard(script: script)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.delete(script)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                            }
                            .onDelete(perform: deleteFilteredScripts)
                        } header: {
                            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "提词器文稿" : "搜索结果")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 0)
                    .scrollContentBackground(.hidden)
                    .background(HomeAmbientBackground())
                    .overlay {
                        if filteredScripts.isEmpty {
                            ContentUnavailableView("没有找到文稿", systemImage: "magnifyingglass", description: Text("换个关键词试试。"))
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索文稿")
            .navigationDestination(for: Script.ID.self) { id in
                if let script = store.script(with: id) {
                    ScriptEditorView(script: script)
                } else {
                    ContentUnavailableView("文稿不存在", systemImage: "doc.text.magnifyingglass")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            draftScript = store.createDraft()
                        } label: {
                            Label("手动输入", systemImage: "square.and.pencil")
                        }

                        Button {
                            showAIGeneration = true
                        } label: {
                            Label("AI 生成", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新建文稿")
                }
            }
            .sheet(isPresented: $showSettings) {
                AppSettingsView(apiKeyStore: apiKeyStore)
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

    private func deleteFilteredScripts(at offsets: IndexSet) {
        let scriptsToDelete = offsets.compactMap { index in
            filteredScripts.indices.contains(index) ? filteredScripts[index] : nil
        }

        for script in scriptsToDelete {
            store.delete(script)
        }
    }

    private func openPendingGeneratedScript() {
        guard let scriptID = pendingGeneratedScriptID else { return }
        pendingGeneratedScriptID = nil
        path.append(scriptID)
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

    private func cardFill(_ shape: RoundedRectangle) -> some View {
        shape.fill(
            LinearGradient(
                colors: [
                    .white.opacity(0.46),
                    .white.opacity(0.22)
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
