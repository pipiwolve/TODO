import SwiftUI
import TodoCore

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
                GanttGrid(entries: model.timeline, anchor: model.today, onArchive: model.archiveProject, onDelete: model.deleteProject)
            }

            OverdueAlertsView(model: model)
        }
        .padding(18)
        .frame(minWidth: 680, minHeight: 460)
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
    let onArchive: (String) -> Void
    let onDelete: (String) -> Void

    private var days: [DateOnly] {
        (0..<7).map { anchor.addingDays($0) }
    }

    private var projects: [String] {
        Array(Set(entries.map(\.projectName))).sorted()
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
                        ProjectGanttRow(project: project, days: days, entry: entry(project:day:), onArchive: onArchive, onDelete: onDelete)
                    }
                }
            }
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func entry(project: String, day: DateOnly) -> TimelineEntry? {
        entries.first { $0.projectName == project && $0.date == day }
    }

    private func shortLabel(for day: DateOnly) -> String {
        "\(day.month)/\(day.day)"
    }
}

private struct ProjectGanttRow: View {
    let project: String
    let days: [DateOnly]
    let entry: (String, DateOnly) -> TimelineEntry?
    let onArchive: (String) -> Void
    let onDelete: (String) -> Void
    @State private var isHovering = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(project)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if isHovering {
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
                GanttCell(entry: entry(project, day))
            }
        }
    }
}

private struct GanttCell: View {
    let entry: TimelineEntry?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary.opacity(0.5))
                .frame(height: 30)

            if let entry {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.blue.opacity(0.28))
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
            }
        }
        .frame(maxWidth: .infinity)
        .help(entry.map { "\($0.projectName): \($0.completedCount)/\($0.taskCount) complete" } ?? "No tasks")
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
