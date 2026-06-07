# Project Archive Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an archive browser that shows completed project work, deterministic archive stats, related daily notes, and an AI-generated project close-out summary.

**Architecture:** Store archive summaries separately from tasks so project history remains the source of truth. Compose archive detail from existing `tasks`, `daily_notes`, `projects`, and the new `project_archive_summaries` table. Add a DeepSeek summary service and wire it into the existing `AppModel` archive flow as a non-blocking enhancement.

**Tech Stack:** Swift 6, SwiftUI, SQLite3, Swift Testing, URLSession, DeepSeek chat completions.

---

## File Structure

- Modify `Sources/TodoCore/Models/Models.swift`: add archive summary/detail models and AI summary payload models.
- Modify `Sources/TodoCore/Stores/TodoStore.swift`: add migration, archived timestamp, archive detail queries, and summary save/load.
- Create `Sources/TodoCore/Services/ArchiveSummaryPrompt.swift`: prompt for archive summarization.
- Create `Sources/TodoCore/Services/DeepSeekArchiveSummarizer.swift`: DeepSeek request/response implementation.
- Modify `Sources/TodoApp/App/AppModel.swift`: add archive detail state, selected archive project, archive generation actions, and non-blocking archive summarization.
- Modify `Sources/TodoApp/App/AppDelegate.swift`: widen archived project window.
- Modify `Sources/TodoApp/Views/TimelineView.swift`: replace simple archive list with sidebar-detail archive browser.
- Modify `Tests/TodoCoreTests/TodoCoreTests.swift`: storage and detail tests.
- Create `Tests/TodoCoreTests/DeepSeekArchiveSummarizerTests.swift`: request and parser tests.

## Tasks

### Task 1: Persist Archive Detail Data

**Files:**
- Modify: `Tests/TodoCoreTests/TodoCoreTests.swift`
- Modify: `Sources/TodoCore/Models/Models.swift`
- Modify: `Sources/TodoCore/Stores/TodoStore.swift`

- [ ] Write failing tests for archive detail composition and summary persistence.
- [ ] Run `swift test --filter TodoCoreTests/archive` and confirm failure because APIs do not exist.
- [ ] Add archive models.
- [ ] Add SQLite migration columns/table.
- [ ] Add `projectArchiveDetail(name:)` and `saveProjectArchiveSummary(_:)`.
- [ ] Run targeted tests and confirm pass.

### Task 2: Add DeepSeek Archive Summarizer

**Files:**
- Create: `Sources/TodoCore/Services/ArchiveSummaryPrompt.swift`
- Create: `Sources/TodoCore/Services/DeepSeekArchiveSummarizer.swift`
- Create: `Tests/TodoCoreTests/DeepSeekArchiveSummarizerTests.swift`

- [ ] Write failing tests for request JSON and response parsing.
- [ ] Run targeted summarizer tests and confirm failure because types do not exist.
- [ ] Implement prompt, protocol, request builder, and parser.
- [ ] Run targeted summarizer tests and confirm pass.

### Task 3: Wire App State and Archive Actions

**Files:**
- Modify: `Sources/TodoApp/App/AppModel.swift`
- Modify: `Sources/TodoApp/App/AppDelegate.swift`

- [ ] Add archive detail state and selected archived project state.
- [ ] Add `loadArchiveDetail`, `selectArchivedProject`, `generateArchiveSummary`, and `regenerateArchiveSummary`.
- [ ] Update `archiveProject(named:)` to archive first, then attempt AI summary generation when an API key exists.
- [ ] Widen the archive window to support split detail.
- [ ] Run `swift test`.

### Task 4: Build Archive Browser UI

**Files:**
- Modify: `Sources/TodoApp/Views/TimelineView.swift`

- [ ] Replace simple `ArchivedProjectsPanel` list with two-pane browser.
- [ ] Add sidebar rows with completion counts.
- [ ] Add detail summary, stats, completed task list, incomplete task list, and daily note excerpts.
- [ ] Add Generate/Regenerate button connected to `AppModel`.
- [ ] Run `swift build`.

### Task 5: Final Verification

**Files:**
- All touched files.

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Review `git diff`.
- [ ] Report changed files, verification output, and any residual risks.
