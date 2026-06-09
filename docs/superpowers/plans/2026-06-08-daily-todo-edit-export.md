# Daily Todo Edit And Clipboard Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inline daily todo title editing and a one-click clipboard daily report with AI summary fallback.

**Architecture:** `TodoCore` owns persistence, export context construction, Markdown rendering, local fallback summaries, and the DeepSeek request/parser. `TodoApp` owns clipboard writing, async export state, toast/status messages, and compact SwiftUI controls in `StickyNoteView`.

**Tech Stack:** Swift 6, SwiftUI/AppKit, SQLite3, Swift Testing, DeepSeek chat completions.

---

### Task 1: Store Rename API

**Files:**
- Modify: `Sources/TodoCore/Stores/TodoStore.swift`
- Modify: `Tests/TodoCoreTests/TodoCoreTests.swift`

- [ ] Add tests that `renameTask(id:title:)` trims and updates only the title/updated timestamp while preserving metadata, and rejects empty titles.
- [ ] Add `TodoStore.renameTask(id:title:)` near the existing task update methods.
- [ ] Run `swift test --filter TodoCoreTests`.

### Task 2: Daily Export Core

**Files:**
- Modify: `Sources/TodoCore/Models/Models.swift`
- Create: `Sources/TodoCore/Services/DailyExportRenderer.swift`
- Create: `Tests/TodoCoreTests/DailyExportRendererTests.swift`

- [ ] Add daily export context/summary models.
- [ ] Add `DailyExportRenderer.context(date:tasks:projects:)`, `fallbackSummary(context:)`, and `markdown(context:summary:)`.
- [ ] Test grouping, deterministic fallback text, Markdown output details, and empty-day output.
- [ ] Run `swift test --filter DailyExportRendererTests`.

### Task 3: DeepSeek Daily Export Summarizer

**Files:**
- Create: `Sources/TodoCore/Services/DailyExportSummaryPrompt.swift`
- Create: `Sources/TodoCore/Services/DeepSeekDailyExportSummarizer.swift`
- Create: `Tests/TodoCoreTests/DeepSeekDailyExportSummarizerTests.swift`

- [ ] Add a strict JSON prompt for daily project summaries.
- [ ] Add `DailyExportSummarizingService` and `DeepSeekDailyExportSummarizer`.
- [ ] Test request construction, parser success, malformed JSON rejection, and empty API key rejection.
- [ ] Run `swift test --filter DeepSeekDailyExportSummarizerTests`.

### Task 4: AppModel Clipboard Flow

**Files:**
- Modify: `Sources/TodoApp/App/AppModel.swift`

- [ ] Import AppKit for `NSPasteboard`.
- [ ] Add `dailyExportSummarizer`, `isCopyingDailyExport`, `renameTask(_:to:)`, and `copyDailyExportToClipboard()`.
- [ ] Use AI summary when a key exists; otherwise fall back to local summary.
- [ ] Always copy a useful report unless pasteboard writing fails.
- [ ] Run `swift build`.

### Task 5: Today UI Controls

**Files:**
- Modify: `Sources/TodoApp/Views/StickyNoteView.swift`

- [ ] Add a toolbar export button with disabled/progress state.
- [ ] Pass `onRename` into `TaskRow`.
- [ ] Add inline title editing with save/cancel controls and hover edit affordance.
- [ ] Run `swift build`.

### Task 6: Full Verification

**Files:**
- No planned source edits unless verification finds issues.

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Inspect `git diff --check`.
- [ ] Summarize changed files and verification results.
