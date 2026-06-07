import Foundation
import Testing
@testable import TodoCore

@Suite("DeepSeek planner request and response")
struct DeepSeekPlannerTests {
    @Test("planner builds V4 Flash chat-completions request")
    func plannerBuildsV4FlashRequest() throws {
        let planner = DeepSeekPlanner(model: "deepseek-v4-flash")
        let request = try planner.makeRequest(
            input: "Plan my day",
            date: DateOnly(year: 2026, month: 6, day: 7),
            apiKey: "test-key"
        )

        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["model"] as? String == "deepseek-v4-flash")
        #expect(object["response_format"] as? [String: String] == ["type": "json_object"])
    }

    @Test("planner system prompt describes todo and gantt output contract")
    func plannerSystemPromptDescribesContract() throws {
        let planner = DeepSeekPlanner(model: "deepseek-v4-flash")
        let request = try planner.makeRequest(
            input: "Plan my day",
            date: DateOnly(year: 2026, month: 6, day: 7),
            apiKey: "test-key"
        )

        let body = try #require(request.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: String]])
        let systemPrompt = try #require(messages.first?["content"])

        #expect(systemPrompt.contains("daily To Do"))
        #expect(systemPrompt.contains("project"))
        #expect(systemPrompt.contains("Gantt"))
        #expect(systemPrompt.contains("tasks"))
        #expect(systemPrompt.contains("timelineSummary"))
        #expect(systemPrompt.contains("YYYY-MM-DD"))
        #expect(systemPrompt.contains("HH:mm"))
        #expect(systemPrompt.contains("low, medium, and high"))
        #expect(systemPrompt.contains("Do not output emergency"))
    }

    @Test("planner parses chat-completions JSON content")
    func plannerParsesChatCompletionsContent() throws {
        let payload = """
        {
          "choices": [
            {
              "message": {
                "content": "{\\"tasks\\":[{\\"title\\":\\"Polish UI\\",\\"project\\":\\"Todo App\\",\\"priority\\":\\"high\\",\\"date\\":\\"2026-06-07\\",\\"timeBlock\\":\\"morning\\"}],\\"timelineSummary\\":\\"Todo App UI polish today.\\"}"
              }
            }
          ]
        }
        """

        let result = try DeepSeekPlanner.parseResponseEnvelope(Data(payload.utf8))

        #expect(result.tasks.first?.title == "Polish UI")
        #expect(result.timelineSummary == "Todo App UI polish today.")
    }
}
