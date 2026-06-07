import Foundation

public final class DeepSeekPlanner: TodoPlanningService {
    public enum Error: Swift.Error, Equatable {
        case emptyInput
        case emptyAPIKey
        case invalidResponse
        case apiError(String)
    }

    private let session: URLSession
    private let model: String

    public init(session: URLSession = .shared, model: String = "deepseek-v4-flash") {
        self.session = session
        self.model = model
    }

    public func plan(input: String, date: DateOnly, apiKey: String) async throws -> PlanningResult {
        let request = try makeRequest(input: input, date: date, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw Error.apiError(message)
        }
        return try Self.parseResponseEnvelope(data)
    }

    public func makeRequest(input: String, date: DateOnly, apiKey: String) throws -> URLRequest {
        let cleanInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanInput.isEmpty else { throw Error.emptyInput }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Error.emptyAPIKey }

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(input: cleanInput, date: date))
        return request
    }

    public static func parseResponseEnvelope(_ data: Data) throws -> PlanningResult {
        let envelope = try JSONDecoder().decode(ChatEnvelope.self, from: data)
        guard let content = envelope.choices.first?.message.content else {
            throw Error.invalidResponse
        }
        return try PlanningParser.parse(content)
    }

    private func requestBody(input: String, date: DateOnly) -> [String: Any] {
        [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": PlanningPrompt.system(date: date)
                ],
                [
                    "role": "user",
                    "content": input
                ]
            ],
            "response_format": [
                "type": "json_object"
            ],
            "temperature": 0.2
        ]
    }
}

private struct ChatEnvelope: Decodable {
    var choices: [Choice]
}

private struct Choice: Decodable {
    var message: Message
}

private struct Message: Decodable {
    var content: String
}
