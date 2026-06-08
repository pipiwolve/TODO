import Foundation
import Testing
@testable import TodoCore

@Suite("DeepSeek daily export summarizer request and response")
struct DeepSeekDailyExportSummarizerTests {
    @Test("summarizer builds daily export chat-completions request")
    func summarizerBuildsDailyExportRequest() throws {
        let summarizer = DeepSeekDailyExportSummarizer(model: "deepseek-v4-flash")
        let context = dailyContext()

        let request = try summarizer.makeRequest(context: context, apiKey: "test-key")

        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "deepseek-v4-flash")
        #expect(object["response_format"] as? [String: String] == ["type": "json_object"])

        let messages = try #require(object["messages"] as? [[String: String]])
        let systemPrompt = try #require(messages.first?["content"])
        let userPrompt = try #require(messages.last?["content"])

        #expect(systemPrompt.contains("daily project summaries"))
        #expect(systemPrompt.contains("bullets"))
        #expect(userPrompt.contains("\"year\":2026"))
        #expect(userPrompt.contains("\"month\":6"))
        #expect(userPrompt.contains("\"day\":8"))
        #expect(userPrompt.contains("Client Work"))
        #expect(userPrompt.contains("Ship report"))
        #expect(userPrompt.contains("Send invoice"))
    }

    @Test("summarizer rejects empty API key")
    func summarizerRejectsEmptyAPIKey() throws {
        let summarizer = DeepSeekDailyExportSummarizer(model: "deepseek-v4-flash")

        #expect(throws: DeepSeekDailyExportSummarizer.Error.self) {
            try summarizer.makeRequest(context: dailyContext(), apiKey: "   ")
        }
    }

    @Test("summarizer parses chat-completions JSON content")
    func summarizerParsesChatCompletionsContent() throws {
        let payload = """
        {
          "choices": [
            {
              "message": {
                "content": "{\\"bullets\\":[\\"Client Work: shipped the report and still needs invoice follow-up.\\",\\"Todo App: review remains open.\\"]}"
              }
            }
          ]
        }
        """

        let summary = try DeepSeekDailyExportSummarizer.parseResponseEnvelope(Data(payload.utf8))

        #expect(summary.bullets == [
            "Client Work: shipped the report and still needs invoice follow-up.",
            "Todo App: review remains open."
        ])
    }

    @Test("summarizer rejects malformed daily export JSON")
    func summarizerRejectsMalformedDailyExportJSON() throws {
        let payload = """
        {
          "choices": [
            {
              "message": {
                "content": "{\\"summary\\":\\"Missing bullets\\"}"
              }
            }
          ]
        }
        """

        #expect(throws: DeepSeekDailyExportSummarizer.Error.self) {
            try DeepSeekDailyExportSummarizer.parseResponseEnvelope(Data(payload.utf8))
        }
    }

    private func dailyContext() -> DailyExportContext {
        DailyExportContext(
            date: DateOnly(year: 2026, month: 6, day: 8),
            projects: [
                DailyProjectExportContext(
                    projectName: "Client Work",
                    totalTaskCount: 2,
                    completedTaskCount: 1,
                    incompleteTaskCount: 1,
                    completedTasks: [
                        DailyExportTask(title: "Ship report", isCompleted: true, priority: .high, dueTime: "09:00")
                    ],
                    incompleteTasks: [
                        DailyExportTask(title: "Send invoice", isCompleted: false, priority: .medium, dueTime: nil)
                    ]
                )
            ]
        )
    }
}
