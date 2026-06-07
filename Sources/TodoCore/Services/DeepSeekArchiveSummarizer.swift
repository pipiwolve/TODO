import Foundation

public protocol ProjectArchiveSummarizingService: Sendable {
    func summarize(context: ProjectArchiveContext, apiKey: String) async throws -> ProjectArchiveSummary
}

public final class DeepSeekArchiveSummarizer: ProjectArchiveSummarizingService {
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

    public func summarize(context: ProjectArchiveContext, apiKey: String) async throws -> ProjectArchiveSummary {
        let request = try makeRequest(context: context, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw Error.apiError(message)
        }
        return try Self.parseResponseEnvelope(data, projectName: context.projectName, generatedAt: Date())
    }

    public func makeRequest(context: ProjectArchiveContext, apiKey: String) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Error.emptyAPIKey }

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(context: context))
        return request
    }

    public static func parseResponseEnvelope(_ data: Data, projectName: String, generatedAt: Date) throws -> ProjectArchiveSummary {
        let envelope = try JSONDecoder().decode(ArchiveChatEnvelope.self, from: data)
        guard let content = envelope.choices.first?.message.content else {
            throw Error.invalidResponse
        }
        return try parseSummary(content, projectName: projectName, generatedAt: generatedAt)
    }

    private static func parseSummary(_ json: String, projectName: String, generatedAt: Date) throws -> ProjectArchiveSummary {
        guard let data = json.data(using: .utf8) else {
            throw Error.invalidResponse
        }
        do {
            let payload = try JSONDecoder().decode(ProjectArchiveSummaryPayload.self, from: data)
            guard !payload.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw Error.invalidResponse
            }
            return ProjectArchiveSummary(
                projectName: projectName,
                summary: payload.summary,
                outcomes: payload.outcomes,
                risks: payload.risks,
                nextSteps: payload.nextSteps,
                generatedAt: generatedAt
            )
        } catch let error as Error {
            throw error
        } catch {
            throw Error.invalidResponse
        }
    }

    private func requestBody(context: ProjectArchiveContext) throws -> [String: Any] {
        [
            "model": model,
            "messages": [
                [
                    "role": "system",
                    "content": ArchiveSummaryPrompt.system
                ],
                [
                    "role": "user",
                    "content": try ArchiveSummaryPrompt.user(context: context)
                ]
            ],
            "response_format": [
                "type": "json_object"
            ],
            "temperature": 0.2
        ]
    }
}

private struct ArchiveChatEnvelope: Decodable {
    var choices: [ArchiveChoice]
}

private struct ArchiveChoice: Decodable {
    var message: ArchiveMessage
}

private struct ArchiveMessage: Decodable {
    var content: String
}
