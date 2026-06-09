import Foundation
import UIKit

struct PromptLine: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let characterCount: Int
}

enum PromptFormatter {
    static func lines(from content: String, targetCharactersPerLine: Int = 18) -> [PromptLine] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var result: [PromptLine] = []
        for paragraph in normalized.components(separatedBy: "\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                result.append(PromptLine(text: "", characterCount: 0))
                continue
            }
            result.append(contentsOf: split(trimmed, target: targetCharactersPerLine))
        }
        return result.filter { !$0.text.isEmpty || result.count > 1 }
    }

    private static func split(_ text: String, target: Int) -> [PromptLine] {
        var lines: [PromptLine] = []
        var current = ""
        let semanticMinimumLength = max(8, target)
        let hardMaximumLength = max(semanticMinimumLength * 2, target + 10)

        for character in text {
            current.append(character)
            let shouldBreakAtStrongPunctuation = "。！？；.!?;".contains(character) && current.count >= 4
            let shouldBreakAtSoftPunctuation = "，、,：:".contains(character) && current.count >= semanticMinimumLength
            let shouldBreakLongPhrase = current.count >= hardMaximumLength

            if shouldBreakAtStrongPunctuation || shouldBreakAtSoftPunctuation || shouldBreakLongPhrase {
                append(current, to: &lines, fallbackCount: target)
                current = ""
            }
        }

        append(current, to: &lines, fallbackCount: target)
        return lines
    }

    private static func append(_ text: String, to lines: inout [PromptLine], fallbackCount: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !containsSpeakableCharacter(trimmed), let previous = lines.popLast() {
            let merged = previous.text + trimmed
            lines.append(PromptLine(text: merged, characterCount: max(previous.characterCount, merged.count)))
            return
        }
        lines.append(PromptLine(text: trimmed, characterCount: max(1, trimmed.count, fallbackCount / 2)))
    }

    private static func containsSpeakableCharacter(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }
}

@MainActor
enum Haptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumImpact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
