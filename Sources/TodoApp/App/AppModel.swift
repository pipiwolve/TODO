import AppKit
import Foundation
import Observation
import TodoCore

@MainActor
@Observable
final class AppModel {
    static weak var shared: AppModel?

    var today: DateOnly
    var timelineWindow: TimelineWindow
    var tasks: [TodoTask] = []
    var timeline: [TimelineEntry] = []
    var timelineTasks: [TodoTask] = []
    var overdueTasks: [TodoTask] = []
    var projects: [Project] = []
    var archivedProjects: [Project] = []
    var selectedArchivedProjectName: String?
    var selectedArchiveDetail: ProjectArchiveDetail?
    var dailyNote: DailyNote
    var newProjectName = ""
    var showsArchivedProjects = false
    var draftTaskTitle = ""
    var draftProjectName = "个人工作"
    var draftPriority: TaskPriority = .medium
    var draftDueTime: String?
    var captureText = ""
    var statusMessage = ""
    var isPlanning = false
    var isGeneratingArchiveSummary = false
    var isCopyingDailyExport = false
    var apiKeyDraft = ""
    var isPinned = true
    var toast: Toast?

    weak var actions: AppActions?

    private let store: TodoStore
    private let planner: TodoPlanningService
    private let archiveSummarizer: ProjectArchiveSummarizingService
    private let dailyExportSummarizer: DailyExportSummarizingService
    private let vault: APIKeyVault

    init(store: TodoStore, planner: TodoPlanningService, archiveSummarizer: ProjectArchiveSummarizingService = DeepSeekArchiveSummarizer(), dailyExportSummarizer: DailyExportSummarizingService = DeepSeekDailyExportSummarizer(), vault: APIKeyVault, today: DateOnly = .today()) {
        self.store = store
        self.planner = planner
        self.archiveSummarizer = archiveSummarizer
        self.dailyExportSummarizer = dailyExportSummarizer
        self.vault = vault
        self.today = today
        self.timelineWindow = TimelineWindow(today: today)
        self.dailyNote = DailyNote(date: today, blockers: "", completedSummary: "", tomorrowPlan: "")
        AppModel.shared = self
        refresh()
        apiKeyDraft = (try? vault.load()) ?? ""
    }

    static func bootstrap() -> AppModel {
        do {
            let path = try TodoStore.defaultDatabasePath()
            return try AppModel(
                store: TodoStore(path: path),
                planner: DeepSeekPlanner(),
                archiveSummarizer: DeepSeekArchiveSummarizer(),
                dailyExportSummarizer: DeepSeekDailyExportSummarizer(),
                vault: KeychainAPIKeyVault()
            )
        } catch {
            let fallbackPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("todo-sticky-fallback.sqlite").path
            let fallbackStore = try! TodoStore(path: fallbackPath)
            let model = AppModel(store: fallbackStore, planner: DeepSeekPlanner(), archiveSummarizer: DeepSeekArchiveSummarizer(), dailyExportSummarizer: DeepSeekDailyExportSummarizer(), vault: InMemoryAPIKeyVault())
            model.statusMessage = "Using temporary storage: \(error.localizedDescription)"
            return model
        }
    }

    func refresh() {
        do {
            tasks = try store.tasks(on: today)
            timeline = try store.timelineEntries(scope: .week, anchor: timelineWindow.anchor)
            timelineTasks = try store.timelineTasks(scope: .week, anchor: timelineWindow.anchor)
            overdueTasks = try store.overdueTasks(before: today)
            projects = try store.projects()
            archivedProjects = try store.archivedProjects()
            if let selectedArchivedProjectName, archivedProjects.contains(where: { $0.name == selectedArchivedProjectName }) {
                selectedArchiveDetail = try store.projectArchiveDetail(name: selectedArchivedProjectName)
            } else {
                selectedArchivedProjectName = archivedProjects.first?.name
                selectedArchiveDetail = selectedArchivedProjectName.flatMap { try? store.projectArchiveDetail(name: $0) }
            }
            if !projects.contains(where: { $0.name == draftProjectName }) {
                draftProjectName = projects.first?.name ?? "个人工作"
            }
            dailyNote = try store.dailyNote(on: today) ?? DailyNote(date: today, blockers: "", completedSummary: "", tomorrowPlan: "")
        } catch {
            statusMessage = "Refresh failed: \(error.localizedDescription)"
        }
    }

    func showPreviousTimelineWeek() {
        timelineWindow.moveBackward()
        refresh()
    }

    func showNextTimelineWeek() {
        timelineWindow.moveForward()
        refresh()
    }

    func addManualTask() {
        let title = draftTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        do {
            _ = try store.addTask(
                title: title,
                date: today,
                priority: draftPriority,
                source: .manual,
                projectName: draftProjectName,
                dueTime: draftDueTime
            )
            draftTaskTitle = ""
            showToast("Added")
            refresh()
        } catch {
            showToast("Add failed")
            statusMessage = "Add failed: \(error.localizedDescription)"
        }
    }

    func delete(_ task: TodoTask) {
        do {
            try store.deleteTask(id: task.id)
            showToast("Deleted")
            refresh()
        } catch {
            showToast("Delete failed")
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func toggle(_ task: TodoTask) {
        do {
            try store.setTaskCompleted(id: task.id, isCompleted: !task.isCompleted)
            refresh()
        } catch {
            statusMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    func updateTaskMetadata(_ task: TodoTask, projectName: String?, priority: TaskPriority, dueTime: String?) {
        do {
            try store.updateTaskMetadata(id: task.id, projectName: projectName, priority: priority, dueTime: dueTime)
            showToast("Updated")
            refresh()
        } catch {
            showToast("Update failed")
            statusMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    func renameTask(_ task: TodoTask, to title: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            showToast("Rename failed")
            statusMessage = "Task title is empty"
            return
        }
        guard cleanTitle != task.title else { return }
        do {
            try store.renameTask(id: task.id, title: cleanTitle)
            showToast("Renamed")
            refresh()
        } catch {
            showToast("Rename failed")
            statusMessage = "Rename failed: \(error.localizedDescription)"
            refresh()
        }
    }

    func copyDailyExportToClipboard() async {
        guard !isCopyingDailyExport else { return }

        isCopyingDailyExport = true
        defer { isCopyingDailyExport = false }

        let context = DailyExportRenderer.context(date: today, tasks: tasks, projects: projects)
        var summary = DailyExportRenderer.fallbackSummary(context: context)
        var usedFallback = true

        do {
            if let apiKey = try vault.load(), !apiKey.isEmpty {
                summary = try await dailyExportSummarizer.summarize(context: context, apiKey: apiKey)
                usedFallback = false
            } else {
                statusMessage = "Daily report copied with local summary. Add API key in Settings for AI summary."
            }
        } catch {
            statusMessage = "Daily report copied. AI summary skipped: \(error.localizedDescription)"
        }

        let report = DailyExportRenderer.markdown(context: context, summary: summary)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(report, forType: .string) else {
            showToast("Copy failed")
            statusMessage = "Copy failed: could not write to clipboard"
            return
        }

        showToast(usedFallback ? "Copied local report" : "Copied AI report")
    }

    func tasks(forProject projectName: String, on date: DateOnly) -> [TodoTask] {
        timelineTasks.filter { ($0.projectName ?? "Inbox") == projectName && $0.date == date }
    }

    func moveTask(_ task: TodoTask, to date: DateOnly) {
        guard task.date != date else { return }
        do {
            try store.moveTask(id: task.id, to: date)
            showToast("Date updated")
            refresh()
        } catch {
            showToast("Date failed")
            statusMessage = "Date failed: \(error.localizedDescription)"
            refresh()
        }
    }

    func renameProject(from oldName: String, to newName: String) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            showToast("Rename failed")
            statusMessage = "Project name is empty"
            return
        }
        guard oldName != cleanName else { return }
        do {
            try store.renameProject(from: oldName, to: cleanName)
            if draftProjectName == oldName {
                draftProjectName = cleanName
            }
            if selectedArchivedProjectName == oldName {
                selectedArchivedProjectName = cleanName
            }
            showToast("Project renamed")
            refresh()
        } catch {
            showToast("Rename failed")
            statusMessage = "Rename failed: \(error.localizedDescription)"
            refresh()
        }
    }

    func saveDailyNote() {
        do {
            try store.saveDailyNote(dailyNote)
            showToast("Journal saved")
            refresh()
        } catch {
            showToast("Journal failed")
            statusMessage = "Journal failed: \(error.localizedDescription)"
        }
    }

    func saveAPIKey() {
        do {
            if apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try vault.clear()
                showToast("API key cleared")
            } else {
                try vault.save(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                showToast("API key saved")
            }
        } catch {
            showToast("Keychain failed")
            statusMessage = "Keychain failed: \(error.localizedDescription)"
        }
    }

    func planCapture() async {
        let input = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        isPlanning = true
        defer { isPlanning = false }

        do {
            guard let apiKey = try vault.load(), !apiKey.isEmpty else {
                showToast("Add API key in Settings")
                statusMessage = "Add your DeepSeek API key in Settings"
                return
            }
            let result = try await planner.plan(input: input, date: today, apiKey: apiKey)
            try store.applyPlanningResult(result, fallbackDate: today)
            captureText = ""
            showToast("Planned \(result.tasks.count) tasks")
            refresh()
        } catch {
            showToast("Planning failed")
            statusMessage = "AI planning failed. You can add tasks manually."
        }
    }

    func showSettings() {
        actions?.showSettings()
    }

    func showTimeline() {
        actions?.showTimeline(model: self)
    }

    func showAddProject() {
        actions?.showAddProject(model: self)
    }

    func showArchivedProjects() {
        refresh()
        actions?.showArchivedProjects(model: self)
    }

    func togglePinned() {
        isPinned.toggle()
        actions?.setStickyPinned(isPinned)
        showToast(isPinned ? "Pinned on top" : "Unpinned")
    }

    func addProjectFromDraft() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try store.addProject(name: name)
            newProjectName = ""
            draftProjectName = name
            showToast("Project added")
            refresh()
        } catch {
            showToast("Project failed")
            statusMessage = "Project failed: \(error.localizedDescription)"
        }
    }

    func archiveProject(named name: String) {
        do {
            try store.archiveProject(name: name)
            showToast("Project archived")
            refresh()
            Task {
                await generateArchiveSummary(for: name, showsToastOnSuccess: false)
            }
        } catch {
            showToast("Archive failed")
            statusMessage = "Archive failed: \(error.localizedDescription)"
        }
    }

    func deleteProject(named name: String) {
        do {
            try store.deleteProject(name: name)
            if selectedArchivedProjectName == name {
                selectedArchivedProjectName = nil
                selectedArchiveDetail = nil
            }
            showToast("Project deleted")
            refresh()
        } catch {
            showToast("Delete failed")
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func selectArchivedProject(_ project: Project) {
        selectedArchivedProjectName = project.name
        loadArchiveDetail(named: project.name)
    }

    func loadArchiveDetail(named name: String) {
        do {
            selectedArchiveDetail = try store.projectArchiveDetail(name: name)
        } catch {
            showToast("Archive detail failed")
            statusMessage = "Archive detail failed: \(error.localizedDescription)"
        }
    }

    func regenerateArchiveSummary() {
        guard let name = selectedArchivedProjectName else { return }
        Task {
            await generateArchiveSummary(for: name, showsToastOnSuccess: true)
        }
    }

    func generateArchiveSummary(for name: String, showsToastOnSuccess: Bool) async {
        do {
            guard let apiKey = try vault.load(), !apiKey.isEmpty else {
                statusMessage = "Archive saved. Add API key in Settings to generate a summary."
                return
            }
            guard let detail = try store.projectArchiveDetail(name: name) else {
                statusMessage = "Archive summary failed: project not found"
                return
            }

            isGeneratingArchiveSummary = true
            defer { isGeneratingArchiveSummary = false }

            let summary = try await archiveSummarizer.summarize(context: detail.archiveContext, apiKey: apiKey)
            try store.saveProjectArchiveSummary(summary)
            if selectedArchivedProjectName == name {
                selectedArchiveDetail = try store.projectArchiveDetail(name: name)
            }
            if showsToastOnSuccess {
                showToast("Archive summary updated")
            } else {
                statusMessage = "Archive summary generated"
            }
        } catch {
            showToast("Archive summary skipped")
            statusMessage = "Archive saved. AI summary failed: \(error.localizedDescription)"
        }
    }

    private func showToast(_ message: String) {
        let toast = Toast(message: message)
        self.toast = toast
        statusMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.7))
            if self.toast?.id == toast.id {
                self.toast = nil
            }
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
}
