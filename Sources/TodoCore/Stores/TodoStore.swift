import Foundation
import SQLite3

public final class TodoStore: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable {
        case openFailed(String)
        case executeFailed(String)
        case prepareFailed(String)
        case invalidDate(String)
    }

    private let db: OpaquePointer?
    private let lock = NSLock()
    private static let protectedProjectNames: Set<String> = ["Inbox", "个人工作"]

    public static func defaultDatabasePath(appName: String = "TodoSticky") throws -> String {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent(appName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("todo.sqlite").path
    }

    public init(path: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            throw Error.openFailed(message)
        }

        db = handle
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public func addTask(title: String, date: DateOnly, priority: TaskPriority, source: TaskSource, projectName: String?, dueTime: String? = nil) throws -> TodoTask {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProjectName = try projectName?.nilIfBlank ?? inboxProjectName()
        let now = Date()
        let task = TodoTask(
            id: UUID(),
            title: cleanTitle,
            date: date,
            isCompleted: false,
            priority: priority,
            source: source,
            projectName: cleanProjectName,
            dueTime: dueTime?.normalizedDueTime,
            createdAt: now,
            updatedAt: now
        )

        try ensureProject(named: task.projectName)
        try withStatement(
            """
            INSERT INTO tasks (id, title, date, is_completed, priority, source, project_name, due_time, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        ) { statement in
            bind(task.id.uuidString, to: 1, in: statement)
            bind(task.title, to: 2, in: statement)
            bind(task.date.isoString, to: 3, in: statement)
            sqlite3_bind_int(statement, 4, task.isCompleted ? 1 : 0)
            bind(task.priority.rawValue, to: 5, in: statement)
            bind(task.source.rawValue, to: 6, in: statement)
            bind(task.projectName, to: 7, in: statement)
            bind(task.dueTime, to: 8, in: statement)
            bind(task.createdAt.timeIntervalSince1970, to: 9, in: statement)
            bind(task.updatedAt.timeIntervalSince1970, to: 10, in: statement)
            try stepDone(statement)
        }
        return task
    }

    public func tasks(on date: DateOnly) throws -> [TodoTask] {
        try queryTasks(
            sql: "SELECT id, title, date, is_completed, priority, source, project_name, due_time, created_at, updated_at FROM tasks WHERE date = ? ORDER BY COALESCE(due_time, '99:99') ASC, created_at ASC",
            bindings: { statement in bind(date.isoString, to: 1, in: statement) }
        )
    }

    public func allTasks(from start: DateOnly, through end: DateOnly) throws -> [TodoTask] {
        try queryTasks(
            sql: "SELECT id, title, date, is_completed, priority, source, project_name, due_time, created_at, updated_at FROM tasks WHERE date >= ? AND date <= ? ORDER BY date ASC, COALESCE(due_time, '99:99') ASC, created_at ASC",
            bindings: { statement in
                bind(start.isoString, to: 1, in: statement)
                bind(end.isoString, to: 2, in: statement)
            }
        )
    }

    public func overdueTasks(before date: DateOnly) throws -> [TodoTask] {
        try queryTasks(
            sql: "SELECT id, title, date, is_completed, priority, source, project_name, due_time, created_at, updated_at FROM tasks WHERE date < ? AND is_completed = 0 ORDER BY date ASC, priority DESC, COALESCE(due_time, '99:99') ASC, created_at ASC",
            bindings: { statement in bind(date.isoString, to: 1, in: statement) }
        )
    }

    public func projects() throws -> [Project] {
        try queryProjects(active: true)
    }

    public func archivedProjects() throws -> [Project] {
        try queryProjects(active: false)
    }

    public func addProject(name: String) throws -> Project {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            throw Error.executeFailed("Project name is empty")
        }
        try withStatement(
            """
            INSERT INTO projects (id, name, color_hex, is_active)
            VALUES (?, ?, ?, 1)
            ON CONFLICT(name) DO UPDATE SET is_active = 1
            """
        ) { statement in
            bind(UUID().uuidString, to: 1, in: statement)
            bind(cleanName, to: 2, in: statement)
            bind(ProjectColor.paletteColor(for: cleanName), to: 3, in: statement)
            try stepDone(statement)
        }
        return try projects().first { $0.name == cleanName } ?? Project(id: UUID(), name: cleanName, colorHex: ProjectColor.paletteColor(for: cleanName), isActive: true)
    }

    public func archiveProject(name: String) throws {
        try withStatement("UPDATE projects SET is_active = 0, archived_at = ? WHERE name = ?") { statement in
            bind(Date().timeIntervalSince1970, to: 1, in: statement)
            bind(name, to: 2, in: statement)
            try stepDone(statement)
        }
    }

    public func deleteProject(name: String) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Self.protectedProjectNames.contains(cleanName) else {
            throw Error.executeFailed("Default projects cannot be deleted")
        }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try withStatement("DELETE FROM tasks WHERE COALESCE(project_name, 'Inbox') = ?") { statement in
                bind(cleanName, to: 1, in: statement)
                try stepDone(statement)
            }
            try withStatement("DELETE FROM project_archive_summaries WHERE project_name = ?") { statement in
                bind(cleanName, to: 1, in: statement)
                try stepDone(statement)
            }
            try withStatement("DELETE FROM projects WHERE name = ?") { statement in
                bind(cleanName, to: 1, in: statement)
                try stepDone(statement)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func renameProject(from oldName: String, to newName: String) throws {
        let cleanOldName = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOldName.isEmpty, !cleanNewName.isEmpty else {
            throw Error.executeFailed("Project name is empty")
        }
        guard cleanOldName != cleanNewName else { return }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try withStatement("UPDATE projects SET name = ? WHERE name = ?") { statement in
                bind(cleanNewName, to: 1, in: statement)
                bind(cleanOldName, to: 2, in: statement)
                try stepDone(statement)
            }
            try withStatement("UPDATE tasks SET project_name = ?, updated_at = ? WHERE COALESCE(project_name, 'Inbox') = ?") { statement in
                bind(cleanNewName, to: 1, in: statement)
                bind(Date().timeIntervalSince1970, to: 2, in: statement)
                bind(cleanOldName, to: 3, in: statement)
                try stepDone(statement)
            }
            try withStatement("UPDATE project_archive_summaries SET project_name = ? WHERE project_name = ?") { statement in
                bind(cleanNewName, to: 1, in: statement)
                bind(cleanOldName, to: 2, in: statement)
                try stepDone(statement)
            }
            if try inboxProjectName() == cleanOldName {
                try setInboxProjectName(cleanNewName)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func projectArchiveDetail(name: String) throws -> ProjectArchiveDetail? {
        guard let project = try project(named: name) else {
            return nil
        }

        let tasks = try tasks(forProjectNamed: name)
        let dailyNotes = try dailyNotes(from: tasks.map(\.date).min(), through: tasks.map(\.date).max())
        let summary = try projectArchiveSummary(projectName: name)
        return ProjectArchiveDetail(project: project, tasks: tasks, dailyNotes: dailyNotes, summary: summary)
    }

    public func saveProjectArchiveSummary(_ summary: ProjectArchiveSummary) throws {
        let encoder = JSONEncoder()
        let outcomes = String(data: try encoder.encode(summary.outcomes), encoding: .utf8) ?? "[]"
        let risks = String(data: try encoder.encode(summary.risks), encoding: .utf8) ?? "[]"
        let nextSteps = String(data: try encoder.encode(summary.nextSteps), encoding: .utf8) ?? "[]"

        try withStatement(
            """
            INSERT INTO project_archive_summaries (project_name, summary, outcomes_json, risks_json, next_steps_json, generated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(project_name) DO UPDATE SET
              summary = excluded.summary,
              outcomes_json = excluded.outcomes_json,
              risks_json = excluded.risks_json,
              next_steps_json = excluded.next_steps_json,
              generated_at = excluded.generated_at
            """
        ) { statement in
            bind(summary.projectName, to: 1, in: statement)
            bind(summary.summary, to: 2, in: statement)
            bind(outcomes, to: 3, in: statement)
            bind(risks, to: 4, in: statement)
            bind(nextSteps, to: 5, in: statement)
            bind(summary.generatedAt.timeIntervalSince1970, to: 6, in: statement)
            try stepDone(statement)
        }
    }

    private func queryProjects(active: Bool) throws -> [Project] {
        var projects: [Project] = []
        try withStatement("SELECT id, name, color_hex, is_active, archived_at FROM projects WHERE is_active = ? ORDER BY name ASC") { statement in
            sqlite3_bind_int(statement, 1, active ? 1 : 0)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard
                    let idString = columnString(statement, 0),
                    let id = UUID(uuidString: idString),
                    let name = columnString(statement, 1),
                    let colorHex = columnString(statement, 2)
                else {
                    throw Error.executeFailed("Could not decode project row")
                }
                projects.append(
                    Project(
                        id: id,
                        name: name,
                        colorHex: colorHex,
                        isActive: sqlite3_column_int(statement, 3) == 1,
                        archivedAt: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                    )
                )
            }
        }
        return projects
    }

    public func deleteTask(id: UUID) throws {
        try withStatement("DELETE FROM tasks WHERE id = ?") { statement in
            bind(id.uuidString, to: 1, in: statement)
            try stepDone(statement)
        }
    }

    public func setTaskCompleted(id: UUID, isCompleted: Bool) throws {
        try withStatement("UPDATE tasks SET is_completed = ?, updated_at = ? WHERE id = ?") { statement in
            sqlite3_bind_int(statement, 1, isCompleted ? 1 : 0)
            bind(Date().timeIntervalSince1970, to: 2, in: statement)
            bind(id.uuidString, to: 3, in: statement)
            try stepDone(statement)
        }
    }

    public func tasks(forProjectNamed name: String, on date: DateOnly) throws -> [TodoTask] {
        try queryTasks(
            sql: "SELECT id, title, date, is_completed, priority, source, project_name, due_time, created_at, updated_at FROM tasks WHERE COALESCE(project_name, 'Inbox') = ? AND date = ? ORDER BY COALESCE(due_time, '99:99') ASC, created_at ASC",
            bindings: { statement in
                bind(name, to: 1, in: statement)
                bind(date.isoString, to: 2, in: statement)
            }
        )
    }

    public func moveTask(id: UUID, to date: DateOnly) throws {
        try withStatement("UPDATE tasks SET date = ?, updated_at = ? WHERE id = ?") { statement in
            bind(date.isoString, to: 1, in: statement)
            bind(Date().timeIntervalSince1970, to: 2, in: statement)
            bind(id.uuidString, to: 3, in: statement)
            try stepDone(statement)
        }
    }

    public func renameTask(id: UUID, title: String) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            throw Error.executeFailed("Task title is empty")
        }
        try withStatement("UPDATE tasks SET title = ?, updated_at = ? WHERE id = ?") { statement in
            bind(cleanTitle, to: 1, in: statement)
            bind(Date().timeIntervalSince1970, to: 2, in: statement)
            bind(id.uuidString, to: 3, in: statement)
            try stepDone(statement)
        }
    }

    public func updateTaskMetadata(id: UUID, projectName: String?, priority: TaskPriority, dueTime: String?) throws {
        let cleanProject = projectName?.nilIfBlank
        try ensureProject(named: cleanProject)
        try withStatement("UPDATE tasks SET project_name = ?, priority = ?, due_time = ?, updated_at = ? WHERE id = ?") { statement in
            bind(cleanProject, to: 1, in: statement)
            bind(priority.rawValue, to: 2, in: statement)
            bind(dueTime?.normalizedDueTime, to: 3, in: statement)
            bind(Date().timeIntervalSince1970, to: 4, in: statement)
            bind(id.uuidString, to: 5, in: statement)
            try stepDone(statement)
        }
    }

    public func applyPlanningResult(_ result: PlanningResult, fallbackDate: DateOnly) throws {
        var touchedDates = Set<DateOnly>()
        for plannedTask in result.tasks {
            let taskDate = plannedTask.date.flatMap(DateOnly.init) ?? fallbackDate
            _ = try addTask(
                title: plannedTask.title,
                date: taskDate,
                priority: plannedTask.priority,
                source: .ai,
                projectName: plannedTask.project,
                dueTime: plannedTask.timeBlock?.normalizedDueTime
            )
            touchedDates.insert(taskDate)
        }

        let snapshotDate = touchedDates.min() ?? fallbackDate
        try withStatement(
            """
            INSERT INTO planning_snapshots (id, anchor_date, scope, summary, created_at)
            VALUES (?, ?, ?, ?, ?)
            """
        ) { statement in
            bind(UUID().uuidString, to: 1, in: statement)
            bind(snapshotDate.isoString, to: 2, in: statement)
            bind("week", to: 3, in: statement)
            bind(result.timelineSummary, to: 4, in: statement)
            bind(Date().timeIntervalSince1970, to: 5, in: statement)
            try stepDone(statement)
        }
    }

    public func timelineEntries(scope: TimelineScope, anchor: DateOnly) throws -> [TimelineEntry] {
        let days = scope == .week ? 7 : 31
        let end = anchor.addingDays(days - 1)
        var entries: [TimelineEntry] = []

        try withStatement(
            """
            SELECT COALESCE(project_name, 'Inbox') AS project_name, date, COUNT(*), SUM(is_completed)
            FROM tasks
            LEFT JOIN projects ON projects.name = COALESCE(project_name, 'Inbox')
            WHERE date >= ? AND date <= ?
              AND (tasks.project_name IS NULL OR projects.name IS NULL OR projects.is_active = 1)
            GROUP BY project_name, date
            ORDER BY date ASC, project_name ASC
            """
        ) { statement in
            bind(anchor.isoString, to: 1, in: statement)
            bind(end.isoString, to: 2, in: statement)
            while sqlite3_step(statement) == SQLITE_ROW {
                let project = columnString(statement, 0) ?? "Inbox"
                guard let dateString = columnString(statement, 1), let date = DateOnly(dateString) else {
                    throw Error.invalidDate(columnString(statement, 1) ?? "")
                }
                let taskCount = Int(sqlite3_column_int(statement, 2))
                let completedCount = Int(sqlite3_column_int(statement, 3))
                entries.append(
                    TimelineEntry(
                        projectName: project,
                        date: date,
                        taskCount: taskCount,
                        completedCount: completedCount,
                        summary: nil
                    )
                )
            }
        }

        return entries
    }

    public func timelineTasks(scope: TimelineScope, anchor: DateOnly) throws -> [TodoTask] {
        let days = scope == .week ? 7 : 31
        let end = anchor.addingDays(days - 1)
        return try queryTasks(
            sql: """
            SELECT tasks.id, title, date, is_completed, priority, source, project_name, due_time, created_at, updated_at
            FROM tasks
            LEFT JOIN projects ON projects.name = COALESCE(project_name, 'Inbox')
            WHERE date >= ? AND date <= ?
              AND (tasks.project_name IS NULL OR projects.name IS NULL OR projects.is_active = 1)
            ORDER BY date ASC, COALESCE(due_time, '99:99') ASC, created_at ASC
            """,
            bindings: { statement in
                bind(anchor.isoString, to: 1, in: statement)
                bind(end.isoString, to: 2, in: statement)
            }
        )
    }

    public func saveDailyNote(_ note: DailyNote) throws {
        try withStatement(
            """
            INSERT INTO daily_notes (date, blockers, completed_summary, tomorrow_plan, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(date) DO UPDATE SET
              blockers = excluded.blockers,
              completed_summary = excluded.completed_summary,
              tomorrow_plan = excluded.tomorrow_plan,
              updated_at = excluded.updated_at
            """
        ) { statement in
            bind(note.date.isoString, to: 1, in: statement)
            bind(note.blockers, to: 2, in: statement)
            bind(note.completedSummary, to: 3, in: statement)
            bind(note.tomorrowPlan, to: 4, in: statement)
            bind(Date().timeIntervalSince1970, to: 5, in: statement)
            try stepDone(statement)
        }
    }

    public func dailyNote(on date: DateOnly) throws -> DailyNote? {
        var note: DailyNote?
        try withStatement("SELECT blockers, completed_summary, tomorrow_plan FROM daily_notes WHERE date = ?") { statement in
            bind(date.isoString, to: 1, in: statement)
            if sqlite3_step(statement) == SQLITE_ROW {
                note = DailyNote(
                    date: date,
                    blockers: columnString(statement, 0) ?? "",
                    completedSummary: columnString(statement, 1) ?? "",
                    tomorrowPlan: columnString(statement, 2) ?? ""
                )
            }
        }
        return note
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                color_hex TEXT NOT NULL,
                is_active INTEGER NOT NULL DEFAULT 1,
                archived_at REAL
            );
            """
        )
        try addColumnIfNeeded(table: "projects", column: "archived_at", definition: "REAL")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS tasks (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                date TEXT NOT NULL,
                is_completed INTEGER NOT NULL DEFAULT 0,
                priority TEXT NOT NULL,
                source TEXT NOT NULL,
                project_name TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS idx_tasks_date ON tasks(date);")
        try addColumnIfNeeded(table: "tasks", column: "due_time", definition: "TEXT")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS daily_notes (
                date TEXT PRIMARY KEY,
                blockers TEXT NOT NULL,
                completed_summary TEXT NOT NULL,
                tomorrow_plan TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS planning_snapshots (
                id TEXT PRIMARY KEY,
                anchor_date TEXT NOT NULL,
                scope TEXT NOT NULL,
                summary TEXT NOT NULL,
                created_at REAL NOT NULL
            );
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS project_archive_summaries (
                project_name TEXT PRIMARY KEY,
                summary TEXT NOT NULL,
                outcomes_json TEXT NOT NULL,
                risks_json TEXT NOT NULL,
                next_steps_json TEXT NOT NULL,
                generated_at REAL NOT NULL
            );
            """
        )
        try ensureDefaultProjectsIfNeeded()
    }

    private func project(named name: String) throws -> Project? {
        var project: Project?
        try withStatement("SELECT id, name, color_hex, is_active, archived_at FROM projects WHERE name = ?") { statement in
            bind(name, to: 1, in: statement)
            if sqlite3_step(statement) == SQLITE_ROW {
                guard
                    let idString = columnString(statement, 0),
                    let id = UUID(uuidString: idString),
                    let name = columnString(statement, 1),
                    let colorHex = columnString(statement, 2)
                else {
                    throw Error.executeFailed("Could not decode project row")
                }
                project = Project(
                    id: id,
                    name: name,
                    colorHex: colorHex,
                    isActive: sqlite3_column_int(statement, 3) == 1,
                    archivedAt: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                )
            }
        }
        return project
    }

    private func tasks(forProjectNamed name: String) throws -> [TodoTask] {
        try queryTasks(
            sql: "SELECT id, title, date, is_completed, priority, source, project_name, due_time, created_at, updated_at FROM tasks WHERE COALESCE(project_name, 'Inbox') = ? ORDER BY date ASC, COALESCE(due_time, '99:99') ASC, created_at ASC",
            bindings: { statement in bind(name, to: 1, in: statement) }
        )
    }

    private func dailyNotes(from start: DateOnly?, through end: DateOnly?) throws -> [DailyNote] {
        guard let start, let end else {
            return []
        }

        var notes: [DailyNote] = []
        try withStatement("SELECT date, blockers, completed_summary, tomorrow_plan FROM daily_notes WHERE date >= ? AND date <= ? ORDER BY date ASC") { statement in
            bind(start.isoString, to: 1, in: statement)
            bind(end.isoString, to: 2, in: statement)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let dateString = columnString(statement, 0), let date = DateOnly(dateString) else {
                    throw Error.invalidDate(columnString(statement, 0) ?? "")
                }
                notes.append(
                    DailyNote(
                        date: date,
                        blockers: columnString(statement, 1) ?? "",
                        completedSummary: columnString(statement, 2) ?? "",
                        tomorrowPlan: columnString(statement, 3) ?? ""
                    )
                )
            }
        }
        return notes
    }

    private func projectArchiveSummary(projectName: String) throws -> ProjectArchiveSummary? {
        var summary: ProjectArchiveSummary?
        try withStatement("SELECT summary, outcomes_json, risks_json, next_steps_json, generated_at FROM project_archive_summaries WHERE project_name = ?") { statement in
            bind(projectName, to: 1, in: statement)
            if sqlite3_step(statement) == SQLITE_ROW {
                let decoder = JSONDecoder()
                let outcomes = try decodeStringArray(columnString(statement, 1), decoder: decoder)
                let risks = try decodeStringArray(columnString(statement, 2), decoder: decoder)
                let nextSteps = try decodeStringArray(columnString(statement, 3), decoder: decoder)
                summary = ProjectArchiveSummary(
                    projectName: projectName,
                    summary: columnString(statement, 0) ?? "",
                    outcomes: outcomes,
                    risks: risks,
                    nextSteps: nextSteps,
                    generatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                )
            }
        }
        return summary
    }

    private func ensureProject(named projectName: String?) throws {
        guard let projectName else { return }
        try withStatement(
            """
            INSERT OR IGNORE INTO projects (id, name, color_hex, is_active)
            VALUES (?, ?, ?, 1)
            """
        ) { statement in
            bind(UUID().uuidString, to: 1, in: statement)
            bind(projectName, to: 2, in: statement)
            bind(ProjectColor.paletteColor(for: projectName), to: 3, in: statement)
            try stepDone(statement)
        }
    }

    private func ensureDefaultProjectsIfNeeded() throws {
        var projectCount = 0
        try withStatement("SELECT COUNT(*) FROM projects") { statement in
            if sqlite3_step(statement) == SQLITE_ROW {
                projectCount = Int(sqlite3_column_int(statement, 0))
            }
        }
        guard projectCount == 0 else { return }
        try ensureProject(named: "个人工作")
        try ensureProject(named: "Inbox")
        try setInboxProjectName("Inbox")
    }

    private func inboxProjectName() throws -> String {
        var name: String?
        try withStatement("SELECT value FROM app_settings WHERE key = ?") { statement in
            bind("inbox_project_name", to: 1, in: statement)
            if sqlite3_step(statement) == SQLITE_ROW {
                name = columnString(statement, 0)
            }
        }
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "Inbox"
    }

    private func setInboxProjectName(_ name: String) throws {
        try withStatement(
            """
            INSERT INTO app_settings (key, value)
            VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """
        ) { statement in
            bind("inbox_project_name", to: 1, in: statement)
            bind(name, to: 2, in: statement)
            try stepDone(statement)
        }
    }

    private func queryTasks(sql: String, bindings: (OpaquePointer?) throws -> Void) throws -> [TodoTask] {
        var tasks: [TodoTask] = []
        try withStatement(sql) { statement in
            try bindings(statement)
            while sqlite3_step(statement) == SQLITE_ROW {
                guard
                    let idString = columnString(statement, 0),
                    let id = UUID(uuidString: idString),
                    let title = columnString(statement, 1),
                    let dateString = columnString(statement, 2),
                    let date = DateOnly(dateString),
                    let priorityString = columnString(statement, 4),
                    let priority = TaskPriority(rawValue: priorityString),
                    let sourceString = columnString(statement, 5),
                    let source = TaskSource(rawValue: sourceString)
                else {
                    throw Error.executeFailed("Could not decode task row")
                }

                tasks.append(
                    TodoTask(
                        id: id,
                        title: title,
                        date: date,
                        isCompleted: sqlite3_column_int(statement, 3) == 1,
                        priority: priority,
                        source: source,
                        projectName: columnString(statement, 6),
                        dueTime: columnString(statement, 7),
                        createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                        updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9))
                    )
                )
            }
        }
        return tasks
    }

    private func addColumnIfNeeded(table: String, column: String, definition: String) throws {
        var exists = false
        try withStatement("PRAGMA table_info(\(table))") { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                if columnString(statement, 1) == column {
                    exists = true
                    break
                }
            }
        }
        if !exists {
            try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
        }
    }

    private func execute(_ sql: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? currentErrorMessage
            sqlite3_free(error)
            throw Error.executeFailed(message)
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer?) throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Error.prepareFailed(currentErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw Error.executeFailed(currentErrorMessage)
        }
    }

    private var currentErrorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
    }
}

private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer?) {
    guard let value else {
        sqlite3_bind_null(statement, index)
        return
    }
    sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
}

private func bind(_ value: Double, to index: Int32, in statement: OpaquePointer?) {
    sqlite3_bind_double(statement, index, value)
}

private func columnString(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard let pointer = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: pointer)
}

private func decodeStringArray(_ json: String?, decoder: JSONDecoder) throws -> [String] {
    guard let data = (json ?? "[]").data(using: .utf8) else {
        throw TodoStore.Error.executeFailed("Could not decode archive summary JSON")
    }
    return try decoder.decode([String].self, from: data)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    var nilIfBlank: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    var normalizedDueTime: String? {
        let clean = trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([0-1]?[0-9]|2[0-3]):([0-5][0-9])$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
              let hourRange = Range(match.range(at: 1), in: clean),
              let minuteRange = Range(match.range(at: 2), in: clean),
              let hour = Int(clean[hourRange])
        else {
            return nil
        }
        return String(format: "%02d:%@", hour, String(clean[minuteRange]))
    }
}

private enum ProjectColor {
    private static let palette = ["#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#06B6D4"]

    static func paletteColor(for name: String) -> String {
        let index = abs(name.hashValue) % palette.count
        return palette[index]
    }
}
