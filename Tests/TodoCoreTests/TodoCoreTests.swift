import Foundation
import Testing
@testable import TodoCore

@Suite("Todo core persistence and planning")
struct TodoCoreTests {
    @Test("manual tasks persist and can be deleted")
    func manualTasksPersistAndDelete() async throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        let task = try store.addTask(
            title: "Write MVP outline",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .high,
            source: .manual,
            projectName: "Todo App"
        )

        #expect(try store.tasks(on: DateOnly(year: 2026, month: 6, day: 7)).map(\.title) == ["Write MVP outline"])

        try store.deleteTask(id: task.id)

        #expect(try store.tasks(on: DateOnly(year: 2026, month: 6, day: 7)).isEmpty)
    }

    @Test("manual tasks can persist project priority and due time")
    func manualTasksPersistMetadata() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        _ = try store.addTask(
            title: "Prepare slides",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .high,
            source: .manual,
            projectName: "个人工作",
            dueTime: "15:30"
        )

        let task = try #require(store.tasks(on: DateOnly(year: 2026, month: 6, day: 7)).first)

        #expect(task.projectName == "个人工作")
        #expect(task.priority == .high)
        #expect(task.dueTime == "15:30")
    }

    @Test("project list includes default personal work project")
    func projectListIncludesDefaultPersonalWork() throws {
        let store = try TodoStore(path: temporaryDatabasePath())

        let projects = try store.projects()

        #expect(projects.contains { $0.name == "个人工作" })
    }

    @Test("projects can be created and archived without deleting history")
    func projectsCanBeCreatedAndArchived() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        let project = try store.addProject(name: "Client Work")
        _ = try store.addTask(
            title: "Ship report",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .high,
            source: .manual,
            projectName: project.name
        )

        #expect(try store.projects().contains { $0.name == "Client Work" })

        try store.archiveProject(name: "Client Work")

        #expect(try !store.projects().contains { $0.name == "Client Work" })
        #expect(try store.archivedProjects().contains { $0.name == "Client Work" })
        #expect(try store.tasks(on: DateOnly(year: 2026, month: 6, day: 7)).contains { $0.projectName == "Client Work" })
    }

    @Test("projects can be deleted with their tasks and archive summaries")
    func projectsCanBeDeletedWithTheirTasksAndArchiveSummaries() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        _ = try store.addProject(name: "Client Work")
        _ = try store.addTask(
            title: "Ship report",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .high,
            source: .manual,
            projectName: "Client Work"
        )
        _ = try store.addTask(
            title: "Keep unrelated work",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .medium,
            source: .manual,
            projectName: "Other Work"
        )
        try store.archiveProject(name: "Client Work")
        try store.saveProjectArchiveSummary(
            ProjectArchiveSummary(
                projectName: "Client Work",
                summary: "Finished client work.",
                outcomes: ["Report shipped"],
                risks: [],
                nextSteps: [],
                generatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        try store.deleteProject(name: "Client Work")

        #expect(try !store.projects().contains { $0.name == "Client Work" })
        #expect(try !store.archivedProjects().contains { $0.name == "Client Work" })
        #expect(try store.projectArchiveDetail(name: "Client Work") == nil)
        #expect(try store.tasks(on: DateOnly(year: 2026, month: 6, day: 7)).map(\.title) == ["Keep unrelated work"])
    }

    @Test("default projects cannot be deleted")
    func defaultProjectsCannotBeDeleted() throws {
        let store = try TodoStore(path: temporaryDatabasePath())

        #expect(throws: TodoStore.Error.self) {
            try store.deleteProject(name: "Inbox")
        }
        #expect(throws: TodoStore.Error.self) {
            try store.deleteProject(name: "个人工作")
        }
        #expect(try store.projects().contains { $0.name == "Inbox" })
        #expect(try store.projects().contains { $0.name == "个人工作" })
    }

    @Test("archive detail includes project tasks stats and daily notes")
    func archiveDetailIncludesProjectTasksStatsAndDailyNotes() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        _ = try store.addProject(name: "Client Work")
        let completed = try store.addTask(
            title: "Ship report",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .high,
            source: .manual,
            projectName: "Client Work",
            dueTime: "09:00"
        )
        _ = try store.addTask(
            title: "Send invoice",
            date: DateOnly(year: 2026, month: 6, day: 8),
            priority: .medium,
            source: .manual,
            projectName: "Client Work"
        )
        _ = try store.addTask(
            title: "Unrelated task",
            date: DateOnly(year: 2026, month: 6, day: 8),
            priority: .low,
            source: .manual,
            projectName: "Other Work"
        )
        try store.setTaskCompleted(id: completed.id, isCompleted: true)
        try store.saveDailyNote(
            DailyNote(
                date: DateOnly(year: 2026, month: 6, day: 7),
                blockers: "Waiting for approval",
                completedSummary: "Finished report",
                tomorrowPlan: "Invoice client"
            )
        )
        try store.archiveProject(name: "Client Work")

        let loadedDetail = try store.projectArchiveDetail(name: "Client Work")
        let detail = try #require(loadedDetail)

        #expect(detail.project.name == "Client Work")
        #expect(detail.totalTaskCount == 2)
        #expect(detail.completedTaskCount == 1)
        #expect(detail.incompleteTaskCount == 1)
        #expect(detail.startDate == DateOnly(year: 2026, month: 6, day: 7))
        #expect(detail.endDate == DateOnly(year: 2026, month: 6, day: 8))
        #expect(detail.completedTasks.map(\.title) == ["Ship report"])
        #expect(detail.incompleteTasks.map(\.title) == ["Send invoice"])
        #expect(detail.dailyNotes.map(\.completedSummary) == ["Finished report"])
    }

    @Test("archive summaries can be saved and replaced")
    func archiveSummariesCanBeSavedAndReplaced() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        _ = try store.addProject(name: "Client Work")
        _ = try store.addTask(
            title: "Ship report",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .high,
            source: .manual,
            projectName: "Client Work"
        )
        try store.archiveProject(name: "Client Work")

        let first = ProjectArchiveSummary(
            projectName: "Client Work",
            summary: "Finished the client report.",
            outcomes: ["Report shipped"],
            risks: ["Follow-up not scheduled"],
            nextSteps: ["Schedule handoff"],
            generatedAt: Date(timeIntervalSince1970: 100)
        )
        try store.saveProjectArchiveSummary(first)

        var loadedDetail = try store.projectArchiveDetail(name: "Client Work")
        var detail = try #require(loadedDetail)
        #expect(detail.summary?.summary == "Finished the client report.")
        #expect(detail.summary?.outcomes == ["Report shipped"])

        let replacement = ProjectArchiveSummary(
            projectName: "Client Work",
            summary: "Updated summary.",
            outcomes: ["Report shipped", "Invoice drafted"],
            risks: [],
            nextSteps: ["Close project"],
            generatedAt: Date(timeIntervalSince1970: 200)
        )
        try store.saveProjectArchiveSummary(replacement)

        loadedDetail = try store.projectArchiveDetail(name: "Client Work")
        detail = try #require(loadedDetail)
        #expect(detail.summary?.summary == "Updated summary.")
        #expect(detail.summary?.outcomes == ["Report shipped", "Invoice drafted"])
        #expect(detail.summary?.nextSteps == ["Close project"])
    }

    @Test("task metadata can be edited after creation")
    func taskMetadataCanBeEditedAfterCreation() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        let task = try store.addTask(
            title: "Tune task",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .medium,
            source: .manual,
            projectName: "个人工作"
        )

        try store.updateTaskMetadata(id: task.id, projectName: "Client Work", priority: .high, dueTime: "08:45")

        let updated = try #require(store.tasks(on: DateOnly(year: 2026, month: 6, day: 7)).first)
        #expect(updated.projectName == "Client Work")
        #expect(updated.priority == .high)
        #expect(updated.dueTime == "08:45")
    }

    @Test("AI planning result is inserted as tasks and timeline snapshots")
    func planningResultIsInserted() async throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        let result = PlanningResult(
            tasks: [
                PlannedTask(title: "Sketch sticky note UI", project: "Todo App", priority: .medium, date: "2026-06-07", timeBlock: "morning"),
                PlannedTask(title: "Review database schema", project: "Todo App", priority: .low, date: "2026-06-08", timeBlock: "afternoon")
            ],
            timelineSummary: "Todo App spans UI today and schema tomorrow."
        )

        try store.applyPlanningResult(result, fallbackDate: DateOnly(year: 2026, month: 6, day: 7))

        #expect(try store.tasks(on: DateOnly(year: 2026, month: 6, day: 7)).map(\.title) == ["Sketch sticky note UI"])
        #expect(try store.tasks(on: DateOnly(year: 2026, month: 6, day: 8)).map(\.title) == ["Review database schema"])
        #expect(try store.timelineEntries(scope: .week, anchor: DateOnly(year: 2026, month: 6, day: 7)).contains { $0.projectName == "Todo App" })
    }

    @Test("archived projects are hidden from active timeline")
    func archivedProjectsAreHiddenFromActiveTimeline() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        _ = try store.addTask(
            title: "Finish archiveable work",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .medium,
            source: .manual,
            projectName: "Client Work"
        )
        #expect(try store.timelineEntries(scope: .week, anchor: DateOnly(year: 2026, month: 6, day: 7)).contains { $0.projectName == "Client Work" })

        try store.archiveProject(name: "Client Work")

        #expect(try !store.timelineEntries(scope: .week, anchor: DateOnly(year: 2026, month: 6, day: 7)).contains { $0.projectName == "Client Work" })
        #expect(try store.projectArchiveDetail(name: "Client Work")?.totalTaskCount == 1)
    }

    @Test("structured output parser rejects invalid task payloads")
    func parserRejectsInvalidPayloads() throws {
        let valid = """
        {
          "tasks": [
            {"title": "Plan today", "project": "Operations", "priority": "high", "date": "2026-06-07", "timeBlock": "10:00"}
          ],
          "timelineSummary": "Operations work is concentrated today."
        }
        """

        let parsed = try PlanningParser.parse(valid)
        #expect(parsed.tasks.first?.title == "Plan today")

        let invalid = #"{"tasks":[{"project":"Missing title"}],"timelineSummary":"Bad"}"#
        #expect(throws: PlanningParser.Error.self) {
            try PlanningParser.parse(invalid)
        }
    }

    @Test("daily notes update the same local database")
    func dailyNotesPersist() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        try store.saveDailyNote(
            DailyNote(
                date: DateOnly(year: 2026, month: 6, day: 7),
                blockers: "Need API key",
                completedSummary: "Created scaffold",
                tomorrowPlan: "Wire UI"
            )
        )

        let loadedNote = try store.dailyNote(on: DateOnly(year: 2026, month: 6, day: 7))
        let note = try #require(loadedNote)
        #expect(note.blockers == "Need API key")
        #expect(note.tomorrowPlan == "Wire UI")
    }

    @Test("overdue tasks only include incomplete tasks before today")
    func overdueTasksOnlyIncludeIncompletePastTasks() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        let yesterday = DateOnly(year: 2026, month: 6, day: 6)
        let today = DateOnly(year: 2026, month: 6, day: 7)
        let oldTask = try store.addTask(title: "Finish yesterday", date: yesterday, priority: .high, source: .manual, projectName: "Todo App")
        let completed = try store.addTask(title: "Already done", date: yesterday, priority: .low, source: .manual, projectName: "Todo App")
        _ = try store.addTask(title: "Today task", date: today, priority: .medium, source: .manual, projectName: "Todo App")

        try store.setTaskCompleted(id: completed.id, isCompleted: true)

        let overdue = try store.overdueTasks(before: today)

        #expect(overdue.map(\.id) == [oldTask.id])
        #expect(overdue.first?.date == yesterday)
    }

    @Test("API keys can be saved, read, and cleared through a vault")
    func apiKeyVaultLifecycle() throws {
        let vault = InMemoryAPIKeyVault()

        try vault.save("sk-test")
        #expect(try vault.load() == "sk-test")

        try vault.clear()
        #expect(try vault.load() == nil)
    }

    private func temporaryDatabasePath() -> String {
        let name = UUID().uuidString + ".sqlite"
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name).path
    }
}
