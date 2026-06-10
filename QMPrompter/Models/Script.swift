import Foundation
import SwiftUI

struct Script: Identifiable, Codable, Equatable {
    static let defaultFontSize: Double = 38

    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var fontSize: Double
    var scrollSpeed: Double
    var textColorPreset: TextColorPreset
    var overlayOpacity: Double

    init(
        id: UUID = UUID(),
        title: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        fontSize: Double = Self.defaultFontSize,
        scrollSpeed: Double = 80,
        textColorPreset: TextColorPreset = .white,
        overlayOpacity: Double = 0.48
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fontSize = fontSize
        self.scrollSpeed = scrollSpeed
        self.textColorPreset = textColorPreset
        self.overlayOpacity = overlayOpacity
    }

    var preview: String {
        content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TextColorPreset: String, CaseIterable, Codable, Identifiable {
    case white
    case silver
    case graphite

    var id: String { rawValue }

    static var editorChoices: [TextColorPreset] {
        [.white, .graphite]
    }

    var name: String {
        switch self {
        case .white: "白"
        case .silver: "银灰"
        case .graphite: "深灰"
        }
    }

    var color: Color {
        switch self {
        case .white: .white
        case .silver: Color(red: 0.78, green: 0.80, blue: 0.82)
        case .graphite: Color(red: 0.50, green: 0.52, blue: 0.55)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case Self.white.rawValue:
            self = .white
        case Self.silver.rawValue, "yellow":
            self = .silver
        case Self.graphite.rawValue, "green":
            self = .graphite
        default:
            self = .white
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
