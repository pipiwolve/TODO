# Project Archive Summary Design

## Goal

When a project is archived, the app should preserve a readable close-out record: completed work, completion statistics, related daily review notes, and an AI-generated summary. Users should open Archived Projects, select a project on the left, and inspect the archive detail on the right.

## Current Data Flow

Daily todos and the weekly Gantt chart are already connected. `TodoStore.timelineEntries(scope:anchor:)` aggregates rows from the `tasks` table by `COALESCE(project_name, 'Inbox')` and `date`. The Gantt chart is a derived view, not separate persisted timeline data.

Project archiving currently updates `projects.is_active = 0` and keeps historical tasks. This is the right foundation for archive summaries because no task history is deleted.

`daily_notes` are separate from the Gantt chart. They should not affect the Gantt aggregation, but archive summaries should include notes within the archived project's task date range as context for the AI summary and detail view.

## Product Shape

The existing Archived Projects window becomes a sidebar-detail archive browser.

Left pane:
- Archived project list.
- Project name.
- Completion ratio.
- Archived/generated date if a summary exists.

Right pane:
- AI summary at the top.
- Stats row: total tasks, completed tasks, incomplete tasks, completion rate, date span.
- Completed task list sorted by date and due time.
- Incomplete/leftover task list when present.
- Daily review excerpts from dates that overlap the project work.
- A regenerate summary action.

## Architecture

Add archive-specific models to `TodoCore`:
- `ProjectArchiveSummary`: persisted AI summary and deterministic stats.
- `ProjectArchiveTaskSnapshot`: task rows shown in the archive detail.
- `ProjectArchiveDailyNoteSnapshot`: daily note rows shown in the archive detail.
- `ProjectArchiveDetail`: composed object for the selected project.

Add a new `project_archive_summaries` SQLite table. `archiveProject(name:)` remains the operation that changes project state, but it also records an `archived_at` timestamp. Summary generation is a separate save operation so the UI can still archive if the network call fails.

Add an AI service:
- `ProjectArchiveSummarizingService`
- `DeepSeekArchiveSummarizer`

The summarizer receives a compact project archive context and returns strict JSON with:
- `summary`
- `outcomes`
- `risks`
- `nextSteps`

`AppModel.archiveProject(named:)` should:
1. Archive the project.
2. Refresh local lists.
3. If an API key exists, build archive context and generate/save an AI summary.
4. If the AI call fails, keep the archive and show a non-blocking status.

`AppModel.regenerateArchiveSummary(for:)` should re-run summary generation for a selected archived project.

## UI Decisions

Use a native macOS split layout rather than custom navigation. The archive window is a utility/detail window, not a landing page.

The left pane should stay lightweight and list-like. The right pane can use compact repeated cards for stats and task groups.

The feature should be useful without AI. If no generated summary exists, the detail view should show deterministic stats and task lists plus a small "Generate summary" action.

## Testing

Core tests should cover:
- Archiving records `archived_at`.
- Archive detail includes all tasks for a project after archiving.
- Archive detail separates completed and incomplete tasks.
- Archive detail includes daily notes within the project's task date span.
- Saving and replacing a generated archive summary persists correctly.
- DeepSeek archive summary request and parser use strict JSON and reject malformed payloads.

UI is verified by building the app. The data and summarizer behavior are covered in `TodoCoreTests`.
