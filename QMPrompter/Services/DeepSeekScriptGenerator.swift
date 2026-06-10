import Foundation

struct AIScriptGenerator {
    enum GenerationError: LocalizedError {
        case missingAPIKey(String)
        case invalidBaseURL
        case invalidResponse(String)
        case emptyContent(String)
        case server(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey(let provider):
                "请先填写 \(provider) API Key。"
            case .invalidBaseURL:
                "Base URL 格式不正确。"
            case .invalidResponse(let provider):
                "\(provider) 返回格式异常。"
            case .emptyContent(let provider):
                "\(provider) 没有生成可用正文。"
            case .server(let message):
                message
            }
        }
    }

    private let configuration: AIConnectionConfiguration

    init(configuration: AIConnectionConfiguration) {
        self.configuration = configuration
    }

    func generateScript(for prompt: String) async throws -> String {
        guard !configuration.apiKey.isEmpty else {
            throw GenerationError.missingAPIKey(configuration.provider.title)
        }

        switch configuration.provider {
        case .deepSeek, .openAICompatible:
            return try await generateWithChatCompletions(prompt)
        case .anthropicCompatible:
            return try await generateWithAnthropicMessages(prompt)
        }
    }

    private func generateWithChatCompletions(_ prompt: String) async throws -> String {
        let endpoint = try endpointURL(for: .chatCompletions)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        let body = ChatCompletionsRequest(
            model: configuration.model,
            messages: [
                .init(role: "system", content: Self.systemPrompt),
                .init(role: "user", content: userPrompt(from: prompt))
            ],
            thinking: configuration.provider == .deepSeek ? .init(type: "disabled") : nil,
            maxTokens: 2800,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw GenerationError.invalidResponse(configuration.provider.title)
        }

        return try clean(content)
    }

    private func generateWithAnthropicMessages(_ prompt: String) async throws -> String {
        let endpoint = try endpointURL(for: .anthropicMessages)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 90

        let body = AnthropicMessagesRequest(
            model: configuration.model,
            system: Self.systemPrompt,
            messages: [
                .init(role: "user", content: userPrompt(from: prompt))
            ],
            maxTokens: 2800,
            stream: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        let content = decoded.content
            .compactMap(\.text)
            .joined(separator: "\n")

        return try clean(content)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GenerationError.invalidResponse(configuration.provider.title)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data).error?.message) ??
                "\(configuration.provider.title) 请求失败：HTTP \(httpResponse.statusCode)。"
            throw GenerationError.server(message)
        }
    }

    private func clean(_ content: String) throws -> String {
        let cleaned = Self.cleanGeneratedScript(content)
        guard !cleaned.isEmpty else {
            throw GenerationError.emptyContent(configuration.provider.title)
        }
        return cleaned
    }

    private func endpointURL(for endpoint: AIEndpoint) throws -> URL {
        let rawBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseURL = rawBaseURL.contains("://") ? rawBaseURL : "https://\(rawBaseURL)"

        guard var url = URL(string: normalizedBaseURL),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil
        else {
            throw GenerationError.invalidBaseURL
        }

        let path = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        switch endpoint {
        case .chatCompletions:
            guard !path.hasSuffix("chat/completions") else { return url }
            url.appendPathComponent("chat")
            url.appendPathComponent("completions")
            return url
        case .anthropicMessages:
            guard !path.hasSuffix("messages") else { return url }
            if !path.hasSuffix("v1") {
                url.appendPathComponent("v1")
            }
            url.appendPathComponent("messages")
            return url
        }
    }

    private func userPrompt(from prompt: String) -> String {
        """
        用户的生成需求：
        \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))

        请输出一篇可直接放进提词器朗读的中文口播文稿。
        """
    }

    private static let systemPrompt = """
    你是向阳乔木的提词器文稿作者，负责把用户的简单想法生成适合直接朗读的中文口播稿。

    写作方法参考向阳乔木的读书口播脚本工作流：
    从听众真实困境或强认知锚点开始；
    如果用户输入的是书名、作者或读书视频主题，先说明作者或这本书为什么值得听，再提炼三到五个真正改变认知的观点；
    如果不是书籍主题，也用同样的结构：一个清晰问题、三到五个观点、具体生活场景、自然收束；
    每个观点都要用一句话解释，再接一个普通人能立刻看见的场景；
    语言要像真人说话，短段落，一句只承载一个意思；
    结尾自然，不要强行销售。

    输出规则：
    只输出口播正文；
    不要 Markdown；
    不要代码块；
    不要标题；
    不要提纲；
    不要列表符号；
    不要加粗标记；
    不要小标题；
    不要“开场、观点、结尾”这类段落标签；
    不要“第一点、第二点、首先、其次、最后”；
    不要镜头提示、音乐提示、字幕提示或时长说明；
    不要解释你的写作过程；
    文本要适合提词器滚动显示，段落短，换行自然。

    避免这些词和句式：震惊、绝了、太牛了、赋能、落地、深度融合、内卷、这个时代、年轻人、精准打击、你知道吗、今天我要告诉你、重点来了、接下来告诉你、划重点。
    """

    private static func cleanGeneratedScript(_ content: String) -> String {
        var result = content
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```markdown", with: "")
            .replacingOccurrences(of: "```", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")

        let lines = result
            .components(separatedBy: .newlines)
            .compactMap { rawLine -> String? in
                var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return "" }
                guard !shouldDropGeneratedLine(line) else { return nil }
                line = stripGeneratedLinePrefix(line)
                line = stripLeadingStageDirection(line)
                guard !shouldDropGeneratedLine(line) else { return nil }
                let strippedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return strippedLine.isEmpty ? nil : strippedLine
            }

        result = lines.joined(separator: "\n")

        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldDropGeneratedLine(_ line: String) -> Bool {
        if line.hasPrefix("#") || line.hasPrefix(">") || line.contains("预估时长") {
            return true
        }

        let normalized = line
            .replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if [
            "口播正文", "口播正文:", "口播稿", "口播稿:", "正文", "正文:",
            "标题", "标题:", "小标题", "小标题:", "提纲", "提纲:",
            "开场", "开场:", "开场白", "开场白:", "结尾", "结尾:",
            "收束", "收束:", "脚本", "脚本:", "文稿", "文稿:"
        ].contains(normalized) {
            return true
        }

        let stageDirectionPattern = #"^[【\(\（\[]?\s*(镜头|画面|字幕|音乐|音效|BGM|提示|时长|旁白)[^。！？]*[】\)\）\]：:]"#
        if line.range(of: stageDirectionPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        let metaResponsePattern = #"^(以下是|下面是|好的[，,]|可以[，,]).*(口播|文稿|脚本|提词器)"#
        return line.range(of: metaResponsePattern, options: .regularExpression) != nil
    }

    private static func stripGeneratedLinePrefix(_ line: String) -> String {
        var result = line
        let prefixPatterns = [
            #"^#{1,6}\s*"#,
            #"^[-*•·]\s+"#,
            #"^\d+[\.\)、、]\s*"#,
            #"^（?[一二三四五六七八九十]+[、\.．）)]\s*"#,
            #"^第[一二三四五六七八九十0-9]+[点部分][：:、，\s]*"#,
            #"^(口播正文|口播稿|正文|开场白|开场|观点|转折|收束|结尾|脚本|文稿|提词器文稿)[：:\s]+"#,
            #"^(首先|其次|然后|接着|再说|最后|总之)[，,、：:\s]+"#
        ]

        var didStrip = true
        while didStrip {
            didStrip = false
            for pattern in prefixPatterns {
                if let range = result.range(of: pattern, options: .regularExpression) {
                    result.removeSubrange(range)
                    result = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    didStrip = true
                }
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingStageDirection(_ line: String) -> String {
        var result = line
        let stagePatterns = [
            #"^[【\(\（\[]\s*(停顿|微笑|看镜头|转场|镜头|画面|字幕|音乐|音效|BGM|提示)[^】\)\）\]]*[】\)\）\]]\s*"#,
            #"^（\s*[0-9]+秒\s*）\s*"#
        ]

        for pattern in stagePatterns {
            if let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                result.removeSubrange(range)
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum AIEndpoint {
    case chatCompletions
    case anthropicMessages
}

private struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [AIMessage]
    let thinking: AIThinking?
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case thinking
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct AIThinking: Encodable {
    let type: String
}

private struct AIMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionsResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: AIMessage
    }
}

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let system: String
    let messages: [AIMessage]
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case system
        case messages
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [Content]

    struct Content: Decodable {
        let type: String?
        let text: String?
    }
}

private struct APIErrorResponse: Decodable {
    let error: APIError?

    struct APIError: Decodable {
        let message: String
    }
}
