import SwiftUI
import UIKit

struct PrompterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var script: Script
    let onSave: () -> Void

    @StateObject private var engine = ScrollEngine()
    @StateObject private var speechFollower = SpeechFollower()
    @State private var cameraPermission: CameraPermissionState = .checking
    @State private var showSettingsPanel = false
    @State private var speechLineIndex: Int?
    @State private var isManualDragging = false
    @State private var dragStartOffset: CGFloat = 0
    @State private var promptLayout: PromptLayout = .empty
    @State private var lastFormattedWidth: CGFloat = 0
    @State private var lastFormattedFontSize: Double = 0
    @State private var lastFormattedContent = ""
    @State private var latestMaximumOffset: CGFloat = 0
    @State private var hasStartedDefaultSpeech = false
    @State private var speechStartPending = false
    @State private var pendingSettingsSave = false
    @State private var settingsSaveTask: Task<Void, Never>?
    @State private var previousIdleTimerDisabled: Bool?

    var body: some View {
        GeometryReader { proxy in
            let layout = promptLayout
            let topPadding = proxy.size.height * 0.40
            let isSpeedMode = !speechStartPending && speechFollower.state == .idle
            let bottomPadding = proxy.size.height * (showSettingsPanel ? (isSpeedMode ? 0.46 : 0.40) : 0.34)
            let totalHeight = layout.contentHeight + topPadding + bottomPadding
            let maxOffset = max(0, totalHeight - proxy.size.height)
            let scrollingIndex = lineIndex(
                atContentY: max(0, engine.offset - topPadding + layout.averageLineHeight * 0.42),
                layouts: layout.lineLayouts
            )
            let currentIndex = layout.lines.isEmpty ? 0 : (speechFollower.isListening ? min(layout.lines.count - 1, max(0, speechLineIndex ?? scrollingIndex)) : scrollingIndex)
            let shouldHighlightCurrentLine = speechFollower.isListening

            ZStack {
                CameraPreview(permissionState: $cameraPermission)
                    .ignoresSafeArea()
                    .overlay(.black.opacity(cameraPermission == .authorized ? script.overlayOpacity : 0.78))

                if cameraPermission != .authorized {
                    cameraStatusView
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PromptTextLayer(
                        position: engine.position,
                        script: script,
                        layout: layout,
                        topPadding: topPadding,
                        currentIndex: currentIndex,
                        shouldHighlightCurrentLine: shouldHighlightCurrentLine,
                        viewportHeight: proxy.size.height
                    )
                    .frame(height: proxy.size.height)
                    .mask(PromptViewportFadeMask())
                    .clipped()
                    Spacer(minLength: 0)
                }

                interactionLayer()
                .zIndex(1)

                if !showSettingsPanel && maxOffset > 0 {
                    PromptProgressRail(position: engine.position, maxOffset: maxOffset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                        .padding(.top, proxy.safeAreaInsets.top + 126)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 132)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(2)
                }

                if showSettingsPanel {
                    settingsPanel(maxOffset: maxOffset)
                        .environment(\.colorScheme, .dark)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .zIndex(3)
                }

                topBar
                    .environment(\.colorScheme, .dark)
                    .zIndex(5)
            }
            .background(Color.black)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .contentShape(Rectangle())
            .onAppear {
                beginPrompterSession()
                let updatedLayout = refreshPromptLayout(width: proxy.size.width)
                let updatedMaxOffset = maximumOffset(
                    for: updatedLayout,
                    viewportHeight: proxy.size.height,
                    topPadding: topPadding,
                    bottomPadding: bottomPadding
                )
                latestMaximumOffset = updatedMaxOffset
                configureEngine(with: updatedLayout, maximumOffset: updatedMaxOffset)
                startDefaultSpeechIfNeeded(maxOffset: updatedMaxOffset)
            }
            .onChange(of: script.scrollSpeed) { _, value in
                engine.setSpeed(value)
            }
            .onChange(of: engine.speed) { _, value in
                script.scrollSpeed = value
                scheduleSettingsSave()
            }
            .onChange(of: script.fontSize) { _, _ in
                let updatedLayout = refreshPromptLayout(width: proxy.size.width)
                configureEngine(with: updatedLayout, maximumOffset: maxOffset)
                scheduleSettingsSave()
            }
            .onChange(of: script.content) { _, _ in
                let updatedLayout = refreshPromptLayout(width: proxy.size.width)
                configureEngine(with: updatedLayout, maximumOffset: maxOffset)
            }
            .onChange(of: proxy.size.width) { _, width in
                let updatedLayout = refreshPromptLayout(width: width)
                configureEngine(with: updatedLayout, maximumOffset: maxOffset)
            }
            .onChange(of: maxOffset) { _, value in
                latestMaximumOffset = value
                configureEngine(with: layout, maximumOffset: value)
            }
            .onChange(of: speechFollower.progress) { _, progress in
                guard speechFollower.isListening else { return }
                let lineIndex = speechLineIndex(for: progress, promptLines: layout.lines)
                speechLineIndex = lineIndex
                engine.follow(to: speechTargetOffset(
                    for: lineIndex,
                    layouts: layout.lineLayouts,
                    topPadding: topPadding,
                    viewportHeight: proxy.size.height,
                    maximumOffset: maxOffset
                ))
            }
            .onChange(of: speechFollower.state) { _, state in
                if state != .idle {
                    speechStartPending = false
                }
                if state != .listening {
                    speechLineIndex = nil
                    engine.stopFollowing()
                }
            }
            .onChange(of: script.textColorPreset) { _, _ in scheduleSettingsSave() }
            .onChange(of: script.overlayOpacity) { _, _ in scheduleSettingsSave() }
            .onDisappear {
                endPrompterSession()
                flushPendingSettingsSave()
                speechFollower.stop()
                engine.stopFollowing()
            }
        }
    }

    private func beginPrompterSession() {
        guard previousIdleTimerDisabled == nil else { return }
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func endPrompterSession() {
        guard let previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        self.previousIdleTimerDisabled = nil
    }

    @discardableResult
    private func refreshPromptLayout(width: CGFloat) -> PromptLayout {
        let normalizedWidth = max(1, width.rounded(.down))
        guard normalizedWidth != lastFormattedWidth ||
            script.fontSize != lastFormattedFontSize ||
            script.content != lastFormattedContent
        else {
            return promptLayout
        }

        let targetCharacters = targetCharactersPerLine(width: width, fontSize: script.fontSize)
        let lines = PromptFormatter.lines(from: script.content, targetCharactersPerLine: targetCharacters)
        let fontSize = CGFloat(script.fontSize)
        let baseLineHeight = promptBaseLineHeight(fontSize: fontSize)
        let textWidth = promptTextWidth(for: width)
        let lineLayouts = promptLineLayouts(
            for: lines,
            width: textWidth,
            fontSize: fontSize,
            baseLineHeight: baseLineHeight
        )
        let layout = PromptLayout(
            lines: lines,
            lineLayouts: lineLayouts,
            textWidth: textWidth,
            contentHeight: lineLayouts.last.map { $0.y + $0.height } ?? 0,
            averageLineHeight: averagePromptLineHeight(for: lineLayouts, fallback: baseLineHeight),
            averageCharactersPerLine: averageCharactersPerLine(for: lines)
        )

        promptLayout = layout
        lastFormattedWidth = normalizedWidth
        lastFormattedFontSize = script.fontSize
        lastFormattedContent = script.content
        return layout
    }

    private func configureEngine(with layout: PromptLayout, maximumOffset: CGFloat) {
        engine.configure(
            speed: script.scrollSpeed,
            lineHeight: layout.averageLineHeight,
            averageCharactersPerLine: layout.averageCharactersPerLine,
            maximumOffset: maximumOffset
        )
    }

    private func maximumOffset(
        for layout: PromptLayout,
        viewportHeight: CGFloat,
        topPadding: CGFloat,
        bottomPadding: CGFloat
    ) -> CGFloat {
        max(0, layout.contentHeight + topPadding + bottomPadding - viewportHeight)
    }

    private func scheduleSettingsSave() {
        pendingSettingsSave = true
        settingsSaveTask?.cancel()
        settingsSaveTask = Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                pendingSettingsSave = false
                onSave()
            }
        }
    }

    private func flushPendingSettingsSave() {
        settingsSaveTask?.cancel()
        settingsSaveTask = nil

        if pendingSettingsSave {
            pendingSettingsSave = false
            onSave()
        }
    }

    private func targetCharactersPerLine(width: CGFloat, fontSize: Double) -> Int {
        let usableWidth = max(220, width - 44)
        let fontSize = CGFloat(fontSize)
        let estimatedCharacterWidth = max(8, fontSize * 0.82)
        let estimatedCount = Int((usableWidth / estimatedCharacterWidth) * 0.88)
        return max(4, min(30, estimatedCount))
    }

    private func promptBaseLineHeight(fontSize: CGFloat) -> CGFloat {
        max(fontSize * 1.34, fontSize + 12)
    }

    private func promptLineSpacing(fontSize: CGFloat) -> CGFloat {
        max(4, fontSize * 0.10)
    }

    private func promptTextWidth(for viewportWidth: CGFloat) -> CGFloat {
        max(1, viewportWidth - 40)
    }

    private func promptLineLayouts(
        for promptLines: [PromptLine],
        width: CGFloat,
        fontSize: CGFloat,
        baseLineHeight: CGFloat
    ) -> [PromptLineLayout] {
        var currentY: CGFloat = 0
        let usableWidth = max(1, width)

        return promptLines.enumerated().map { index, line in
            let rowHeight = measuredPromptLineHeight(
                for: line.text,
                width: usableWidth,
                fontSize: fontSize,
                baseLineHeight: baseLineHeight
            )
            let layout = PromptLineLayout(index: index, line: line, y: currentY, height: rowHeight)
            currentY += rowHeight
            return layout
        }
    }

    private func measuredPromptLineHeight(
        for text: String,
        width: CGFloat,
        fontSize: CGFloat,
        baseLineHeight: CGFloat
    ) -> CGFloat {
        let verticalPadding = max(16, fontSize * 0.28)
        guard !text.isEmpty else {
            return baseLineHeight * 0.72 + verticalPadding
        }

        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = promptLineSpacing(fontSize: fontSize)
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        let measured = attributedText.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let estimatedLineCount = estimatedVisualLineCount(for: text, width: width, fontSize: fontSize)
        let estimatedHeight = CGFloat(estimatedLineCount) * baseLineHeight

        return max(baseLineHeight, ceil(max(measured.height, estimatedHeight)) + verticalPadding)
    }

    private func estimatedVisualLineCount(for text: String, width: CGFloat, fontSize: CGFloat) -> Int {
        let visibleCharacterCount = max(1, text.filter { !$0.isWhitespace }.count)
        let estimatedGlyphWidth = max(8, fontSize * 0.88)
        let estimatedCharactersPerLine = max(1, Int((width / estimatedGlyphWidth).rounded(.down)))
        return max(1, Int(ceil(Double(visibleCharacterCount) / Double(estimatedCharactersPerLine))))
    }

    private func averagePromptLineHeight(for layouts: [PromptLineLayout], fallback: CGFloat) -> CGFloat {
        guard !layouts.isEmpty else { return fallback }
        let sum = layouts.reduce(CGFloat(0)) { $0 + $1.height }
        return max(fallback, sum / CGFloat(layouts.count))
    }

    private func lineIndex(atContentY contentY: CGFloat, layouts: [PromptLineLayout]) -> Int {
        guard !layouts.isEmpty else { return 0 }

        var lowerBound = 0
        var upperBound = layouts.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if contentY <= layouts[middle].y + layouts[middle].height {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }

        return layouts[min(lowerBound, layouts.count - 1)].index
    }

    private func averageCharactersPerLine(for promptLines: [PromptLine]) -> CGFloat {
        guard !promptLines.isEmpty else { return 12 }
        let sum = promptLines.reduce(0) { $0 + $1.characterCount }
        return CGFloat(max(6, sum / promptLines.count))
    }

    private var topBar: some View {
        VStack {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    Haptics.lightImpact()
                    engine.pause()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 42)
                        .glassCircle()
                        .contentShape(Circle())
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("关闭提词")
                .buttonStyle(.plain)

                Spacer(minLength: 12)

                Button {
                    Haptics.selection()
                    withAnimation(.snappy(duration: 0.22)) {
                        showSettingsPanel.toggle()
                    }
                } label: {
                    Image(systemName: showSettingsPanel ? "gearshape.fill" : "gearshape")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 42, height: 42)
                        .glassCircle()
                        .contentShape(Circle())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showSettingsPanel ? "关闭设置" : "打开设置")
            }
            .frame(height: 42, alignment: .center)
            .overlay {
                modeStatusButton
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer()
        }
    }

    private var speedText: String {
        "\(Int(engine.speed)) 字/分"
    }

    private var speedModeActive: Bool {
        !speechStartPending && speechFollower.state == .idle
    }

    private var modeStatusButton: some View {
        Button {
            Haptics.selection()
            toggleModeFromStatusPill()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: modeStatusIcon)
                    .font(.system(size: 12, weight: .bold))

                Text(modeStatusText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassCapsule()
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(modeStatusAccessibilityLabel)
    }

    private var modeStatusIcon: String {
        if speechStartPending || speechFollower.isListening {
            return "waveform"
        }

        if speechFollower.state != .idle {
            return "exclamationmark.circle"
        }

        return "speedometer"
    }

    private var modeStatusText: String {
        if speechStartPending {
            return "正在准备语音"
        }

        if speechFollower.state != .idle {
            return speechFollower.statusText
        }

        return speedText
    }

    private var modeStatusAccessibilityLabel: String {
        if speechStartPending || speechFollower.state != .idle {
            switch speechFollower.state {
            case .denied:
                return "打开语音权限设置"
            case .unavailable, .failed:
                return "重新启动语音跟随"
            case .idle, .listening:
                return "切换到速度控制"
            }
        }

        return "切换到语音跟随"
    }

    private var cameraStatusView: some View {
        VStack(spacing: 14) {
            Image(systemName: cameraPermission == .denied ? "camera.fill.badge.ellipsis" : "camera.viewfinder")
                .font(.system(size: 42, weight: .semibold))
            Text(cameraStatusTitle)
                .font(.headline)
            Text(cameraStatusMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 280)

            if cameraPermission == .denied {
                Button {
                    openAppSettings()
                } label: {
                    Text("打开设置")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .glassCapsule()
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
    }

    private var cameraStatusTitle: String {
        switch cameraPermission {
        case .checking: "正在请求摄像头"
        case .authorized: ""
        case .denied: "摄像头权限未开启"
        case .unavailable: "无法使用前置摄像头"
        }
    }

    private var cameraStatusMessage: String {
        switch cameraPermission {
        case .checking: "首次打开会弹出权限确认。"
        case .authorized: ""
        case .denied: "请到系统设置里允许乔木提词器访问摄像头。"
        case .unavailable: "当前设备或运行环境没有可用的前置摄像头。"
        }
    }

    private func interactionLayer() -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: handleCanvasTap)
            .gesture(manualScrollGesture)
        .ignoresSafeArea()
    }

    private func handleCanvasTap() {
        if showSettingsPanel {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.2)) {
                showSettingsPanel = false
            }
            return
        }

        if speechFollower.isListening {
            return
        }

        Haptics.selection()
        engine.toggle()
    }

    private func settingsPanel(maxOffset: CGFloat) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 14) {
                if speedModeActive {
                    speedModeSettings(maxOffset: maxOffset)
                } else {
                    speechModeSettings(maxOffset: maxOffset)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(maxWidth: 390)
            .glassPanel(cornerRadius: 24)
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func speedModeSettings(maxOffset: CGFloat) -> some View {
        transportControls

        VStack(spacing: 12) {
            fontSizeSlider

            controlSlider(
                title: "速度",
                value: Binding(
                    get: { script.scrollSpeed },
                    set: {
                        script.scrollSpeed = $0
                        engine.setSpeed($0)
                    }
                ),
                range: 20...260,
                label: "\(Int(script.scrollSpeed)) 字/分"
            )

            progressSlider(maxOffset: maxOffset)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func speechModeSettings(maxOffset: CGFloat) -> some View {
        VStack(spacing: 12) {
            fontSizeSlider
            progressSlider(maxOffset: maxOffset)
        }
        .padding(.horizontal, 4)
    }

    private var transportControls: some View {
        HStack(spacing: 10) {
            glassIconButton(
                systemName: "gobackward.10",
                accessibilityLabel: "后退"
            ) {
                engine.setOffset(max(0, engine.offset - 240))
            }

            Button {
                Haptics.selection()
                engine.toggle()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .frame(width: 52, height: 42)
                    .foregroundStyle(.primary)
                    .glassCapsule()
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isPlaying ? "暂停" : "播放")

            glassIconButton(
                systemName: "goforward.10",
                accessibilityLabel: "前进"
            ) {
                engine.setOffset(engine.offset + 240)
            }

            Divider()
                .frame(height: 28)
                .overlay(.white.opacity(0.22))

            glassIconButton(
                systemName: "arrow.counterclockwise",
                accessibilityLabel: "回到开头"
            ) {
                engine.reset()
            }
        }
    }

    private var fontSizeSlider: some View {
        controlSlider(
            title: "字号",
            value: Binding(
                get: { script.fontSize },
                set: { script.fontSize = $0 }
            ),
            range: 12...110,
            label: "\(Int(script.fontSize))"
        )
    }

    private func progressSlider(maxOffset: CGFloat) -> some View {
        PromptProgressSlider(
            position: engine.position,
            maxOffset: maxOffset,
            setOffset: {
                stopSpeechFollowerForManualPositioning()
                engine.setOffset($0)
            }
        )
    }

    private func glassIconButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 42, height: 42)
                .foregroundStyle(.primary)
                .glassCircle()
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func controlSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        label: String
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            }
            Slider(value: value, in: range)
                .tint(.white.opacity(0.86))
        }
    }

    private func progress(maxOffset: CGFloat) -> CGFloat {
        guard maxOffset > 0 else { return 0 }
        return min(1, max(0, engine.offset / maxOffset))
    }

    private var manualScrollGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if !isManualDragging {
                    isManualDragging = true
                    dragStartOffset = engine.offset
                }

                if abs(value.translation.height) <= 12 {
                    return
                }

                stopSpeechFollowerForManualPositioning()
                engine.setOffset(dragStartOffset - value.translation.height * 1.05)
            }
            .onEnded { _ in
                isManualDragging = false
                dragStartOffset = engine.offset
            }
    }

    private func toggleModeFromStatusPill() {
        if speechStartPending || speechFollower.isListening {
            switchToSpeedControl()
            return
        }

        switch speechFollower.state {
        case .idle:
            startSpeechFollower(maxOffset: latestMaximumOffset)
        case .denied:
            openAppSettings()
        case .unavailable, .failed:
            speechFollower.reset()
            startSpeechFollower(maxOffset: latestMaximumOffset)
        case .listening:
            switchToSpeedControl()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func switchToSpeedControl() {
        engine.stopFollowing()
        engine.pause()
        speechStartPending = false
        speechFollower.reset()

        withAnimation(.snappy(duration: 0.22)) {
            showSettingsPanel = true
        }
    }

    private func startDefaultSpeechIfNeeded(maxOffset: CGFloat) {
        guard !hasStartedDefaultSpeech else { return }
        hasStartedDefaultSpeech = true
        startSpeechFollower(maxOffset: maxOffset)
    }

    private func startSpeechFollower(maxOffset: CGFloat) {
        guard !script.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        engine.pause()
        engine.stopFollowing()
        speechLineIndex = nil
        speechStartPending = true

        withAnimation(.snappy(duration: 0.2)) {
            showSettingsPanel = false
        }

        speechFollower.start(content: script.content, initialProgress: Double(progress(maxOffset: maxOffset)))
    }

    private func stopSpeechFollowerForManualPositioning() {
        engine.pause()
        engine.stopFollowing()

        if speechFollower.isListening {
            speechFollower.stop()
            speechLineIndex = nil
        }
    }

    private func speechLineIndex(for progress: Double, promptLines: [PromptLine]) -> Int {
        let speakableLines = promptLines.enumerated().filter { isSpeakableLine($0.element.text) }
        guard !speakableLines.isEmpty else { return 0 }

        let counts = speakableLines.map { max(1, speechCharacterCount($0.element.text)) }
        let total = counts.reduce(0, +)
        let rawTarget = max(1, Int((Double(total) * progress).rounded(.down)))
        let target = progress >= 0.995 ? total : max(1, rawTarget - 2)
        var running = 0

        for (index, count) in counts.enumerated() {
            running += count
            if target <= running {
                return speakableLines[index].offset
            }
        }

        return speakableLines.last?.offset ?? 0
    }

    private func speechTargetOffset(
        for lineIndex: Int,
        layouts: [PromptLineLayout],
        topPadding: CGFloat,
        viewportHeight: CGFloat,
        maximumOffset: CGFloat
    ) -> CGFloat {
        let targetTop = max(132, viewportHeight * 0.34)
        let lineY = layouts.first(where: { $0.index == lineIndex })?.y ?? 0
        let rawOffset = topPadding + lineY - targetTop
        return min(maximumOffset, max(0, rawOffset))
    }

    private func speechCharacterCount(_ text: String) -> Int {
        text.filter { $0.isLetter || $0.isNumber }.count
    }

    private func isSpeakableLine(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }
}

private struct PromptLineLayout: Equatable {
    let index: Int
    let line: PromptLine
    let y: CGFloat
    let height: CGFloat
}

private struct PromptLayout: Equatable {
    static let empty = PromptLayout(
        lines: [],
        lineLayouts: [],
        textWidth: 0,
        contentHeight: 0,
        averageLineHeight: 84,
        averageCharactersPerLine: 18
    )

    let lines: [PromptLine]
    let lineLayouts: [PromptLineLayout]
    let textWidth: CGFloat
    let contentHeight: CGFloat
    let averageLineHeight: CGFloat
    let averageCharactersPerLine: CGFloat
}

private struct PromptTextLayer: View {
    @ObservedObject var position: ScrollPosition

    let script: Script
    let layout: PromptLayout
    let topPadding: CGFloat
    let currentIndex: Int
    let shouldHighlightCurrentLine: Bool
    let viewportHeight: CGFloat

    var body: some View {
        let visibleRange = visibleLayoutRange

        ZStack(alignment: .top) {
            ForEach(Array(visibleRange), id: \.self) { index in
                let lineLayout = layout.lineLayouts[index]
                let isHighlighted = shouldHighlightCurrentLine &&
                    lineLayout.index == currentIndex &&
                    isSpeakableLine(lineLayout.line.text)

                Text(lineLayout.line.text)
                    .font(.system(size: script.fontSize, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineSpacing(max(4, CGFloat(script.fontSize) * 0.10))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(textColor(isHighlighted: isHighlighted))
                    .shadow(color: isHighlighted ? .white.opacity(0.46) : .clear, radius: 11)
                    .shadow(color: isHighlighted ? .black.opacity(0.36) : .clear, radius: 4, y: 1)
                    .frame(width: layout.textWidth, height: lineLayout.height, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .animation(.easeInOut(duration: 0.16), value: currentIndex)
                    .offset(y: topPadding + lineLayout.y - position.offset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var visibleLayoutRange: Range<Int> {
        guard !layout.lineLayouts.isEmpty else { return 0..<0 }

        let visibleTop = position.offset - topPadding - viewportHeight * 0.35
        let visibleBottom = position.offset - topPadding + viewportHeight * 1.35
        let start = max(0, firstLayoutEnding(after: visibleTop) - 2)
        let end = min(layout.lineLayouts.count, firstLayoutStarting(after: visibleBottom) + 2)
        return start..<end
    }

    private func firstLayoutEnding(after y: CGFloat) -> Int {
        var lowerBound = 0
        var upperBound = layout.lineLayouts.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            let line = layout.lineLayouts[middle]
            if line.y + line.height >= y {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }

        return min(lowerBound, layout.lineLayouts.count - 1)
    }

    private func firstLayoutStarting(after y: CGFloat) -> Int {
        var lowerBound = 0
        var upperBound = layout.lineLayouts.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if layout.lineLayouts[middle].y > y {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }

        return lowerBound
    }

    private func isSpeakableLine(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    private func textColor(isHighlighted: Bool) -> Color {
        if shouldHighlightCurrentLine {
            return isHighlighted ? .white : script.textColorPreset.color.opacity(0.58)
        }

        return script.textColorPreset.color.opacity(0.92)
    }
}

private struct PromptViewportFadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.90),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private struct PromptProgressSlider: View {
    @ObservedObject var position: ScrollPosition

    let maxOffset: CGFloat
    let setOffset: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("进度")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
            }

            Slider(
                value: Binding(
                    get: { Double(position.offset) },
                    set: { setOffset(CGFloat($0)) }
                ),
                in: 0...max(1, Double(maxOffset))
            )
            .tint(.white.opacity(0.86))
        }
    }

    private var progress: CGFloat {
        guard maxOffset > 0 else { return 0 }
        return min(1, max(0, position.offset / maxOffset))
    }
}

private struct PromptProgressRail: View {
    @ObservedObject var position: ScrollPosition

    let maxOffset: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let progress = currentProgress
            let trackHeight = max(44, proxy.size.height)
            let thumbHeight = max(28, min(trackHeight * 0.28, 64))
            let travel = max(0, trackHeight - thumbHeight)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(.white.opacity(0.13))
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.16), lineWidth: 0.5)
                    )

                Capsule()
                    .fill(.white.opacity(0.62))
                    .frame(height: thumbHeight)
                    .shadow(color: .black.opacity(0.14), radius: 7, y: 2)
                    .offset(y: travel * progress)
            }
        }
        .frame(width: 4)
    }

    private var currentProgress: CGFloat {
        guard maxOffset > 0 else { return 0 }
        return min(1, max(0, position.offset / maxOffset))
    }
}

private extension View {
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.04)).interactive(), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.20), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.04)).interactive(), in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.20), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        } else {
            background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
        }
    }

    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(.white.opacity(0.04)).interactive(), in: shape)
                .overlay(
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.34),
                                    .white.opacity(0.12),
                                    .white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.16), radius: 24, y: 14)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.30),
                                    .white.opacity(0.12),
                                    .white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.16), radius: 22, y: 12)
        }
    }
}

#Preview {
    PrompterView(
        script: .constant(
            Script(
                title: "试用",
                content: "大家好，这里是第一句。\n左侧滑动调速度，右侧滑动调进度。\n点击屏幕播放或暂停。"
            )
        ),
        onSave: {}
    )
}
