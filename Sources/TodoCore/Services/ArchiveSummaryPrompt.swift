import Foundation

public enum ArchiveSummaryPrompt {
    public static var system: String {
        """
        You write concise archive summaries for a local macOS todo and Gantt app.

        Create an archive summary from the provided project tasks and daily review notes.

        Output contract:
        - Return strict JSON only. Do not include markdown, prose, comments, or code fences.
        - Top-level keys must be exactly summary, outcomes, risks, and nextSteps.
        - summary: one short paragraph describing what was completed and how the project ended.
        - outcomes: 1-5 concise completed outcomes.
        - risks: 0-5 concise risks, leftovers, or unresolved blockers.
        - nextSteps: 0-5 practical follow-up actions.
        - Do not invent work that is not present in tasks or notes.
        """
    }

    public static func user(context: ProjectArchiveContext) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(context)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
