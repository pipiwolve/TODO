import Foundation

public enum DailyExportRenderer {
    public static func context(date: DateOnly, tasks: [TodoTask], projects: [Project]) -> DailyExportContext {
        let projectOrder = Dictionary(uniqueKeysWithValues: projects.enumerated().map { ($0.element.name, $0.offset) })
        let groupedTasks = Dictionary(grouping: tasks) { task in
            task.projectName ?? "Inbox"
        }
        let contexts = groupedTasks.map { projectName, projectTasks in
            let exportTasks = projectTasks.map(DailyExportTask.init(task:)).sorted()
            let completedTasks = exportTasks.filter(\.isCompleted)
            let incompleteTasks = exportTasks.filter { !$0.isCompleted }
            return DailyProjectExportContext(
                projectName: projectName,
                totalTaskCount: exportTasks.count,
                completedTaskCount: completedTasks.count,
                incompleteTaskCount: incompleteTasks.count,
                completedTasks: completedTasks,
                incompleteTasks: incompleteTasks
            )
        }
        .sorted { lhs, rhs in
            switch (projectOrder[lhs.projectName], projectOrder[rhs.projectName]) {
            case let (lhsIndex?, rhsIndex?):
                lhsIndex < rhsIndex
            case (_?, nil):
                true
            case (nil, _?):
                false
            case (nil, nil):
                lhs.projectName < rhs.projectName
            }
        }

        return DailyExportContext(date: date, projects: contexts)
    }

    public static func fallbackSummary(context: DailyExportContext) -> DailyExportSummary {
        guard !context.projects.isEmpty else {
            return DailyExportSummary(bullets: ["今天暂无 To-Do。"])
        }

        let bullets = context.projects.map { project in
            let leftover = project.incompleteTaskCount == 0 ? "无剩余事项" : "\(project.incompleteTaskCount) 项待推进"
            return "\(project.projectName): \(project.completedTaskCount)/\(project.totalTaskCount) 完成，\(leftover)。"
        }
        return DailyExportSummary(bullets: bullets)
    }

    public static func markdown(context: DailyExportContext, summary: DailyExportSummary) -> String {
        var lines: [String] = [
            "# 轻话日报 \(context.date.isoString)",
            "",
            "## 总结"
        ]

        let bullets = summary.bullets.isEmpty ? fallbackSummary(context: context).bullets : summary.bullets
        lines += bullets.map { "- \($0)" }
        lines += ["", "## To-Do 明细"]

        if context.projects.isEmpty {
            lines.append("- 今天暂无 To-Do。")
            return lines.joined(separator: "\n")
        }

        for project in context.projects {
            lines += ["", "### \(project.projectName)"]
            lines += project.tasks.map(taskLine)
        }

        return lines.joined(separator: "\n")
    }

    private static func taskLine(_ task: DailyExportTask) -> String {
        var parts: [String] = ["-", task.isCompleted ? "已完成" : "未完成"]
        if let dueTime = task.dueTime {
            parts.append(dueTime)
        }
        if task.priority == .high {
            parts.append("高优先级:")
        }
        parts.append(task.title)
        return parts.joined(separator: " ")
    }
}
