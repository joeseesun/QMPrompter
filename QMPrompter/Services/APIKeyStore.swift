import Foundation
import Security

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case deepSeek
    case openAICompatible
    case anthropicCompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deepSeek: "DeepSeek"
        case .openAICompatible: "OpenAI 兼容"
        case .anthropicCompatible: "Claude 兼容"
        }
    }

    var subtitle: String {
        switch self {
        case .deepSeek:
            "默认生成口播文稿，适合直接开始。"
        case .openAICompatible:
            "适合 OpenAI 协议的中转或自定义模型。"
        case .anthropicCompatible:
            "适合 Anthropic 协议的 Claude 或第三方中转。"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepSeek: "https://api.deepseek.com"
        case .openAICompatible: "https://api.openai.com/v1"
        case .anthropicCompatible: "https://api.anthropic.com"
        }
    }

    var defaultModel: String {
        switch self {
        case .deepSeek: "deepseek-v4-flash"
        case .openAICompatible: "gpt-4o-mini"
        case .anthropicCompatible: "claude-sonnet-4-20250514"
        }
    }

    var modelOptions: [AIModelOption] {
        switch self {
        case .deepSeek:
            [
                AIModelOption("deepseek-v4-flash", title: "DeepSeek V4 Flash", detail: "当前默认"),
                AIModelOption("deepseek-chat", title: "DeepSeek Chat"),
                AIModelOption("deepseek-reasoner", title: "DeepSeek Reasoner")
            ]
        case .openAICompatible:
            [
                AIModelOption("gpt-4o-mini", title: "GPT-4o mini", detail: "OpenAI 官方"),
                AIModelOption("gpt-4o", title: "GPT-4o", detail: "OpenAI 官方"),
                AIModelOption("o3-mini", title: "o3 mini", detail: "OpenAI 官方"),
                AIModelOption("anthropic/claude-sonnet-4", title: "Claude Sonnet 4", detail: "OpenRouter"),
                AIModelOption("claude-sonnet-4-20250514", title: "Claude Sonnet 4", detail: "兼容中转"),
                AIModelOption("deepseek-chat", title: "DeepSeek Chat"),
                AIModelOption("deepseek-reasoner", title: "DeepSeek Reasoner"),
                AIModelOption("qwen-max", title: "Qwen Max")
            ]
        case .anthropicCompatible:
            [
                AIModelOption("claude-sonnet-4-20250514", title: "Claude Sonnet 4", detail: "推荐"),
                AIModelOption("claude-opus-4-20250514", title: "Claude Opus 4"),
                AIModelOption("claude-3-5-haiku-latest", title: "Claude Haiku")
            ]
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .deepSeek, .openAICompatible: "sk-..."
        case .anthropicCompatible: "sk-ant-... 或第三方 token"
        }
    }
}

struct AIModelOption: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String

    init(_ id: String, title: String? = nil, detail: String = "") {
        self.id = id
        self.title = title ?? id
        self.detail = detail
    }
}

struct AIConnectionConfiguration {
    let provider: AIProvider
    let apiKey: String
    let baseURL: String
    let model: String
}

@MainActor
final class APIKeyStore: ObservableObject {
    @Published var provider: AIProvider
    @Published var apiKey: String
    @Published var baseURL: String
    @Published var model: String

    private let account = "ai-api-key"
    private let legacyDeepSeekAccount = "deepseek-api-key"
    private let service = "com.qiaomu.Prompter"
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let provider = "ai.provider"
        static let baseURL = "ai.baseURL"
        static let model = "ai.model"
    }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var configuration: AIConnectionConfiguration {
        AIConnectionConfiguration(
            provider: provider,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: resolvedBaseURL,
            model: resolvedModel
        )
    }

    init() {
        let savedProvider = defaults.string(forKey: DefaultsKey.provider)
            .flatMap(AIProvider.init(rawValue:)) ?? .deepSeek
        provider = savedProvider
        apiKey = Self.read(account: account, service: service) ??
            Self.read(account: legacyDeepSeekAccount, service: service) ?? ""
        baseURL = defaults.string(forKey: DefaultsKey.baseURL) ?? savedProvider.defaultBaseURL
        model = defaults.string(forKey: DefaultsKey.model) ?? savedProvider.defaultModel
    }

    func save() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextBaseURL = resolvedBaseURL
        let nextModel = resolvedModel

        apiKey = key
        baseURL = nextBaseURL
        model = nextModel

        defaults.set(provider.rawValue, forKey: DefaultsKey.provider)
        defaults.set(nextBaseURL, forKey: DefaultsKey.baseURL)
        defaults.set(nextModel, forKey: DefaultsKey.model)

        if key.isEmpty {
            Self.delete(account: account, service: service)
        } else {
            Self.save(key, account: account, service: service)
        }
        Self.delete(account: legacyDeepSeekAccount, service: service)
    }

    private var resolvedBaseURL: String {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? provider.defaultBaseURL : value
    }

    private var resolvedModel: String {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? provider.defaultModel : value
    }

    private static func save(_ value: String, account: String, service: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account: account, service: service)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private static func read(account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]

        SecItemDelete(query as CFDictionary)
    }
}
