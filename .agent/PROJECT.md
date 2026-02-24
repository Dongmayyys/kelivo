# PROJECT: Kelivo
> 生成时间: 2026-02-13  |  最后更新: 2026-02-24

## 技术栈
- Runtime: Flutter (Dart SDK ^3.8.1)
- Framework: Flutter (Material 3 / Material You)
- Language: Dart
- Styling: Material Design 3 + DynamicColor + 自定义调色板 (ThemePalettes)
- Database: Hive (本地 NoSQL，含 `hive_generator` 代码生成)
- Package Manager: Flutter pub (pubspec.yaml)
- Monorepo: 无（但 `dependencies/` 目录包含数个本地修改的第三方包）

## 版本
- 当前: 1.1.8-beta.1+25
- License: AGPL-3.0

## 常用命令
- 安装依赖: `flutter pub get`
- 开发启动: `flutter run` (加 `-d windows`/`-d chrome`/`-d <device>` 指定平台)
- 构建: `flutter build apk` / `flutter build windows` / `flutter build ios`
- 构建 (仅 arm64): `flutter build apk --release --split-per-abi --target-platform android-arm64`
- 本地调试: `$env:JAVA_HOME = "C:\Program Files\Eclipse Adoptium\jdk-17.0.18.8-hotspot"; flutter run -d <device_id>`
- 测试: `flutter test`
- Lint: `flutter analyze`
- 代码生成 (Hive adapters): `flutter pub run build_runner build`
- 图标生成: `flutter pub run flutter_launcher_icons`

## 目录结构
- `lib/` → 全部 Dart 源码 (274 子项)
  - `lib/main.dart` → 应用入口，MultiProvider 挂载 17 个 ChangeNotifier
  - `lib/core/` → 核心层 (models / providers / services 三层)
    - `lib/core/models/` → 数据模型 (18 文件): conversation, chat_message, assistant, api_keys, world_book 等
    - `lib/core/providers/` → 状态管理 (16 ChangeNotifierProvider): settings, chat, mcp, tts, assistant, model 等
    - `lib/core/services/` → 业务服务: API 调用, chat 引擎, MCP, search (15 个搜索引擎适配), TTS, 备份, 网络等
  - `lib/features/` → 功能模块 (14 个), 每个含独立的 pages/widgets
    - `assistant/` → AI 助手管理
    - `chat/` → 聊天核心 UI
    - `home/` → 首页 (33 子项，最大模块)
    - `settings/` → 设置页
    - `mcp/` → MCP 工具集管理
    - `provider/` → AI 提供商配置
    - `search/` → 搜索功能
    - `backup/`, `model/`, `quick_phrase/`, `scan/`, `translate/`, `instruction_injection/`, `world_book/`
  - `lib/desktop/` → 桌面端特定 UI (46 子项): 导航栏, 系统托盘, 热键, 窗口管理
  - `lib/shared/` → 跨功能共享组件: responsive 布局, 通用 widgets, 动画, 对话框
  - `lib/theme/` → 主题系统: design_tokens, palettes (23KB 调色板), theme_factory, theme_provider
  - `lib/utils/` → 工具函数 (15 文件): 平台判断, Markdown 处理, 沙箱路径, 文件导入等
  - `lib/l10n/` → 国际化 (7 文件): 英文 + 中文简/繁 (.arb → 生成 dart)
  - `lib/icons/` → 自定义图标
  - `lib/secrets/` → 空目录（占位）
- `dependencies/` → 本地修改的第三方包 (101 子项): tray_manager, mcp_client, flutter_tts, permission_handler_windows
- `assets/` → 应用资源 (58 子项): icons, app_icon, mermaid.min.js, HTML 模板
- `android/`, `ios/`, `windows/`, `macos/`, `linux/`, `web/` → 各平台原生工程
- `test/` → 测试 (2 子项)
- `docx/` → 文档/截图
- `.github/` → CI/CD (6 个 workflow), Issue 模板, FUNDING

## 架构概要
Flutter 多平台 LLM 聊天客户端，采用 **Provider 模式** 进行状态管理。
核心采用 **三层架构**: `models`(数据定义) → `providers`(状态管理/业务逻辑) → `services`(IO/API/存储)。
UI 层按**功能模块**组织 (`features/`)，桌面端 (`desktop/`) 与移动端 (`features/home/`) 分离入口。
本地数据使用 **Hive** 嵌入式数据库，API 通信使用 **Dio/HTTP**。
支持 MCP (Model Context Protocol) 工具集成、12+ 搜索引擎、TTS 多后端。

## 核心概念
- **Provider**: 每个 ChangeNotifier 管理一个功能域的状态，通过 MultiProvider 在根部注入
- **SettingsProvider**: 最大的 Provider (132KB)，管理全部应用设置，包含代理、主题、字体、各种开关
- **ChatService**: 聊天核心引擎，管理对话和消息的创建/持久化
- **MessageBuilderService**: 构建发给 LLM 的完整消息列表，组合记忆/摘要/搜索/注入/世界书
- **ToolHandlerService**: 接收 LLM 返回的 tool_calls 并本地执行（记忆/MCP/搜索）
- **McpProvider / McpToolService**: MCP 协议客户端，管理工具服务器连接和函数调用
- **Assistant**: 可自定义的 AI 助手角色，含系统提示词和参数配置
- **Conversation / ChatMessage**: 对话和消息数据模型，使用 Hive 持久化（有 `.g.dart` 生成文件）
- **InstructionInjection / WorldBook**: 上下文注入机制，用于在对话中添加背景知识
- **ThemePalettes**: 预定义多套配色方案，支持 Material You 动态取色 (Android 12+)
- **SandboxPathResolver**: 处理 iOS 沙箱环境下的路径变化问题

## 代码约定
- 状态管理统一使用 `ChangeNotifierProvider`，在 `main.dart` 根部挂载
- 桌面端 (`desktop/`) 和移动端 (`features/home/`) 共享 `core/` 和 `shared/`，UI 分别实现
- 数据模型使用 Hive，需 `@HiveType` 注解 + `build_runner` 生成适配器
- 国际化使用 Flutter 官方 ARB 方案 (`l10n.yaml` + `flutter generate: true`)
- 本地修改的第三方包放在 `dependencies/` 目录，通过 `path:` 引用
- Lint 使用 `flutter_lints` 包，排除了 `dependencies/flutter_tts/`
- 错误处理广泛使用 `try/catch(_) {}` 静默模式（避免崩溃，但不记录）

## Git 约定
- 分支策略: upstream `origin/master` + 个人 fork `myfork/my-dev`，功能分支如 `fix/world-book-keyword-split-regex`
- Commit 格式: 中文，Conventional Commits 风格
  - `feat: 世界书关键词编辑 UI 优化`
  - `fix: 修复正则转义导致关键词拆分异常`
  - `chore: 添加 debug/release 共存配置`
- 上游 commit 格式较自由，有时单字母 (`f`) 或无 type 前缀

## 已有的规则文件
- 无 `.cursorrules` / `AGENTS.md` / `CLAUDE.md` 等额外规则文件
