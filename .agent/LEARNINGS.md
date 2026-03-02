# LEARNINGS
> 最后更新: 2026-03-02

## 开发范围

- **只关心安卓端**：修改代码时不要连带改桌面端（`lib/desktop/`）、iOS、Web 等不使用的平台。多改文件 = 多 rebase 冲突成本，收益为零
- **性能疑虑以 release 为准**：debug 模式下动画/滚动/布局比 release 慢 5-10 倍，不要在 debug 下做性能优化判断。功能逻辑 bug 才值得在 debug 下排查
- **禁止 `.agent/` 与代码混合提交**：`.agent/` 是本地个人文档，绝不能混进代码 commit。PR 时从 `upstream/master` checkout 干净分支 → cherry-pick 目标 commit → push 到 origin → 在 GitHub 发起 PR。`.agent/` 的变更单独 commit 或暂不提交

## 架构与设计决策

- System Message 内部拼接顺序：角色设定 → 记忆(`<memories>`) → 摘要(`<recent_chats>`) → 搜索说明 → 指令注入，全部通过 `_appendToSystemMessage` 追加到同一个 system message。世界书的 `beforeSystemPrompt`/`afterSystemPrompt` 位置也会修改该 system message
- 完整注入管线时序（`prepareApiMessagesWithInjections`）：`buildApiMessages`(历史) → Regex替换(assistant) → `processUserMessagesForApi`(文档/OCR/消息模板) → `injectSystemPrompt` → `injectMemoryAndRecentChats` → `injectSearchPrompt` → `injectInstructionPrompts` → `injectWorldBookPrompts`(5种位置) → **`resolveInjectedPlaceholders`**（统一占位符解析，只处理 role==system） → `applyContextLimit` → `inlineLocalImages`。世界书条目按 position 分 5 种注入位置：beforeSystemPrompt / afterSystemPrompt（合入system）、topOfChat（首条user前）、bottomOfChat（末条消息前）、atDepth（从末尾倒数N条处）
- 占位符系统设计：统一语法 `{key}` / `{key:param}`，所有注入渠道共享同一套变量。Message Template 保持独立语法 `{{ key }}`（用途不同且改动会破坏兼容性）。占位符只在 `role==system` 消息中解析，避免误替换用户聊天内容。世界书 entry 在插入前单独解析（因为部分位置不是 system role）
- 记忆功能使用 Function Calling 协议实现（`create_memory`/`edit_memory`/`delete_memory`），AI 自主决定是否调用，Kelivo 本地执行并存入 SharedPreferences
- Prompt 中引导 AI "相似或相关的记忆应合并为一条记录"，导致实际使用中 AI 只维护一条汇总型记忆条目
- 对话摘要每 5 条新消息触发一次，使用增量策略（旧摘要 + 新 user 消息 → 新摘要），限制 100 字以内
- 世界书注入时机：`injectWorldBookPrompts` 在 AI 生成之前调用，`apiMessages` 只含历史对话+当前用户消息，不含本次 AI 回复
- 世界书持久化选择 `ChatMessage.metadataJson`（通用元数据字段）而非 `toolEvents`（伪工具事件）。后者语义污染 tool 管道，导致多处需硬编码过滤 `worldbook_inject`。metadataJson 结构为 `{worldBook: {count, entries}}`，未来可扩展存储其他 per-message 元数据
- 备份完整性：`DataSync.prepareBackupFile` 导出 SharedPreferences 全量 snapshot（仅排除 5 个窗口状态 key）+ chats.json（含 toolEvents/geminiThoughtSigs）+ upload/ + images/ + avatars/，迁移签名不同的自编译版时数据无损
- Debug/Release 共存方案：`build.gradle.kts` 中 debug buildType 设置 `applicationIdSuffix = ".dev"`，debug 版包名为 `com.psyche.kelivo.dev`，与正式版 `com.psyche.kelivo` 共存互不干扰。`AndroidManifest.xml` 的 `android:label` 改为 `@string/app_name` 资源引用，debug 显示 "Kelivo (Dev)"、release 显示 "Kelivo"
- `main.dart` 的 `MaterialApp.title` 会在运行时通过 `Activity.setTaskDescription()` 覆盖 Manifest 的 app_name，导致多任务界面不显示 debug 后缀。已用 `kDebugMode` 三元表达式修复。桌面图标/系统设置仍读 Manifest（安装时写入，Flutter 碰不到）
- `ChatApiService` 各后端对 system 消息的转换：OpenAI Chat Completions 原样保留 `role: system`；Responses API 提取为顶层 `instructions`；Anthropic 提取为顶层 `system`；Gemini 原生 API 使用 `systemInstruction` 字段（上游已合入修复）
- `ChatApiService` 上游已拆分为 provider 子文件（`part of` 模式）：`claude_official.dart`、`google_common.dart`、`google_gemini.dart`、`google_vertex.dart`、`openai_common.dart`、`openai_chat_completions.dart`、`openai_responses.dart`。同时新增 `model_types.dart`（ModelInfo 提取到独立文件）、`model_override_payload_parser.dart`、`model_override_resolver.dart` 集中化 override 逻辑。改代码时注意对应到正确的 provider 文件
- Claude 推理强度 UI 映射：Off=0, Auto=-1, Light=1024, Medium=16000, Heavy=32000。"自动"(-1) 在 Claude 4.6 模型发送 `thinking.type: 'adaptive'`（模型自行决定是否/如何思考），在老版本 Claude 发送 `'enabled'` 且不带 budget（由 API 默认分配）
- 上游多次拆分大文件：`assistant_settings_edit_page.dart`（6000+ 行）→ 6 个 `part` 文件；`desktop_settings_page.dart`（10000+ 行）→ 4 个 pane 文件；`chat_api_service.dart`（6000+ 行）→ 7 个 provider 文件。rebase 时涉及这些文件的改动需手动适配到新位置
- Token 统计完全依赖 API 返回的 `usage` 字段，无本地 tokenizer。`TokenUsage`（纯内存类）在流式中对 prompt/completion 各自取 max，然后 `total = prompt + completion` 自己算（不用 API 原始 total），这是对多后端流式 chunk 报告不一致的防御策略。最终只有 `ChatMessage.totalTokens`（`int?`）通过 Hive 持久化，prompt/completion 分项不保留
- 消息编辑"保存并发送"：`appendMessageVersion` 在同一 `groupId` 下创建新版本（不覆盖原消息），UI 通过版本切换器浏览历史。对 assistant 消息使用 `assistantAsNewReply: true` 走 `regenerateAtMessage`，以编辑后内容为历史上下文生成新回复。**没有额外的"续写"prompt**——API 收到以编辑后的 assistant 消息结尾的对话，模型自行决定行为

## 代码陷阱与注意事项

- `features/home/services/message_builder_service.dart:611`: `RegExp(keyword, caseSensitive: ...)` 未传 `multiLine: true`，导致正则中 `^` 只匹配上下文字符串的开头而非每行开头
- `world_book_page.dart:keywordChip`: 长关键词溢出已修复（`c8d59dd`）——用 `Flexible` + `TextOverflow.ellipsis` 包裹文本
- `scroll_controller.dart`: 8 秒自动滚动延迟实际功能鸡肋——Timer 结束后只设置标志位不触发滚动；AI 输出期间 `maxScrollExtent` 增长极快会迅速超出 56px 阈值
- `chat_api_service.dart`: Gemini 3 Pro 只支持 `thinkingLevel: 'low' | 'high'`；Flash 支持 `'minimal' | 'low' | 'medium' | 'high'`；UI 5 档在 Pro 上多对一降级
- `memory_store.dart`: SharedPreferences 存储全部记忆（JSON），有容量限制 (~1MB)，每次全量读写
- `chat_input_bar.dart:1417`: 移动端回车发送通过 `textInputAction: TextInputAction.send` 实现
- `ChatController._messages` 与 `ChatService._messagesCache` 是**两套独立的消息引用**。`chatService.updateMessage()` 只更新 Hive + cache 并 `notifyListeners()`，但 `ChatController._messages` 不会自动同步。必须手动调用 `chatController.updateMessageInList()` 才能让 widget 立即看到变更（如 metadataJson），否则要切换对话重新加载才生效
- Hive 模型加字段需要 `build_runner` 重新生成 `.g.dart` 序列化代码。热重载（`r`）不会重新注册 TypeAdapter，必须热重启（`R`）才能生效
- `build_runner` 的 analyzer 版本可能不兼容当前 SDK（如 `0x14_000000` 数字分隔符语法报错），但不影响目标文件的代码生成，可忽略
- Hive `@HiveField(N)` 编号只能递增，**不能重用或修改已有编号**。新增字段对旧数据自动兼容（读出来是 `null`）
- 旧消息中存在 `worldbook_inject` 伪 tool event（迁移前写入），`chat_message_widget.dart` 和 `message_export_sheet.dart` 中的过滤仍需保留，否则旧消息会渲染出多余的工具调用卡片


## 模块间关系

- `MessageBuilderService` → `MemoryProvider` + `ChatService` + `InstructionInjectionProvider` + `WorldBookProvider`: 构建发给 LLM 的完整消息列表
- `ToolHandlerService` → `MemoryProvider` + `McpProvider` + `SearchToolService`: 接收 LLM 返回的 tool_calls 并本地执行
- `HomeViewModel._maybeGenerateSummaryFor` → `ChatApiService.generateText`: 摘要生成走独立 LLM 调用
- `main.dart:_selectHome()` → `DesktopHomePage` / `HomePage`: 移动端与桌面端 UI 的分叉入口，共享 `core/` + `shared/`（~72%），各自独立 UI 壳（~28%）

## 环境与工具

- fork 仓库 CI：自编译 APK 签名与官方版不同，Android 不允许不同签名覆盖安装，切换版本需备份 → 卸载 → 安装 → 恢复
- GitHub Actions 构建 Android arm64：`flutter build apk --release --split-per-abi --target-platform android-arm64` 只编译 arm64 架构，时间和产物体积均为全架构的 1/3。`build-my-dev.yml` 仅配置了 `workflow_dispatch`，push 不会自动触发编译。**注意**：分支已从 `my-dev` 迁移到 `master`，CI workflow 文件名和触发分支可能需要同步更新
- **上游 PR 行为**：维护者倾向于不直接 merge PR，而是自己重写相同修复后提交（如 systemInstruction 修复和 chip 溢出修复均如此）。rebase 时 Git 会自动跳过这些已被上游覆盖的 commit
- 本地开发环境路径：Flutter SDK `D:\develop\flutter`、Android SDK `D:\develop\Android\Sdk`、JDK 17 `D:\develop\jdk-17`（绿色版，从 Adoptium MSI 迁移）
- Android SDK 无需安装 Android Studio：下载 "Command line tools only" zip，用 `sdkmanager` 安装 `platform-tools` + `platforms;android-36` + `build-tools;35.0.0` + `ndk;27.0.12077973`
- Gradle 8.12 需要 JDK 17 LTS，通过用户级环境变量 `JAVA_HOME = D:\develop\jdk-17` 指定（绿色版，直接复制文件夹即可使用，不依赖注册表和 PATH）
- F5 调试（DAP 协议）比终端 `flutter run` 多了保存自动热重载、断点、变量查看；原生配置（Manifest/Gradle）变更需全量重编译，Dart 代码改动秒级热重载
- **本地 release 编译**：首次约 15 分钟，增量约 1-3 分钟（别跑 `flutter clean`）。CI 每次全量约 10 分钟，无法增量
- **本地 release 签名**：Android 16 对 release APK 严格验证证书，debug keystore 无法通过。已用 `keytool` 生成专用 release keystore（`~/.android/my-release-key.jks`），通过 `android/key.properties` 引用。`key.properties` 通过 `.git/info/exclude` 排除
- 调试手机：荣耀 Magic7 Pro (PTP-AN10)，Android 16 (API 36)，arm64。**USB 模式需选 RNDIS 才能被 ADB 检测到**（MTP/PTP 均不行，荣耀特殊行为）
- `.vscode/launch.json` 需指定 `type: dart`，否则 F5 可能被 Go 扩展抢占。`.vscode/` 通过 `.git/info/exclude` 本地排除
- **不主动跑 `flutter analyze`**：IDE 内置 Dart Analysis Server 实时报错，终端再跑一遍纯属冗余。除非用户明确要求，否则改完代码直接交付
- **l10n 工作流**：新增 UI 文字需编辑 4 个 arb 文件（`app_en.arb` + `app_zh.arb` + `app_zh_Hans.arb` + `app_zh_Hant.arb`），然后跑 `flutter gen-l10n` 生成 Dart 代码。代码中通过 `l10n.keyName()` 引用

## 已尝试但放弃的方案

- 自动滚动设计：Kelivo 的 Timer + 位置检测方案不如"用户意图状态机"（`shouldFollowRef`），后者基于用户主动滚回底部来恢复跟随，更符合直觉
- 世界书关键词正则 PR (`9503d80`)：上游已在 `2c80164` 合并了更激进方案（完全简化 `_parseKeywordInput`，移除逗号/分号分隔），rebase 时按上游版本解决冲突，该 commit 被自动跳过
- `PROCESS_TEXT` intent-filter（`ad139ef`）：已从 Manifest 中移除以减少系统文本选择工具栏的混乱。Kotlin 代码（`MainActivity.kt`）保留不删，降低上游 rebase 冲突风险（"软关闭"策略）
