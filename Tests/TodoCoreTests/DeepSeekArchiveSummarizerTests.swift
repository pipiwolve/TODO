import Foundation
import Testing
@testable import TodoCore

@Suite("DeepSeek archive summarizer request and response")
struct DeepSeekArchiveSummarizerTests {
    @Test("summarizer builds archive chat-completions request")
    func summarizerBuildsArchiveRequest() throws {
        let summarizer = DeepSeekArchiveSummarizer(model: "deepseek-v4-flash")
        let context = archiveContext()

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

        #expect(systemPrompt.contains("archive summary"))
        #expect(systemPrompt.contains("summary"))
        #expect(systemPrompt.contains("outcomes"))
        #expect(systemPrompt.contains("risks"))
        #expect(systemPrompt.contains("nextSteps"))
        #expect(userPrompt.contains("Client Work"))
        #expect(userPrompt.contains("Ship report"))
        #expect(userPrompt.contains("Finished report"))
    }

    @Test("summarizer parses chat-completions JSON content")
    func summarizerParsesChatCompletionsContent() throws {
        let payload = """
        {
          "choices": [
            {
              "message": {
                "content": "{\\"summary\\":\\"Client Work shipped with a clean handoff.\\",\\"outcomes\\":[\\"Report shipped\\"],\\"risks\\":[\\"Follow-up unscheduled\\"],\\"nextSteps\\":[\\"Schedule handoff\\"]}"
              }
            }
          ]
        }
        """

        let summary = try DeepSeekArchiveSummarizer.parseResponseEnvelope(
            Data(payload.utf8),
            projectName: "Client Work",
            generatedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(summary.projectName == "Client Work")
        #expect(summary.summary == "Client Work shipped with a clean handoff.")
        #expect(summary.outcomes == ["Report shipped"])
        #expect(summary.risks == ["Follow-up unscheduled"])
        #expect(summary.nextSteps == ["Schedule handoff"])
        #expect(summary.generatedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("summarizer rejects malformed archive JSON")
    func summarizerRejectsMalformedArchiveJSON() throws {
        let payload = """
        {
          "choices": [
            {
              "message": {
                "content": "{\\"summary\\":\\"Missing arrays\\"}"
              }
            }
          ]
        }
        """

        #expect(throws: DeepSeekArchiveSummarizer.Error.self) {
            try DeepSeekArchiveSummarizer.parseResponseEnvelope(
                Data(payload.utf8),
                projectName: "Client Work",
                generatedAt: Date(timeIntervalSince1970: 100)
            )
        }
    }

    private func archiveContext() -> ProjectArchiveContext {
        ProjectArchiveContext(
            projectName: "Client Work",
            totalTaskCount: 2,
            completedTaskCount: 1,
            incompleteTaskCount: 1,
            startDate: DateOnly(year: 2026, month: 6, day: 7),
            endDate: DateOnly(year: 2026, month: 6, day: 8),
            completedTasks: [
                ProjectArchiveContext.Task(title: "Ship report", date: DateOnly(year: 2026, month: 6, day: 7), priority: .high, dueTime: "09:00")
            ],
            incompleteTasks: [
                ProjectArchiveContext.Task(title: "Send invoice", date: DateOnly(year: 2026, month: 6, day: 8), priority: .medium, dueTime: nil)
            ],
            dailyNotes: [
                ProjectArchiveContext.Note(date: DateOnly(year: 2026, month: 6, day: 7), blockers: "Waiting for approval", completedSummary: "Finished report", tomorrowPlan: "Invoice client")
            ]
        )
    }
}
