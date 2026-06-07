# 轻话

轻话是一个本地 macOS 便签式 To-do 应用。它用自然语言快速捕捉工作，把内容拆成每日任务，并按项目聚合到轻量甘特图中。项目完成后可以归档，查看完成任务、每日复盘摘录和 AI 生成的归档总结。

## 功能

- 今日便签：查看、添加、完成、删除当天任务。
- 快速捕捉：输入自然语言，让 DeepSeek 拆分成任务。
- 项目管理：任务可归属项目，并在甘特图中按日期聚合。
- 时间管理：任务支持优先级和截止时间。
- 逾期提醒：显示今天之前未完成的任务。
- 项目归档：归档后保留历史，并可生成项目总结。
- 项目删除：在甘特图项目行悬停后可删除项目及其任务，默认项目受保护。
- 菜单栏入口：启动后可以从菜单栏打开便签、捕捉窗口、甘特图和设置。

## 快捷键

- `Option + Command + G`：全局唤醒主便签。
- `Option + Command + S`：全局打开 Quick Capture。
- `Command + Shift + N`：应用激活时打开 Quick Capture。
- `Command + Shift + G`：应用激活时打开 Timeline。

## 本地运行

```bash
./script/build_and_run.sh
```

这个命令会构建 SwiftPM 项目，生成 `dist/TodoSticky.app`，并启动应用。

可用模式：

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
```

## 安装到应用列表

不需要上架 App Store。运行：

```bash
./script/install_app.sh
```

脚本会安装到：

```text
~/Applications/轻话.app
```

安装后可以从 Finder、Spotlight、Launchpad 或 Dock 打开。你也可以把 `~/Applications/轻话.app` 拖到 Dock 里固定。

## AI 配置

应用使用 DeepSeek API 做任务规划和项目归档总结。启动后打开 Settings，填入 DeepSeek API Key。

API Key 存在 macOS Keychain 中，不会写入项目文件或迁移包。

## 数据位置

本地数据存在：

```text
~/Library/Application Support/TodoSticky/todo.sqlite
```

这包含任务、项目、每日复盘、归档项目和归档总结。

## 迁移到另一台电脑

推荐流程：

1. 在旧电脑导出 `todo.sqlite`。
2. 在新电脑 clone 仓库。
3. 运行 `./script/install_app.sh` 安装应用。
4. 把旧电脑的数据库复制到新电脑的应用数据目录。
5. 在新电脑 Settings 中重新填写 DeepSeek API Key。

数据库目标路径：

```text
~/Library/Application Support/TodoSticky/todo.sqlite
```

导入前建议先退出应用，并备份新电脑已有的 `todo.sqlite`。

## 开发

运行测试：

```bash
swift test
```

构建：

```bash
swift build
```

## 技术栈

- Swift 6
- SwiftUI / AppKit
- SQLite3
- Swift Testing
- DeepSeek Chat Completions
