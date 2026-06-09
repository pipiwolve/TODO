import Foundation

public enum DailyExportSummaryPrompt {
    public static var system: String {
        """
        You write concise daily project summaries for a local macOS todo app.

        Create a daily summary from the provided project-grouped todo list.

        Output contract:
        - Return strict JSON only. Do not include markdown, prose, comments, or code fences.
        - Top-level key must be exactly bullets.
        - bullets: 1-8 concise strings, one per project when possible.
        - Each bullet should start with the project name followed by a colon.
        - Mention completed work and remaining work when present.
        - Do not invent work that is not present in tasks.
        """
    }

    public static func user(context: DailyExportContext) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(context)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
