import SwiftUI
import TodoCore

struct StickyNoteView: View {
    @Bindable var model: AppModel
    @State private var showsComposer = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            taskList
            if showsComposer {
                Divider()
                quickAdd
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastBanner(message: toast.message)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: model.toast)
        .animation(.snappy(duration: 0.22), value: showsComposer)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Today")
                    .font(.headline)
                Text(model.today.isoString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            compactToolbar
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private var compactToolbar: some View {
        HStack(spacing: 6) {
            Button {
                showsComposer.toggle()
            } label: {
                Image(systemName: showsComposer ? "plus.circle.fill" : "plus")
            }
            .buttonStyle(.borderless)
            .help(showsComposer ? "Hide add todo" : "Add todo")

            Button {
                model.togglePinned()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(model.isPinned ? "Pinned on top" : "Pin on top")

            Button {
                model.actions?.showCapture(model: model)
            } label: {
                Image(systemName: "sparkles")
            }
            .buttonStyle(.borderless)
            .help("Quick capture")

            Button {
                model.showTimeline()
            } label: {
                Image(systemName: "chart.bar.xaxis")
            }
            .buttonStyle(.borderless)
            .help("Open weekly timeline")

            Button {
                Task {
                    await model.copyDailyExportToClipboard()
                }
            } label: {
                if model.isCopyingDailyExport {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "doc.on.clipboard")
                }
            }
            .buttonStyle(.borderless)
            .disabled(model.isCopyingDailyExport)
            .help("Copy daily report")

            Button {
                model.showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if model.tasks.isEmpty {
                    ContentUnavailableView("No todos today", systemImage: "checklist", description: Text("Use Option-Command-S to plan your day."))
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(model.tasks) { task in
                        TaskRow(
                            task: task,
                            projects: model.projects,
                            onToggle: { model.toggle(task) },
                            onDelete: { model.delete(task) },
                            onRename: { title in
                                model.renameTask(task, to: title)
                            },
                            onMetadataChange: { projectName, priority, dueTime in
                                model.updateTaskMetadata(task, projectName: projectName, priority: priority, dueTime: dueTime)
                            }
                        )
                    }
                }
            }
            .padding(12)
        }
    }

    private var quickAdd: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Add todo", text: $model.draftTaskTitle)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        model.addManualTask()
                    }
                Button {
                    model.addManualTask()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Add todo")
            }

            HStack(spacing: 10) {
                ProjectWheel(projects: model.projects, selection: $model.draftProjectName)
                PriorityWheel(selection: $model.draftPriority)
                DueTimeWheel(selection: $model.draftDueTime)
                Spacer()
            }
            .font(.caption)
        }
        .padding(12)
    }
}

private struct ProjectWheel: View {
    let projects: [Project]
    @Binding var selection: String
    var compact = false

    var body: some View {
        PopoverButton {
            VStack(alignment: .leading, spacing: 6) {
                Text("Project")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(projects) { project in
                            MetadataOptionRow(
                                systemImage: "folder.fill",
                                text: project.name,
                                isSelected: project.name == selection
                            ) {
                                selection = project.name
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            .padding(10)
            .frame(width: 190)
        } label: {
            MetadataPill(systemImage: "folder.fill", text: selection, compact: compact)
        }
        .help("Project")
    }
}

private struct PriorityWheel: View {
    @Binding var selection: TaskPriority
    var compact = false

    var body: some View {
        PopoverButton {
            VStack(alignment: .leading, spacing: 6) {
                Text("Priority")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    MetadataOptionRow(
                        systemImage: priority.systemImage,
                        text: priority.displayName,
                        isSelected: priority == selection
                    ) {
                        selection = priority
                    }
                }
            }
            .padding(10)
            .frame(width: 150)
        } label: {
            MetadataPill(systemImage: selection.systemImage, text: selection.displayName, compact: compact)
        }
        .help("Priority")
    }
}

private struct DueTimeWheel: View {
    @Binding var selection: String?
    var compact = false

    @State private var hour = 9
    @State private var minute = 0

    var body: some View {
        PopoverButton {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    NumberScroller(title: "Hour", range: Array(0..<24), selection: $hour)

                    Text(":")
                        .font(.title3.monospacedDigit())

                    NumberScroller(title: "Minute", range: Array(0..<60), selection: $minute)
                }

                HStack {
                    Button("Clear") {
                        selection = nil
                    }
                    Spacer()
                    Button("Set") {
                        selection = String(format: "%02d:%02d", hour, minute)
                    }
                }
                .font(.caption)
            }
            .padding(12)
            .frame(width: 210)
        } label: {
            MetadataPill(systemImage: "clock", text: selection ?? "DDL", compact: compact)
        }
        .help("Due time")
        .onAppear {
            if let selection {
                let parts = selection.split(separator: ":").compactMap { Int($0) }
                if parts.count == 2 {
                    hour = parts[0]
                    minute = parts[1]
                }
            }
        }
    }
}

private struct MetadataPill: View {
    let systemImage: String
    let text: String
    var compact: Bool

    var body: some View {
        HStack(spacing: compact ? 3 : 5) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 8 : 10, weight: .medium))
                .frame(width: compact ? 9 : 12)
            Text(text)
                .font(.system(size: compact ? 9 : 10.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, compact ? 2 : 5)
        .padding(.vertical, compact ? 1 : 2)
        .background {
            if !compact {
                Color.secondary.opacity(0.12)
            }
        }
        .clipShape(Capsule())
        .contentShape(Rectangle())
    }
}

private struct MetadataOptionRow: View {
    @Environment(\.dismiss) private var dismiss

    let systemImage: String
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .frame(width: 14)
                Text(text)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? .blue.opacity(0.16) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct NumberScroller: View {
    let title: String
    let range: [Int]
    @Binding var selection: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(range, id: \.self) { value in
                            Button {
                                selection = value
                            } label: {
                                Text(String(format: "%02d", value))
                                    .font(.body.monospacedDigit())
                                    .frame(width: 58, height: 24)
                                    .background(value == selection ? .blue.opacity(0.18) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.plain)
                            .id(value)
                        }
                    }
                }
                .frame(width: 66, height: 118)
                .onAppear {
                    proxy.scrollTo(selection, anchor: .center)
                }
                .onChange(of: selection) { _, newValue in
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

private struct PopoverButton<LabelContent: View, PopoverContent: View>: View {
    @ViewBuilder var content: () -> PopoverContent
    @ViewBuilder var label: () -> LabelContent
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            label()
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            content()
        }
    }
}

private struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.caption.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

private struct TaskRow: View {
    let task: TodoTask
    let projects: [Project]
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let onMetadataChange: (String?, TaskPriority, String?) -> Void
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var draftTitle: String
    @State private var projectName: String
    @State private var priority: TaskPriority
    @State private var dueTime: String?

    init(task: TodoTask, projects: [Project], onToggle: @escaping () -> Void, onDelete: @escaping () -> Void, onRename: @escaping (String) -> Void, onMetadataChange: @escaping (String?, TaskPriority, String?) -> Void) {
        self.task = task
        self.projects = projects
        self.onToggle = onToggle
        self.onDelete = onDelete
        self.onRename = onRename
        self.onMetadataChange = onMetadataChange
        _draftTitle = State(initialValue: task.title)
        _projectName = State(initialValue: task.projectName ?? "个人工作")
        _priority = State(initialValue: task.priority)
        _dueTime = State(initialValue: task.dueTime)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .help(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    HStack(spacing: 6) {
                        TextField("Todo title", text: $draftTitle)
                            .textFieldStyle(.plain)
                            .font(.body.weight(.semibold))
                            .onSubmit(saveRename)
                        Button(action: saveRename) {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Save todo title")
                        Button(action: cancelRename) {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help("Cancel rename")
                    }
                } else {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .strikethrough(task.isCompleted)
                        .lineLimit(3)
                }
                HStack(spacing: 7) {
                    ProjectWheel(projects: projects, selection: Binding(get: {
                        projectName
                    }, set: { value in
                        projectName = value
                        onMetadataChange(value, priority, dueTime)
                    }), compact: true)
                    PriorityWheel(selection: Binding(get: {
                        priority
                    }, set: { value in
                        priority = value
                        onMetadataChange(projectName, value, dueTime)
                    }), compact: true)
                    DueTimeWheel(selection: Binding(get: {
                        dueTime
                    }, set: { value in
                        dueTime = value
                        onMetadataChange(projectName, priority, value)
                    }), compact: true)
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                .opacity(0.72)
            }

            Spacer(minLength: 4)

            Group {
                if isHovering {
                    HStack(spacing: 4) {
                        Button {
                            draftTitle = task.title
                            isRenaming = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Rename todo")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Delete todo")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .frame(width: 40, height: 18)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { isHovering = $0 }
        .onChange(of: task.title) { _, newValue in
            if !isRenaming {
                draftTitle = newValue
            }
        }
        .animation(.snappy(duration: 0.16), value: isHovering)
        .animation(.snappy(duration: 0.16), value: isRenaming)
    }

    private func saveRename() {
        let cleanTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        isRenaming = false
        onRename(cleanTitle)
    }

    private func cancelRename() {
        draftTitle = task.title
        isRenaming = false
    }
}

private extension TaskPriority {
    var displayName: String {
        switch self {
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }

    var systemImage: String {
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
