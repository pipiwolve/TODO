# Gantt Todo Date Editing Design

## Purpose

The current app makes two common corrections difficult: projects cannot be renamed, and a todo date chosen by AI planning cannot be changed after creation. The Gantt view should become the correction surface for both problems because it already shows project/date relationships.

## Approved Approach

Use the existing weekly Gantt view as an inline management surface.

- Every project name, including `Inbox` and `个人工作`, can be renamed from the Gantt row header.
- Clicking a populated Gantt day cell opens a popover with that project's todos for that date.
- Each todo in the popover can be dragged onto another day cell in the same weekly grid.
- Dropping a todo on a day cell changes only that todo's `date`.

This intentionally supports single-todo movement only. Whole-cell or bulk movement is out of scope for this version.

## Data Model And Store

No schema migration is required.

`TodoStore` will add two atomic write methods:

- `renameProject(from:to:)`
- `moveTask(id:to:)`

`renameProject(from:to:)` will run in a transaction and update:

- `projects.name`
- `tasks.project_name`
- `project_archive_summaries.project_name`

The method trims whitespace, rejects an empty target name, and relies on the existing unique project name constraint to prevent duplicate names. Because the current model links tasks by project name strings, keeping this operation transactional is required to preserve active tasks and archive history.

`moveTask(id:to:)` updates `tasks.date` and `updated_at`. It does not change project, priority, due time, completion state, or source.

## App Model

`AppModel` will expose:

- `renameProject(from:to:)`
- `moveTask(_ task: TodoTask, to date: DateOnly)`
- a way to fetch tasks for a project/date cell, either through a new model helper or by storing the visible week tasks in memory.

After each successful edit, `refresh()` runs so today's sticky list, overdue alerts, and the Gantt grid remain consistent. Toasts should be short: `Project renamed`, `Date updated`, and failure variants.

## Gantt UI

`TimelineView` keeps the existing compact window layout.

`GanttGrid` receives enough data/actions to:

- show each day cell as a click target when it contains tasks,
- open a popover anchored to the cell,
- display the cell's todos with title, due time, priority, and completion state,
- expose each todo as a draggable item,
- accept a dropped todo on any visible day cell and call the model move action.

The row header gains a small edit affordance next to the project name. When activated, it switches to a compact text field with save/cancel controls. Renaming to the same trimmed name is a no-op.

Empty cells can still act as drop targets. This lets a todo be moved to a date that currently has no tasks.

## Error Handling

Validation errors are surfaced through the existing `statusMessage` and toast patterns.

- Empty project names fail before store writes.
- Duplicate project names fail from SQLite and show a generic rename failure.
- Dropping a todo on its existing date is ignored.
- If a dragged todo is stale or missing, the move fails gracefully and refreshes the view.

## Testing

Core tests should cover:

- renaming a project updates the project row, active tasks, and archive summary lookup,
- all projects, including the existing default projects, can be renamed,
- duplicate or empty rename targets are rejected,
- moving a todo changes which date query returns it,
- moving a todo updates timeline entries.

Manual UI verification should cover:

- project rename from the Gantt row header,
- clicking a populated cell opens the todo popover,
- dragging one todo from tomorrow to today moves only that todo,
- dropping onto an empty day cell creates a new Gantt entry after refresh,
- today's sticky note list updates when a task is moved into or out of today.
