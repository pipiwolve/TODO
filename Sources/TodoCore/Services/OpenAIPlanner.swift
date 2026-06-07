import Foundation

public protocol TodoPlanningService: Sendable {
    func plan(input: String, date: DateOnly, apiKey: String) async throws -> PlanningResult
}

public final class OpenAIPlanner: TodoPlanningService {
    public enum Error: Swift.Error, Equatable {
        case emptyInput
        case emptyAPIKey
        case invalidResponse
        case apiError(String)
    }

    private let session: URLSession
    private let model: String

    public init(session: URLSession = .shared, model: String = "gpt-4.1-mini") {
        self.session = session
        self.model = model
    }

    public func plan(input: String, date: DateOnly, apiKey: String) async throws -> PlanningResult {
        let cleanInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanInput.isEmpty else { throw Error.emptyInput }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Error.emptyAPIKey }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(input: cleanInput, date: date))

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw Error.apiError(message)
        }

        return try parseResponseEnvelope(data)
    }

    private func requestBody(input: String, date: DateOnly) -> [String: Any] {
        [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": [
                        [
                            "type": "input_text",
                            "text": """
                            You organize a local macOS sticky-note todo app. Convert the user's natural language into concise daily tasks. Keep titles short. Assign project names when obvious. Use today's date \(date.isoString) when no date is specified. Return only schema-valid JSON.
                            """
                        ]
                    ]
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": input
                        ]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "todo_planning_result",
                    "strict": true,
                    "schema": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["tasks", "timelineSummary"],
                        "properties": [
                            "tasks": [
                                "type": "array",
                                "minItems": 1,
                                "items": [
                                    "type": "object",
                                    "additionalProperties": false,
                                    "required": ["title", "project", "priority", "date", "timeBlock"],
                                    "properties": [
                                        "title": ["type": "string"],
                                        "project": ["type": ["string", "null"]],
                                        "priority": ["type": "string", "enum": ["low", "medium", "high"]],
                                        "date": ["type": ["string", "null"]],
                                        "timeBlock": ["type": ["string", "null"]]
                                    ]
                                ]
                            ],
                            "timelineSummary": ["type": "string"]
                        ]
                    ]
                ]
            ]
        ]
    }

    private func parseResponseEnvelope(_ data: Data) throws -> PlanningResult {
        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        if let directText = envelope.outputText {
            return try PlanningParser.parse(directText)
        }

        for item in envelope.output ?? [] {
            for content in item.content ?? [] {
                if let text = content.text {
                    return try PlanningParser.parse(text)
                }
            }
        }

        throw Error.invalidResponse
    }
}

private struct ResponseEnvelope: Decodable {
    var outputText: String?
    var output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct OutputItem: Decodable {
    var content: [ContentItem]?
}

private struct ContentItem: Decodable {
    var text: String?
}
