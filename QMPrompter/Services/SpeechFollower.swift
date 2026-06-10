import AVFoundation
import Speech
import SwiftUI

enum SpeechFollowerState: Equatable {
    case idle
    case listening
    case denied
    case unavailable
    case failed(String)
}

@MainActor
final class SpeechFollower: ObservableObject {
    @Published private(set) var state: SpeechFollowerState = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var progress: Double = 0

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var startTask: Task<Void, Never>?
    private var scriptIndex = SpeechScriptIndex(content: "")
    private var inputTapInstalled = false
    private var recognitionSessionID = UUID()

    var isListening: Bool {
        state == .listening
    }

    var statusText: String {
        switch state {
        case .idle:
            "语音跟随"
        case .listening:
            transcript.isEmpty ? "正在听" : "跟随\(Int(progress * 100))%"
        case .denied:
            "语音权限未开启"
        case .unavailable:
            "语音识别不可用"
        case .failed(let message):
            message
        }
    }

    func toggle(content: String, initialProgress: Double = 0) {
        isListening ? stop() : start(content: content, initialProgress: initialProgress)
    }

    func start(content: String, initialProgress: Double = 0) {
        stop()
        startTask = Task { [weak self] in
            await self?.startListening(content: content, initialProgress: initialProgress)
        }
    }

    func stop() {
        recognitionSessionID = UUID()
        startTask?.cancel()
        startTask = nil

        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        if state == .listening {
            state = .idle
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
        stop()
        state = .idle
    }

    private func startListening(content: String, initialProgress: Double) async {
        state = .idle
        transcript = ""
        progress = min(1, max(0, initialProgress))
        scriptIndex = SpeechScriptIndex(content: content, initialProgress: progress)

        guard await requestSpeechAuthorization() else {
            state = .denied
            return
        }
        guard !Task.isCancelled else { return }

        guard await requestMicrophonePermission() else {
            state = .denied
            return
        }
        guard !Task.isCancelled else { return }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .unavailable
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = Self.contextualPhrases(from: content)
        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        if #available(iOS 16.0, *) {
            request.addsPunctuation = false
        }
        recognitionRequest = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            if inputTapInstalled {
                inputNode.removeTap(onBus: 0)
                inputTapInstalled = false
            }
            inputNode.installTap(onBus: 0, bufferSize: 512, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            inputTapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            state = .failed("麦克风启动失败")
            stop()
            return
        }

        state = .listening
        let sessionID = UUID()
        recognitionSessionID = sessionID
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognition(result: result, error: error, sessionID: sessionID)
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?, sessionID: UUID) {
        guard sessionID == recognitionSessionID else { return }

        if let result {
            transcript = result.bestTranscription.formattedString
            progress = scriptIndex.progress(for: transcript)
        }

        if error != nil, state == .listening {
            state = .failed("语音识别中断")
            stop()
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func contextualPhrases(from content: String) -> [String] {
        let separators = CharacterSet(charactersIn: "\n，。！？；,.!?;")
        var phrases: [String] = []

        for component in content.components(separatedBy: separators) {
            let phrase = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard phrase.count >= 2 else { continue }

            phrases.append(phrase)
            if phrases.count >= 80 {
                break
            }
        }

        return phrases
    }
}

private struct SpeechScriptIndex {
    let normalizedContent: String
    private var committedOffset: Int

    init(content: String, initialProgress: Double = 0) {
        normalizedContent = Self.normalize(content)
        committedOffset = min(
            normalizedContent.count,
            max(0, Int((Double(normalizedContent.count) * initialProgress).rounded(.down)))
        )
    }

    mutating func progress(for transcript: String) -> Double {
        let spoken = Self.normalize(transcript)
        guard !spoken.isEmpty, !normalizedContent.isEmpty else {
            return progress(atOffset: committedOffset)
        }

        if let matchOffset = bestMatchEndOffset(for: spoken) {
            committedOffset = max(
                committedOffset,
                boundedMatchOffset(matchOffset, spokenCount: spoken.count)
            )
        } else if committedOffset == 0 {
            committedOffset = max(committedOffset, commonPrefixCount(spoken))
        }

        return progress(atOffset: committedOffset)
    }

    private func bestMatchEndOffset(for spoken: String) -> Int? {
        var best: (endOffset: Int, score: Int)?

        for fragment in candidateFragments(for: spoken) {
            for range in ranges(of: fragment, in: searchRange(fragmentLength: fragment.count)) {
                let startOffset = normalizedContent.distance(from: normalizedContent.startIndex, to: range.lowerBound)
                let endOffset = normalizedContent.distance(from: normalizedContent.startIndex, to: range.upperBound)
                guard isPlausibleMatch(startOffset: startOffset, endOffset: endOffset, fragmentLength: fragment.count) else {
                    continue
                }

                let score = matchScore(startOffset: startOffset, endOffset: endOffset, fragmentLength: fragment.count)
                if best == nil || score > best!.score {
                    best = (endOffset, score)
                }
            }
        }

        return best?.endOffset
    }

    private func candidateFragments(for spoken: String) -> [String] {
        var fragments: [String] = []

        func append(_ fragment: String) {
            guard fragment.count >= 2, !fragments.contains(fragment) else { return }
            fragments.append(fragment)
        }

        if spoken.count <= 96 {
            append(spoken)
        }

        let maximumSuffixLength = min(48, spoken.count)
        if maximumSuffixLength >= 4 {
            for length in stride(from: maximumSuffixLength, through: 4, by: -4) {
                append(String(spoken.suffix(length)))
            }
        }

        if spoken.count >= 3 {
            append(String(spoken.suffix(3)))
        }

        return fragments
    }

    private func ranges(of fragment: String, in range: Range<String.Index>) -> [Range<String.Index>] {
        guard !range.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchRange = range

        while let range = normalizedContent.range(of: fragment, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<searchRange.upperBound
        }

        return ranges
    }

    private func searchRange(fragmentLength: Int) -> Range<String.Index> {
        guard !normalizedContent.isEmpty else {
            return normalizedContent.startIndex..<normalizedContent.startIndex
        }

        if committedOffset == 0 {
            let upperOffset = min(
                normalizedContent.count,
                max(48, fragmentLength * 4)
            )
            return normalizedContent.startIndex..<index(atOffset: upperOffset)
        }

        let backwardTolerance = max(18, fragmentLength * 2)
        let forwardTolerance = fragmentLength < 8 ? max(48, fragmentLength * 6) : max(120, fragmentLength * 10)
        let lowerOffset = max(0, committedOffset - backwardTolerance)
        let upperOffset = min(normalizedContent.count, committedOffset + forwardTolerance)

        return index(atOffset: lowerOffset)..<index(atOffset: upperOffset)
    }

    private func index(atOffset offset: Int) -> String.Index {
        normalizedContent.index(
            normalizedContent.startIndex,
            offsetBy: min(max(0, offset), normalizedContent.count)
        )
    }

    private func isPlausibleMatch(startOffset: Int, endOffset: Int, fragmentLength: Int) -> Bool {
        if committedOffset == 0 {
            guard fragmentLength >= 6 else {
                return startOffset <= 8
            }

            let earlyWindow = max(12, min(40, fragmentLength * 2))
            return startOffset <= earlyWindow
        }

        let backwardTolerance = max(12, fragmentLength * 2)
        if endOffset + backwardTolerance < committedOffset {
            return false
        }

        let forwardTolerance = fragmentLength < 8 ? max(22, fragmentLength * 4) : max(56, fragmentLength * 8)
        if startOffset > committedOffset + forwardTolerance {
            return false
        }

        return true
    }

    private func matchScore(startOffset: Int, endOffset: Int, fragmentLength: Int) -> Int {
        let anchorDistance = abs(startOffset - committedOffset)
        let backwardPenalty = max(0, committedOffset - endOffset)
        let initialPenalty = committedOffset == 0 ? startOffset * 20 : 0

        return fragmentLength * 1_000
            - anchorDistance * 5
            - backwardPenalty * 8
            - initialPenalty
    }

    private func boundedMatchOffset(_ matchOffset: Int, spokenCount: Int) -> Int {
        guard matchOffset > committedOffset else { return matchOffset }
        let maximumAdvance = max(18, min(140, spokenCount * 2 + 10))
        return min(matchOffset, committedOffset + maximumAdvance)
    }

    private func progress(atOffset offset: Int) -> Double {
        return min(1, max(0, Double(offset) / Double(normalizedContent.count)))
    }

    private func commonPrefixCount(_ spoken: String) -> Int {
        zip(normalizedContent, spoken).prefix { $0 == $1 }.count
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
            .map(String.init)
            .joined()
    }
}
