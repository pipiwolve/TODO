import Foundation
import Testing
@testable import TodoCore

@Suite("Daily export context and markdown rendering")
struct DailyExportRendererTests {
    @Test("daily export groups tasks by project using active project order")
    func dailyExportGroupsTasksByProjectUsingActiveProjectOrder() {
        let date = DateOnly(year: 2026, month: 6, day: 8)
        let context = DailyExportRenderer.context(
            date: date,
            tasks: [
                task("Send invoice", project: "Client Work", completed: false, priority: .medium, dueTime: nil),
                task("Ship report", project: "Client Work", completed: true, priority: .high, dueTime: "09:00"),
                task("Buy notebook", project: "个人工作", completed: false, priority: .low, dueTime: "18:30"),
                task("Triage inbox", project: nil, completed: false, priority: .medium, dueTime: nil),
                task("Unknown work", project: "Z Project", completed: true, priority: .medium, dueTime: nil)
            ],
            projects: [
                project("个人工作"),
                project("Client Work"),
                project("Inbox")
            ]
        )

        #expect(context.date == date)
        #expect(context.projects.map(\.projectName) == ["个人工作", "Client Work", "Inbox", "Z Project"])
        #expect(context.projects[1].totalTaskCount == 2)
        #expect(context.projects[1].completedTaskCount == 1)
        #expect(context.projects[1].incompleteTaskCount == 1)
        #expect(context.projects[1].completedTasks.map(\.title) == ["Ship report"])
        #expect(context.projects[1].incompleteTasks.map(\.title) == ["Send invoice"])
    }

    @Test("fallback summary is deterministic")
    func fallbackSummaryIsDeterministic() {
        let context = DailyExportRenderer.context(
            date: DateOnly(year: 2026, month: 6, day: 8),
            tasks: [
                task("Ship report", project: "Client Work", completed: true, priority: .high, dueTime: "09:00"),
                task("Send invoice", project: "Client Work", completed: false, priority: .medium, dueTime: nil),
                task("Plan sprint", project: "Todo App", completed: false, priority: .medium, dueTime: nil)
            ],
            projects: [project("Client Work"), project("Todo App")]
        )

        let summary = DailyExportRenderer.fallbackSummary(context: context)

        #expect(summary.bullets == [
            "Client Work: 1/2 完成，1 项待推进。",
            "Todo App: 0/1 完成，1 项待推进。"
        ])
    }

    @Test("markdown includes date summary projects readable statuses due times and priority")
    func markdownIncludesExpectedReportSections() {
        let context = DailyExportRenderer.context(
            date: DateOnly(year: 2026, month: 6, day: 8),
            tasks: [
                task("Ship report", project: "Client Work", completed: true, priority: .high, dueTime: "09:00"),
                task("Send invoice", project: "Client Work", completed: false, priority: .medium, dueTime: nil)
            ],
            projects: [project("Client Work")]
        )
        let summary = DailyExportSummary(bullets: ["Client Work: report shipped, invoice remains."])

        let markdown = DailyExportRenderer.markdown(context: context, summary: summary)

        #expect(markdown.contains("# 轻话日报 2026-06-08"))
        #expect(markdown.contains("## 总结"))
        #expect(markdown.contains("- Client Work: report shipped, invoice remains."))
        #expect(markdown.contains("## To-Do 明细"))
        #expect(markdown.contains("### Client Work"))
        #expect(markdown.contains("- 已完成 09:00 高优先级: Ship report"))
        #expect(markdown.contains("- 未完成 Send invoice"))
        #expect(!markdown.contains("[x]"))
        #expect(!markdown.contains("[ ]"))
    }

    @Test("markdown handles empty day")
    func markdownHandlesEmptyDay() {
        let context = DailyExportRenderer.context(
            date: DateOnly(year: 2026, month: 6, day: 8),
            tasks: [],
            projects: [project("个人工作")]
        )

        let markdown = DailyExportRenderer.markdown(
            context: context,
            summary: DailyExportRenderer.fallbackSummary(context: context)
        )

        #expect(markdown.contains("# 轻话日报 2026-06-08"))
        #expect(markdown.contains("- 今天暂无 To-Do。"))
        #expect(!markdown.contains("###"))
    }

    private func task(_ title: String, project: String?, completed: Bool, priority: TaskPriority, dueTime: String?) -> TodoTask {
        TodoTask(
            id: UUID(),
            title: title,
            date: DateOnly(year: 2026, month: 6, day: 8),
            isCompleted: completed,
            priority: priority,
            source: .manual,
            projectName: project,
            dueTime: dueTime,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func project(_ name: String) -> Project {
        Project(id: UUID(), name: name, colorHex: "#3B82F6", isActive: true)
    }
}
