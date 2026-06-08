# Daily Todo Edit And Clipboard Export Design

## Purpose

AI planning creates useful daily todos, but generated titles sometimes need small human corrections after creation. The Today sticky note should let users rename a single daily todo without changing its project, date, priority, due time, completion state, or source.

Users also need a fast daily report. The Today sticky note should copy one Markdown-style report to the macOS clipboard. The report should group today's todos by project and, when a DeepSeek API key is available, include one AI-generated daily summary across those project groups.

## Approved Approach

Use the Today sticky note as the correction and export surface.

- Each todo row gets a compact rename affordance.
- Activating rename swaps the title text for a text field with save and cancel controls.
- Saving a non-empty changed title updates only that todo's `title` and `updated_at`.
- The Today toolbar gets a clipboard export action.
- Exporting copies a Markdown-style daily report to the clipboard.
- Exporting uses one DeepSeek call when possible and falls back to deterministic local summary text when the API key is missing or the call fails.

This intentionally does not add file export, export history, or multi-day reports.

## Data Model And Store

No schema migration is required.

`TodoStore` will add `renameTask(id:title:)`. The method trims whitespace, rejects empty titles, updates `tasks.title`, and refreshes `updated_at`.

The export feature will use existing `TodoTask` rows for `AppModel.today`. It should not persist generated daily summaries because the requested output target is the clipboard only.

## Daily Export Summary

Add daily export models and a summarizer in `TodoCore`:

- `DailyProjectExportContext`: one project group containing project name, task counts, completed tasks, incomplete tasks, and task metadata.
- `DailyExportContext`: date plus project groups.
- `DailyExportSummary`: generated summary bullets, keyed by project name.
- `DailyExportSummarizingService`
- `DeepSeekDailyExportSummarizer`

The DeepSeek prompt should request strict JSON only. The service should make a single chat completions request for the whole day, not one request per project. The output should be concise and avoid inventing work that is not present in tasks.

If AI summary generation is unavailable, the app should build local summary bullets such as `Project A: 2/3 complete, 1 item left.`

## Clipboard Report Format

The copied text should be readable after pasting into chat, docs, email, or notes:

```markdown
# 轻话日报 2026-06-08

## 总结
- Project A: ...
- Project B: ...

## To-Do 明细
### Project A
- [x] 09:00 Ship report
- [ ] High: Send invoice

### Project B
- [ ] Draft proposal
```

Task rows should include completion checkbox, due time when present, a priority label for high-priority tasks, and the task title. Projects should sort by active project order when possible, with unknown projects sorted by name.

## App Model

`AppModel` will expose:

- `renameTask(_ task: TodoTask, to title: String)`
- `copyDailyExportToClipboard() async`

`copyDailyExportToClipboard()` should:

1. Build the daily export context from `tasks`.
2. Try to load the API key.
3. If a key exists, call the daily export summarizer once.
4. If no key exists or the call fails, build local summary bullets.
5. Render the final Markdown text.
6. Write it to `NSPasteboard.general`.
7. Refresh toast/status with success or fallback information.

The app should still copy a useful report when today's task list is empty.

## UI Decisions

Keep the sticky note compact. Rename controls appear inline only for the row being edited, and hover actions remain lightweight.

The export button belongs in the existing toolbar near refresh/settings because it is a page-level action. Use a recognizable system clipboard/share icon and a tooltip like `Copy daily report`.

While export is running, disable the export button and show a progress indicator or alternate icon state so repeated clicks do not trigger multiple network calls.

## Error Handling

Validation and failure messages should follow existing toast/status conventions.

- Empty todo titles fail before store writes.
- Saving the same trimmed title is a no-op.
- Store update failures show `Rename failed`.
- Missing API key is not an export failure; the app copies a local-summary report.
- AI/network/parser failures are not export failures; the app copies a local-summary report and records a status message that AI summary was skipped.
- Clipboard write should show a failure toast only if the pasteboard operation cannot be completed.

## Testing

Core tests should cover:

- `renameTask(id:title:)` updates title and keeps project, date, priority, due time, completion state, and source unchanged.
- Empty todo rename targets are rejected.
- Daily export context groups tasks by project and computes completed/incomplete counts.
- Local fallback summary is deterministic.
- Markdown rendering includes the date, summary section, project headings, checkboxes, due times, high priority labels, and handles an empty day.
- DeepSeek daily export request and parser use strict JSON and reject malformed payloads.

Manual UI verification should cover:

- Rename a generated todo from the Today list and confirm it persists after refresh.
- Cancel a rename and confirm the old title remains.
- Copy a daily report with an API key configured.
- Copy a daily report without an API key and confirm local summary output is pasted.
