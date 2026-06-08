import Foundation

public struct DateOnly: Codable, Hashable, Sendable, Comparable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func < (lhs: DateOnly, rhs: DateOnly) -> Bool {
        lhs.isoString < rhs.isoString
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init?(_ isoString: String) {
        let parts = isoString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            return nil
        }
        self.year = parts[0]
        self.month = parts[1]
        self.day = parts[2]
    }

    public static func today(calendar: Calendar = .current) -> DateOnly {
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        return DateOnly(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    public func addingDays(_ days: Int, calendar: Calendar = .current) -> DateOnly {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let date = calendar.date(from: components) ?? Date()
        let nextDate = calendar.date(byAdding: .day, value: days, to: date) ?? date
        let next = calendar.dateComponents([.year, .month, .day], from: nextDate)
        return DateOnly(year: next.year ?? year, month: next.month ?? month, day: next.day ?? day)
    }
}

public enum TaskPriority: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high
}

public enum TaskSource: String, Codable, Sendable {
    case manual
    case ai
}

public struct TodoTask: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var date: DateOnly
    public var isCompleted: Bool
    public var priority: TaskPriority
    public var source: TaskSource
    public var projectName: String?
    public var dueTime: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, title: String, date: DateOnly, isCompleted: Bool, priority: TaskPriority, source: TaskSource, projectName: String?, dueTime: String?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.date = date
        self.isCompleted = isCompleted
        self.priority = priority
        self.source = source
        self.projectName = projectName
        self.dueTime = dueTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Project: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var isActive: Bool
    public var archivedAt: Date?

    public init(id: UUID, name: String, colorHex: String, isActive: Bool, archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.isActive = isActive
        self.archivedAt = archivedAt
    }
}

public struct DailyNote: Codable, Hashable, Sendable {
    public var date: DateOnly
    public var blockers: String
    public var completedSummary: String
    public var tomorrowPlan: String

    public init(date: DateOnly, blockers: String, completedSummary: String, tomorrowPlan: String) {
        self.date = date
        self.blockers = blockers
        self.completedSummary = completedSummary
        self.tomorrowPlan = tomorrowPlan
    }
}

public struct PlannedTask: Codable, Hashable, Sendable {
    public var title: String
    public var project: String?
    public var priority: TaskPriority
    public var date: String?
    public var timeBlock: String?

    public init(title: String, project: String?, priority: TaskPriority, date: String?, timeBlock: String?) {
        self.title = title
        self.project = project
        self.priority = priority
        self.date = date
        self.timeBlock = timeBlock
    }
}

public struct PlanningResult: Codable, Hashable, Sendable {
    public var tasks: [PlannedTask]
    public var timelineSummary: String

    public init(tasks: [PlannedTask], timelineSummary: String) {
        self.tasks = tasks
        self.timelineSummary = timelineSummary
    }
}

public enum TimelineScope: Sendable {
    case week
    case month
}

public struct TimelineWindow: Hashable, Sendable {
    public private(set) var today: DateOnly
    public private(set) var weekOffset: Int

    public init(today: DateOnly, weekOffset: Int = 0) {
        self.today = today
        self.weekOffset = min(0, max(-1, weekOffset))
    }

    public var anchor: DateOnly {
        today.addingDays(weekOffset * 7)
    }

    public var end: DateOnly {
        anchor.addingDays(6)
    }

    public var canMoveBackward: Bool {
        weekOffset > -1
    }

    public var canMoveForward: Bool {
        weekOffset < 0
    }

    public mutating func moveBackward() {
        guard canMoveBackward else { return }
        weekOffset -= 1
    }

    public mutating func moveForward() {
        guard canMoveForward else { return }
        weekOffset += 1
    }
}

public struct TimelineEntry: Identifiable, Hashable, Sendable {
    public var id: String { projectName + ":" + date.isoString }
    public var projectName: String
    public var date: DateOnly
    public var taskCount: Int
    public var completedCount: Int
    public var summary: String?
}

public struct ProjectArchiveSummary: Codable, Hashable, Sendable {
    public var projectName: String
    public var summary: String
    public var outcomes: [String]
    public var risks: [String]
    public var nextSteps: [String]
    public var generatedAt: Date

    public init(projectName: String, summary: String, outcomes: [String], risks: [String], nextSteps: [String], generatedAt: Date) {
        self.projectName = projectName
        self.summary = summary
        self.outcomes = outcomes
        self.risks = risks
        self.nextSteps = nextSteps
        self.generatedAt = generatedAt
    }
}

public struct ProjectArchiveDetail: Hashable, Sendable {
    public var project: Project
    public var tasks: [TodoTask]
    public var dailyNotes: [DailyNote]
    public var summary: ProjectArchiveSummary?

    public init(project: Project, tasks: [TodoTask], dailyNotes: [DailyNote], summary: ProjectArchiveSummary?) {
        self.project = project
        self.tasks = tasks
        self.dailyNotes = dailyNotes
        self.summary = summary
    }

    public var completedTasks: [TodoTask] {
        tasks.filter(\.isCompleted)
    }

    public var incompleteTasks: [TodoTask] {
        tasks.filter { !$0.isCompleted }
    }

    public var totalTaskCount: Int {
        tasks.count
    }

    public var completedTaskCount: Int {
        completedTasks.count
    }

    public var incompleteTaskCount: Int {
        incompleteTasks.count
    }

    public var completionRate: Double {
        guard totalTaskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(totalTaskCount)
    }

    public var startDate: DateOnly? {
        tasks.map(\.date).min()
    }

    public var endDate: DateOnly? {
        tasks.map(\.date).max()
    }

    public var archiveContext: ProjectArchiveContext {
        ProjectArchiveContext(
            projectName: project.name,
            totalTaskCount: totalTaskCount,
            completedTaskCount: completedTaskCount,
            incompleteTaskCount: incompleteTaskCount,
            startDate: startDate,
            endDate: endDate,
            completedTasks: completedTasks.map(ProjectArchiveContext.Task.init(task:)),
            incompleteTasks: incompleteTasks.map(ProjectArchiveContext.Task.init(task:)),
            dailyNotes: dailyNotes.map(ProjectArchiveContext.Note.init(note:))
        )
    }
}

public struct ProjectArchiveContext: Codable, Hashable, Sendable {
    public struct Task: Codable, Hashable, Sendable {
        public var title: String
        public var date: DateOnly
        public var priority: TaskPriority
        public var dueTime: String?

        public init(title: String, date: DateOnly, priority: TaskPriority, dueTime: String?) {
            self.title = title
            self.date = date
            self.priority = priority
            self.dueTime = dueTime
        }

        public init(task: TodoTask) {
            self.init(title: task.title, date: task.date, priority: task.priority, dueTime: task.dueTime)
        }
    }

    public struct Note: Codable, Hashable, Sendable {
        public var date: DateOnly
        public var blockers: String
        public var completedSummary: String
        public var tomorrowPlan: String

        public init(date: DateOnly, blockers: String, completedSummary: String, tomorrowPlan: String) {
            self.date = date
            self.blockers = blockers
            self.completedSummary = completedSummary
            self.tomorrowPlan = tomorrowPlan
        }

        public init(note: DailyNote) {
            self.init(date: note.date, blockers: note.blockers, completedSummary: note.completedSummary, tomorrowPlan: note.tomorrowPlan)
        }
    }

    public var projectName: String
    public var totalTaskCount: Int
    public var completedTaskCount: Int
    public var incompleteTaskCount: Int
    public var startDate: DateOnly?
    public var endDate: DateOnly?
    public var completedTasks: [Task]
    public var incompleteTasks: [Task]
    public var dailyNotes: [Note]

    public init(projectName: String, totalTaskCount: Int, completedTaskCount: Int, incompleteTaskCount: Int, startDate: DateOnly?, endDate: DateOnly?, completedTasks: [Task], incompleteTasks: [Task], dailyNotes: [Note]) {
        self.projectName = projectName
        self.totalTaskCount = totalTaskCount
        self.completedTaskCount = completedTaskCount
        self.incompleteTaskCount = incompleteTaskCount
        self.startDate = startDate
        self.endDate = endDate
        self.completedTasks = completedTasks
        self.incompleteTasks = incompleteTasks
        self.dailyNotes = dailyNotes
    }
}

public struct ProjectArchiveSummaryPayload: Codable, Hashable, Sendable {
    public var summary: String
    public var outcomes: [String]
    public var risks: [String]
    public var nextSteps: [String]

    public init(summary: String, outcomes: [String], risks: [String], nextSteps: [String]) {
        self.summary = summary
        self.outcomes = outcomes
        self.risks = risks
        self.nextSteps = nextSteps
    }
}

public struct DailyExportContext: Codable, Hashable, Sendable {
    public var date: DateOnly
    public var projects: [DailyProjectExportContext]

    public init(date: DateOnly, projects: [DailyProjectExportContext]) {
        self.date = date
        self.projects = projects
    }
}

public struct DailyProjectExportContext: Codable, Hashable, Sendable {
    public var projectName: String
    public var totalTaskCount: Int
    public var completedTaskCount: Int
    public var incompleteTaskCount: Int
    public var completedTasks: [DailyExportTask]
    public var incompleteTasks: [DailyExportTask]

    public init(projectName: String, totalTaskCount: Int, completedTaskCount: Int, incompleteTaskCount: Int, completedTasks: [DailyExportTask], incompleteTasks: [DailyExportTask]) {
        self.projectName = projectName
        self.totalTaskCount = totalTaskCount
        self.completedTaskCount = completedTaskCount
        self.incompleteTaskCount = incompleteTaskCount
        self.completedTasks = completedTasks
        self.incompleteTasks = incompleteTasks
    }

    public var tasks: [DailyExportTask] {
        (completedTasks + incompleteTasks).sorted()
    }
}

public struct DailyExportTask: Codable, Hashable, Sendable, Comparable {
    public var title: String
    public var isCompleted: Bool
    public var priority: TaskPriority
    public var dueTime: String?

    public init(title: String, isCompleted: Bool, priority: TaskPriority, dueTime: String?) {
        self.title = title
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueTime = dueTime
    }

    public init(task: TodoTask) {
        self.init(title: task.title, isCompleted: task.isCompleted, priority: task.priority, dueTime: task.dueTime)
    }

    public static func < (lhs: DailyExportTask, rhs: DailyExportTask) -> Bool {
        let lhsDueTime = lhs.dueTime ?? "99:99"
        let rhsDueTime = rhs.dueTime ?? "99:99"
        if lhsDueTime != rhsDueTime {
            return lhsDueTime < rhsDueTime
        }
        return lhs.title < rhs.title
    }
}

public struct DailyExportSummary: Codable, Hashable, Sendable {
    public var bullets: [String]

    public init(bullets: [String]) {
        self.bullets = bullets
    }
}

public struct DailyExportSummaryPayload: Codable, Hashable, Sendable {
    public var bullets: [String]

    public init(bullets: [String]) {
        self.bullets = bullets
    }
}
