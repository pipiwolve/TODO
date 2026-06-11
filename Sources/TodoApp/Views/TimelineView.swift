import SwiftUI
import TodoCore
import UniformTypeIdentifiers

struct TimelineView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Week Plan")
                        .font(.title2.bold())
                    Text("Project work generated from your daily todos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                timelineWeekControls
                Button {
                    model.showAddProject()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add project")
                Button {
                    model.showArchivedProjects()
                } label: {
                    Image(systemName: "archivebox")
                }
                .help("Archived projects")
                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }

            if model.timeline.isEmpty {
                ContentUnavailableView("No timeline yet", systemImage: "calendar", description: Text("AI-planned or manual tasks will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GanttGrid(
                    entries: model.timeline,
                    anchor: model.timelineWindow.anchor,
                    timelineTasks: model.timelineTasks,
                    tasksForCell: model.tasks(forProject:on:),
                    onMoveTask: model.moveTask(_:to:),
                    onToggleTask: model.toggle(_:),
                    onShowPreviousWeek: model.showPreviousTimelineWeek,
                    onShowNextWeek: model.showNextTimelineWeek,
                    canShowPreviousWeek: model.timelineWindow.canMoveBackward,
                    canShowNextWeek: model.timelineWindow.canMoveForward,
                    onRenameProject: model.renameProject(from:to:),
                    onArchive: model.archiveProject,
                    onDelete: model.deleteProject
                )
            }

            OverdueAlertsView(model: model)
        }
        .padding(18)
        .frame(minWidth: 680, minHeight: 460)
    }

    private var timelineWeekControls: some View {
        HStack(spacing: 4) {
            Button {
                model.showPreviousTimelineWeek()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!model.timelineWindow.canMoveBackward)
            .help("Show previous week")

            Text(timelineRangeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 92)

            Button {
                model.showNextTimelineWeek()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!model.timelineWindow.canMoveForward)
            .help("Show this week")
        }
    }

    private var timelineRangeLabel: String {
        let start = model.timelineWindow.anchor
        let end = model.timelineWindow.end
        return "\(start.month)/\(start.day)-\(end.month)/\(end.day)"
    }
}

struct AddProjectPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Project")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("Project name", text: $model.newProjectName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.addProjectFromDraft() }
                Button {
                    model.addProjectFromDraft()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
            }
            Text("New projects become available in todo metadata and the Gantt view.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }
}

struct ArchivedProjectsPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            archiveSidebar
                .frame(width: 250)

            Divider()

            ArchiveDetailView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 500)
        .onAppear {
            model.refresh()
        }
    }

    private var archiveSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Archived", systemImage: "archivebox")
                    .font(.headline)
                Spacer()
                Text("\(model.archivedProjects.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if model.archivedProjects.isEmpty {
                ContentUnavailableView("No archived projects", systemImage: "archivebox", description: Text("Archive a project from the Gantt view."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(model.archivedProjects) { project in
                            let isSelected = model.selectedArchivedProjectName == project.name
                            Button {
                                model.selectArchivedProject(project)
                            } label: {
                                ArchivedProjectRow(project: project, detail: isSelected ? model.selectedArchiveDetail : nil, isSelected: isSelected)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
    }
}

private struct ArchivedProjectRow: View {
    let project: Project
    let detail: ProjectArchiveDetail?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(hex: project.colorHex))
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitle: String {
        if let detail {
            let rate = Int((detail.completionRate * 100).rounded())
            return "\(detail.completedTaskCount)/\(detail.totalTaskCount) complete · \(rate)%"
        }
        if let archivedAt = project.archivedAt {
            return "Archived \(archivedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Archived"
    }
}

private struct ArchiveDetailView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let detail = model.selectedArchiveDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(detail)
                        stats(detail)
                        summary(detail)
                        taskSections(detail)
                        dailyNotes(detail)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select an archived project", systemImage: "archivebox", description: Text("Completed work and archive summaries appear here."))
            }
        }
    }

    private func header(_ detail: ProjectArchiveDetail) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.project.name)
                    .font(.title2.bold())
                Text(dateRange(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.regenerateArchiveSummary()
            } label: {
                if model.isGeneratingArchiveSummary {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(detail.summary == nil ? "Generate" : "Regenerate", systemImage: "sparkles")
                }
            }
            .disabled(model.isGeneratingArchiveSummary)
            .help("Generate archive summary")
        }
    }

    private func stats(_ detail: ProjectArchiveDetail) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ArchiveStatCard(title: "Tasks", value: "\(detail.totalTaskCount)", color: .primary)
            ArchiveStatCard(title: "Complete", value: "\(detail.completedTaskCount)", color: .green)
            ArchiveStatCard(title: "Left", value: "\(detail.incompleteTaskCount)", color: detail.incompleteTaskCount == 0 ? .secondary : .orange)
            ArchiveStatCard(title: "Rate", value: "\(Int((detail.completionRate * 100).rounded()))%", color: .blue)
        }
    }

    private func summary(_ detail: ProjectArchiveDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Summary", systemImage: "sparkles")
                .font(.headline)
            if let summary = detail.summary {
                Text(summary.summary)
                    .font(.body)
                    .lineSpacing(2)
                ArchiveBulletGroup(title: "Outcomes", items: summary.outcomes, emptyText: "No outcomes listed.")
                ArchiveBulletGroup(title: "Risks", items: summary.risks, emptyText: "No risks listed.")
                ArchiveBulletGroup(title: "Next Steps", items: summary.nextSteps, emptyText: "No next steps listed.")
                Text("Generated \(summary.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No AI summary yet. Generate one to create a project close-out note from tasks and daily reviews.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func taskSections(_ detail: ProjectArchiveDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ArchiveTaskList(title: "Completed Work", tasks: detail.completedTasks, emptyText: "No completed tasks in this project.")
            ArchiveTaskList(title: "Leftover Work", tasks: detail.incompleteTasks, emptyText: "No leftover tasks.")
        }
    }

    private func dailyNotes(_ detail: ProjectArchiveDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Review Excerpts")
                .font(.headline)
            if detail.dailyNotes.isEmpty {
                Text("No daily reviews overlap this project's task dates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(detail.dailyNotes, id: \.date) { note in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(note.date.isoString)
                            .font(.caption.monospacedDigit().weight(.semibold))
                        if !note.completedSummary.isEmpty {
                            Text("Completed: \(note.completedSummary)")
                        }
                        if !note.blockers.isEmpty {
                            Text("Blockers: \(note.blockers)")
                        }
                        if !note.tomorrowPlan.isEmpty {
                            Text("Tomorrow: \(note.tomorrowPlan)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func dateRange(_ detail: ProjectArchiveDetail) -> String {
        switch (detail.startDate, detail.endDate) {
        case let (start?, end?) where start == end:
            return start.isoString
        case let (start?, end?):
            return "\(start.isoString) - \(end.isoString)"
        default:
            return "No tasks recorded"
        }
    }
}

private struct ArchiveStatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ArchiveBulletGroup: View {
    let title: String
    let items: [String]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
            if items.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.caption)
                }
            }
        }
    }
}

private struct ArchiveTaskList: View {
    let title: String
    let tasks: [TodoTask]
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(tasks) { task in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isCompleted ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(.callout.weight(.medium))
                            Text(taskMeta(task))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func taskMeta(_ task: TodoTask) -> String {
        [task.date.isoString, task.dueTime, task.priority.rawValue].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct OverdueAlertsView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Overdue Alerts", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Spacer()
                Text("\(model.overdueTasks.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(alertCountColor)
            }

            if model.overdueTasks.isEmpty {
                Text("No unfinished tasks before today.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.overdueTasks) { task in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.date.isoString)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.orange)
                                    Text(task.title)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(2)
                                    if let project = task.projectName {
                                        Text(project)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Button {
                                    model.toggle(task)
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Mark complete")
                            }
                            .padding(10)
                            .frame(width: 180, alignment: .leading)
                            .background(.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    private var alertCountColor: Color {
        model.overdueTasks.isEmpty ? .secondary : .orange
    }
}

private struct GanttGrid: View {
    let entries: [TimelineEntry]
    let anchor: DateOnly
    let timelineTasks: [TodoTask]
    let tasksForCell: (String, DateOnly) -> [TodoTask]
    let onMoveTask: (TodoTask, DateOnly) -> Void
    let onToggleTask: (TodoTask) -> Void
    let onShowPreviousWeek: () -> Void
    let onShowNextWeek: () -> Void
    let canShowPreviousWeek: Bool
    let canShowNextWeek: Bool
    let onRenameProject: (String, String) -> Void
    let onArchive: (String) -> Void
    let onDelete: (String) -> Void
    @State private var dragOffset: CGFloat = 0

    private var days: [DateOnly] {
        (0..<7).map { anchor.addingDays($0) }
    }

    private var projects: [String] {
        Array(Set(entries.map(\.projectName) + timelineTasks.map { $0.projectName ?? "Inbox" })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Project")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                ForEach(days, id: \.self) { day in
                    Text(shortLabel(for: day))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(projects, id: \.self) { project in
                        ProjectGanttRow(
                            project: project,
                            days: days,
                            allTasks: timelineTasks,
                            entry: entry(project:day:),
                            tasksForCell: tasksForCell,
                            onMoveTask: onMoveTask,
                            onToggleTask: onToggleTask,
                            onRenameProject: onRenameProject,
                            onArchive: onArchive,
                            onDelete: onDelete
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .offset(x: dragOffset * 0.12)
        .animation(.snappy(duration: 0.18), value: dragOffset)
        .simultaneousGesture(weekNavigationGesture)
    }

    private func entry(project: String, day: DateOnly) -> TimelineEntry? {
        entries.first { $0.projectName == project && $0.date == day }
    }

    private func shortLabel(for day: DateOnly) -> String {
        "\(day.month)/\(day.day)"
    }

    private var weekNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 36)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = constrainedDragOffset(value.translation.width)
            }
            .onEnded { value in
                defer { dragOffset = 0 }
                guard shouldNavigateWeek(for: value.translation) else { return }

                if value.translation.width > 0 {
                    guard canShowPreviousWeek else { return }
                    onShowPreviousWeek()
                } else {
                    guard canShowNextWeek else { return }
                    onShowNextWeek()
                }
            }
    }

    private func shouldNavigateWeek(for translation: CGSize) -> Bool {
        abs(translation.width) >= 80 && abs(translation.width) > abs(translation.height) * 1.4
    }

    private func constrainedDragOffset(_ width: CGFloat) -> CGFloat {
        if width > 0 {
            return canShowPreviousWeek ? min(width, 160) : min(width, 42)
        }
        return canShowNextWeek ? max(width, -160) : max(width, -42)
    }
}

private struct ProjectGanttRow: View {
    let project: String
    let days: [DateOnly]
    let allTasks: [TodoTask]
    let entry: (String, DateOnly) -> TimelineEntry?
    let tasksForCell: (String, DateOnly) -> [TodoTask]
    let onMoveTask: (TodoTask, DateOnly) -> Void
    let onToggleTask: (TodoTask) -> Void
    let onRenameProject: (String, String) -> Void
    let onArchive: (String) -> Void
    let onDelete: (String) -> Void
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var showsDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            projectHeader
            .frame(width: 130, alignment: .leading)
            .onHover { isHovering = $0 }
            .animation(.snappy(duration: 0.16), value: isHovering)
            .confirmationDialog(
                "Delete Project?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete(project)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete the project and all todos under it.")
            }

            ForEach(days, id: \.self) { day in
                GanttCell(
                    project: project,
                    day: day,
                    entry: entry(project, day),
                    tasks: tasksForCell(project, day),
                    allTasks: allTasks,
                    onMoveTask: onMoveTask,
                    onToggleTask: onToggleTask
                )
            }
        }
        .onChange(of: project) { _, newValue in
            if !isRenaming {
                draftName = newValue
            }
        }
    }

    @ViewBuilder
    private var projectHeader: some View {
        if isRenaming {
            HStack(spacing: 4) {
                TextField("Project", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.callout.weight(.medium))
                    .onSubmit(saveRename)

                Button(action: saveRename) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderless)
                .help("Save project name")

                Button {
                    draftName = project
                    isRenaming = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Cancel")
            }
            .onAppear {
                if draftName.isEmpty {
                    draftName = project
                }
            }
        } else {
            HStack(spacing: 4) {
                Text(project)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                if isHovering {
                    Button {
                        draftName = project
                        isRenaming = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Rename project")
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))

                    Button {
                        onArchive(project)
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Archive project")
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))

                    Button {
                        showsDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Delete project")
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
    }

    private func saveRename() {
        let cleanName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        onRenameProject(project, cleanName)
        isRenaming = false
    }
}

private struct GanttCell: View {
    let project: String
    let day: DateOnly
    let entry: TimelineEntry?
    let tasks: [TodoTask]
    let allTasks: [TodoTask]
    let onMoveTask: (TodoTask, DateOnly) -> Void
    let onToggleTask: (TodoTask) -> Void
    @State private var showsTasks = false
    @State private var isDropTargeted = false

    var body: some View {
        Button {
            if !tasks.isEmpty {
                showsTasks.toggle()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isDropTargeted ? Color.blue.opacity(0.18) : Color.secondary.opacity(0.10))
                    .frame(height: 30)

                if let entry {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(.blue.opacity(isDropTargeted ? 0.36 : 0.28))
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                let progress = CGFloat(entry.completedCount) / CGFloat(max(entry.taskCount, 1))
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(.blue.opacity(0.52))
                                    .frame(width: max(8, proxy.size.width * progress))
                            }
                        }
                    Text("\(entry.taskCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                } else if isDropTargeted {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .help(entry.map { "\($0.projectName): \($0.completedCount)/\($0.taskCount) complete" } ?? "No tasks")
        .popover(isPresented: $showsTasks, arrowEdge: .bottom) {
            GanttTaskPopover(project: project, day: day, tasks: tasks, onToggleTask: onToggleTask)
        }
        .onDrop(of: [UTType.text], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let idString = object as? String, let id = UUID(uuidString: idString), let task = allTasks.first(where: { $0.id == id }) else {
                return
            }

            Task { @MainActor in
                onMoveTask(task, day)
            }
        }
        return true
    }
}

private struct GanttTaskPopover: View {
    let project: String
    let day: DateOnly
    let tasks: [TodoTask]
    let onToggleTask: (TodoTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(day.isoString) · \(tasks.count) todos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            LazyVStack(alignment: .leading, spacing: 7) {
                ForEach(tasks) { task in
                    GanttTaskRow(task: task, onToggle: { onToggleTask(task) })
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

private struct GanttTaskRow: View {
    let task: TodoTask
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.borderless)
            .help(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.callout.weight(.medium))
                    .strikethrough(task.isCompleted)
                    .lineLimit(3)

                HStack(spacing: 7) {
                    if let dueTime = task.dueTime {
                        Label(dueTime, systemImage: "clock")
                    }
                    Label(task.priority.ganttDisplayName, systemImage: task.priority.ganttSystemImage)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("Drag to another date")
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onDrag {
            NSItemProvider(object: task.id.uuidString as NSString)
        }
    }
}

private extension TaskPriority {
    var ganttDisplayName: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }

    var ganttSystemImage: String {
        switch self {
        case .low:
            "flag"
        case .medium:
            "flag.fill"
        case .high:
            "flag.2.crossed.fill"
        }
    }
}

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = Int(clean, radix: 16) else {
            self = .accentColor
            return
        }

        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
