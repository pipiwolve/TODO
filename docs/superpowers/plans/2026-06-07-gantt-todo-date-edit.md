# Gantt Todo Date Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users rename any project and correct a todo's date from the weekly Gantt view by clicking cells and dragging individual todos.

**Architecture:** Add transactional persistence APIs in `TodoStore`, expose them through `AppModel`, and enhance the existing SwiftUI Gantt components without changing the database schema. The Gantt grid will receive visible week tasks, open a cell popover for the selected project/date, and use SwiftUI drag/drop to move one todo at a time.

**Tech Stack:** Swift 6.1, SwiftPM, Swift Testing, SQLite3, macOS 14 SwiftUI.

---

## File Map

- `Tests/TodoCoreTests/TodoCoreTests.swift`: Add persistence regression tests for project renaming and task date moves.
- `Sources/TodoCore/Stores/TodoStore.swift`: Add `renameProject(from:to:)`, `moveTask(id:to:)`, and public `tasks(forProjectNamed:on:)` query support.
- `Sources/TodoApp/App/AppModel.swift`: Keep the visible week tasks in memory and expose rename/move actions.
- `Sources/TodoApp/Views/TimelineView.swift`: Wire Gantt cells to popovers, project rename UI, and drag/drop.

## Task 1: Store Tests

**Files:**
- Modify: `Tests/TodoCoreTests/TodoCoreTests.swift`

- [ ] **Step 1: Add failing tests**

Add these tests inside `TodoCoreTests` before `AI planning result is inserted as tasks and timeline snapshots`:

```swift
    @Test("projects can be renamed with tasks and archive summaries")
    func projectsCanBeRenamedWithTasksAndArchiveSummaries() throws {
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
        try store.saveProjectArchiveSummary(
            ProjectArchiveSummary(
                projectName: "Client Work",
                summary: "Finished client work.",
                outcomes: ["Report shipped"],
                risks: [],
                nextSteps: ["Send follow-up"],
                generatedAt: Date(timeIntervalSince1970: 100)
            )
        )

        try store.renameProject(from: "Client Work", to: "Renamed Client")

        #expect(try !store.archivedProjects().contains { $0.name == "Client Work" })
        #expect(try store.archivedProjects().contains { $0.name == "Renamed Client" })
        let renamedTask = try #require(store.tasks(on: DateOnly(year: 2026, month: 6, day: 7)).first)
        #expect(renamedTask.projectName == "Renamed Client")
        #expect(try store.projectArchiveDetail(name: "Client Work") == nil)
        let renamedDetail = try #require(store.projectArchiveDetail(name: "Renamed Client"))
        #expect(renamedDetail.summary?.summary == "Finished client work.")
        #expect(renamedDetail.summary?.nextSteps == ["Send follow-up"])
    }

    @Test("default projects can be renamed")
    func defaultProjectsCanBeRenamed() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        _ = try store.addTask(
            title: "Default task",
            date: DateOnly(year: 2026, month: 6, day: 7),
            priority: .medium,
            source: .manual,
            projectName: "Inbox"
        )

        try store.renameProject(from: "Inbox", to: "收件箱")

        #expect(try !store.projects().contains { $0.name == "Inbox" })
        #expect(try store.projects().contains { $0.name == "收件箱" })
        let task = try #require(store.tasks(on: DateOnly(year: 2026, month: 6, day: 7)).first)
        #expect(task.projectName == "收件箱")
    }

    @Test("project rename rejects blank and duplicate names")
    func projectRenameRejectsBlankAndDuplicateNames() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        _ = try store.addProject(name: "Client Work")
        _ = try store.addProject(name: "Other Work")

        #expect(throws: TodoStore.Error.self) {
            try store.renameProject(from: "Client Work", to: "   ")
        }
        #expect(throws: TodoStore.Error.self) {
            try store.renameProject(from: "Client Work", to: "Other Work")
        }
        #expect(try store.projects().contains { $0.name == "Client Work" })
        #expect(try store.projects().contains { $0.name == "Other Work" })
    }

    @Test("tasks can be moved between dates and timeline updates")
    func tasksCanBeMovedBetweenDatesAndTimelineUpdates() throws {
        let store = try TodoStore(path: temporaryDatabasePath())
        let sourceDate = DateOnly(year: 2026, month: 6, day: 8)
        let targetDate = DateOnly(year: 2026, month: 6, day: 7)
        let task = try store.addTask(
            title: "Correct misplaced todo",
            date: sourceDate,
            priority: .medium,
            source: .ai,
            projectName: "Todo App",
            dueTime: "10:30"
        )

        try store.moveTask(id: task.id, to: targetDate)

        #expect(try store.tasks(on: sourceDate).isEmpty)
        let moved = try #require(store.tasks(on: targetDate).first)
        #expect(moved.id == task.id)
        #expect(moved.date == targetDate)
        #expect(moved.projectName == "Todo App")
        #expect(moved.dueTime == "10:30")
        let entries = try store.timelineEntries(scope: .week, anchor: targetDate)
        #expect(entries.contains { $0.projectName == "Todo App" && $0.date == targetDate && $0.taskCount == 1 })
        #expect(!entries.contains { $0.projectName == "Todo App" && $0.date == sourceDate })
    }
```

- [ ] **Step 2: Run tests to verify RED**

Run: `swift test --filter TodoCoreTests`

Expected: FAIL because `TodoStore` has no `renameProject(from:to:)` or `moveTask(id:to:)`.

## Task 2: Store Implementation

**Files:**
- Modify: `Sources/TodoCore/Stores/TodoStore.swift`
- Test: `Tests/TodoCoreTests/TodoCoreTests.swift`

- [ ] **Step 1: Implement store APIs**

Add public methods after `deleteProject(name:)`:

```swift
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
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
```

Add public task query and date move methods near existing task update methods:

```swift
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
```

- [ ] **Step 2: Run store tests to verify GREEN**

Run: `swift test --filter TodoCoreTests`

Expected: PASS for the Todo core suite.

## Task 3: App Model Wiring

**Files:**
- Modify: `Sources/TodoApp/App/AppModel.swift`

- [ ] **Step 1: Add visible week task state and actions**

Add a stored property near `timeline`:

```swift
    var timelineTasks: [TodoTask] = []
```

In `refresh()`, after `timeline = ...`, load visible week tasks:

```swift
            timelineTasks = try store.allTasks(from: today, through: today.addingDays(6))
```

Add these methods after `updateTaskMetadata`:

```swift
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
```

- [ ] **Step 2: Build to verify model compiles**

Run: `swift build`

Expected: build succeeds.

## Task 4: Gantt UI

**Files:**
- Modify: `Sources/TodoApp/Views/TimelineView.swift`

- [ ] **Step 1: Pass model data/actions into GanttGrid**

Change the `GanttGrid` call in `TimelineView` to:

```swift
                GanttGrid(
                    entries: model.timeline,
                    anchor: model.today,
                    tasksForCell: model.tasks(forProject:on:),
                    onMoveTask: model.moveTask(_:to:),
                    onRenameProject: model.renameProject(from:to:),
                    onArchive: model.archiveProject,
                    onDelete: model.deleteProject
                )
```

- [ ] **Step 2: Update `GanttGrid` signature**

Add properties:

```swift
    let tasksForCell: (String, DateOnly) -> [TodoTask]
    let onMoveTask: (TodoTask, DateOnly) -> Void
    let onRenameProject: (String, String) -> Void
```

Pass them to `ProjectGanttRow`.

- [ ] **Step 3: Add drag payload type**

Add near the Gantt views:

```swift
private let todoTaskDragType = "com.qinghua.todo.task"
```

- [ ] **Step 4: Replace row header with editable project name**

In `ProjectGanttRow`, add `onRenameProject`, `@State private var isRenaming = false`, and `@State private var draftName = ""`. Render a compact text field with checkmark/xmark buttons while renaming, otherwise render the current title plus pencil/archive/trash controls.

- [ ] **Step 5: Add cell popover and drop handling**

Change `GanttCell` to accept:

```swift
    let project: String
    let day: DateOnly
    let entry: TimelineEntry?
    let tasks: [TodoTask]
    let onMoveTask: (TodoTask, DateOnly) -> Void
```

Add `@State private var showsTasks = false`. Wrap the cell in a button/popover when `tasks` is not empty, and add `.onDrop(of: [todoTaskDragType], isTargeted: nil)` that decodes a UUID string and finds it in `tasks` from the source model data passed to the grid.

- [ ] **Step 6: Add task popover row**

Create `GanttTaskPopover` and `GanttTaskRow` views. `GanttTaskRow` should use:

```swift
        .onDrag {
            NSItemProvider(object: task.id.uuidString as NSString)
        }
```

and show title, completion icon, due time, and priority.

- [ ] **Step 7: Build to catch SwiftUI type errors**

Run: `swift build`

Expected: build succeeds.

## Task 5: Final Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run full tests**

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 2: Run full build**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 3: Inspect diff**

Run: `git diff --stat && git diff -- Sources/TodoCore/Stores/TodoStore.swift Sources/TodoApp/App/AppModel.swift Sources/TodoApp/Views/TimelineView.swift Tests/TodoCoreTests/TodoCoreTests.swift`

Expected: diff contains only Gantt date editing, project rename, and tests.
