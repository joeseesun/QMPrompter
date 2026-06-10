import Foundation

struct AIModelFetcher {
    enum FetchError: LocalizedError {
        case invalidBaseURL
        case missingAPIKey(String)
        case server(String)
        case noModels

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                "Base URL 格式不正确。"
            case .missingAPIKey(let provider):
                "请先填写 \(provider) API Key。"
            case .server(let message):
                message
            case .noModels:
                "没有从服务器获取到可用模型。"
            }
        }
    }

    private let configuration: AIConnectionConfiguration

    init(configuration: AIConnectionConfiguration) {
        self.configuration = configuration
    }

    func fetchModels() async throws -> [AIModelOption] {
        guard !configuration.apiKey.isEmpty else {
            throw FetchError.missingAPIKey(configuration.provider.title)
        }

        let endpoint = try modelsEndpointURL()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch configuration.provider {
        case .deepSeek, .openAICompatible:
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropicCompatible:
            request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.server("\(configuration.provider.title) 返回格式异常。")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(RemoteModelsErrorResponse.self, from: data).error?.message) ??
                "\(configuration.provider.title) 模型列表请求失败：HTTP \(httpResponse.statusCode)。"
            throw FetchError.server(message)
        }

        let models = try extractModels(from: data)
        guard !models.isEmpty else { throw FetchError.noModels }
        return models
    }

    private func modelsEndpointURL() throws -> URL {
        let rawBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseURL = rawBaseURL.contains("://") ? rawBaseURL : "https://\(rawBaseURL)"

        guard var url = URL(string: normalizedBaseURL),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil
        else {
            throw FetchError.invalidBaseURL
        }

        let path = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        guard !path.hasSuffix("models") else { return url }

        if configuration.provider == .anthropicCompatible,
           !path.hasSuffix("v1") {
            url.appendPathComponent("v1")
        }

        url.appendPathComponent("models")
        return url
    }

    private func extractModels(from data: Data) throws -> [AIModelOption] {
        let payload = try JSONSerialization.jsonObject(with: data)
        let rawItems = collectModelItems(from: payload)
        let options = rawItems.compactMap(makeModelOption)
        return deduplicated(options).sorted { lhs, rhs in
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private func collectModelItems(from payload: Any) -> [Any] {
        if let array = payload as? [Any] {
            return array
        }

        guard let dictionary = payload as? [String: Any] else {
            return []
        }

        let arrayKeys = ["data", "models", "items"]
        var result: [Any] = []

        for key in arrayKeys {
            if let array = dictionary[key] as? [Any] {
                result.append(contentsOf: array)
            }
        }

        if let resultDictionary = dictionary["result"] as? [String: Any] {
            result.append(contentsOf: collectModelItems(from: resultDictionary))
        }

        return result
    }

    private func makeModelOption(from item: Any) -> AIModelOption? {
        if let id = item as? String {
            let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty else { return nil }
            return AIModelOption(normalizedID, detail: "服务器")
        }

        guard let dictionary = item as? [String: Any] else {
            return nil
        }

        let id = stringValue(for: ["id", "model", "slug", "name"], in: dictionary)
        let title = stringValue(for: ["display_name", "displayName", "name", "id"], in: dictionary)
        guard let id else { return nil }

        return AIModelOption(
            id,
            title: title == id ? nil : title,
            detail: "服务器"
        )
    }

    private func stringValue(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func deduplicated(_ options: [AIModelOption]) -> [AIModelOption] {
        var seen = Set<String>()
        var result: [AIModelOption] = []

        for option in options {
            let key = option.id.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(option)
        }

        return result
    }
}

private struct RemoteModelsErrorResponse: Decodable {
    let error: APIError?

    struct APIError: Decodable {
        let message: String?
    }
}
