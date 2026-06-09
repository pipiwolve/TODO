import Foundation

public protocol DailyExportSummarizingService: Sendable {
    func summarize(context: DailyExportContext, apiKey: String) async throws -> DailyExportSummary
}

public final class DeepSeekDailyExportSummarizer: DailyExportSummarizingService {
    public enum Error: Swift.Error, Equatable {
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

    public func summarize(context: DailyExportContext, apiKey: String) async throws -> DailyExportSummary {
        let request = try makeRequest(context: context, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw Error.apiError(message)
        }
        return try Self.parseResponseEnvelope(data)
    }

    public func makeRequest(context: DailyExportContext, apiKey: String) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Error.emptyAPIKey
        }

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(context: context))
        return request
    }

    public static func parseResponseEnvelope(_ data: Data) throws -> DailyExportSummary {
        let envelope = try JSONDecoder().decode(DailyExportChatEnvelope.self, from: data)
        guard let content = envelope.choices.first?.message.content else {
            throw Error.invalidResponse
        }
        return try parseSummary(content)
    }

    private static func parseSummary(_ json: String) throws -> DailyExportSummary {
        guard let data = json.data(using: .utf8) else {
            throw Error.invalidResponse
        }
        do {
            let payload = try JSONDecoder().decode(DailyExportSummaryPayload.self, from: data)
            let bullets = payload.bullets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !bullets.isEmpty else {
                throw Error.invalidResponse
            }
            return DailyExportSummary(bullets: bullets)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.invalidResponse
        }
    }

    private func requestBody(context: DailyExportContext) throws -> [String: Any] {
        [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": DailyExportSummaryPrompt.system
                ],
                [
                    "role": "user",
                    "content": try DailyExportSummaryPrompt.user(context: context)
                ]
            ],
            "response_format": [
                "type": "json_object"
            ],
            "temperature": 0.2
        ]
    }
}

private struct DailyExportChatEnvelope: Decodable {
    var choices: [DailyExportChoice]
}

private struct DailyExportChoice: Decodable {
    var message: DailyExportMessage
}

private struct DailyExportMessage: Decodable {
    var content: String
}
