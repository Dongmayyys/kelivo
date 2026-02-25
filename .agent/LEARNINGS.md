# LEARNINGS
> 最后更新: 2026-02-25

## 架构与设计决策

- System Prompt 注入顺序：角色设定 → 记忆(`<memories>`) → 摘要(`<recent_chats>`) → 搜索说明 → 指令注入，全部通过 `_appendToSystemMessage` 追加到同一个 system message
- 记忆功能使用 Function Calling 协议实现（`create_memory`/`edit_memory`/`delete_memory`），AI 自主决定是否调用，Kelivo 本地执行并存入 SharedPreferences
- Prompt 中引导 AI "相似或相关的记忆应合并为一条记录"，导致实际使用中 AI 只维护一条汇总型记忆条目
- 对话摘要每 5 条新消息触发一次，使用增量策略（旧摘要 + 新 user 消息 → 新摘要），限制 100 字以内
- 世界书注入时机：`injectWorldBookPrompts` 在 AI 生成之前调用，`apiMessages` 只含历史对话+当前用户消息，不含本次 AI 回复
- 备份完整性：`DataSync.prepareBackupFile` 导出 SharedPreferences 全量 snapshot（仅排除 5 个窗口状态 key）+ chats.json（含 toolEvents/geminiThoughtSigs）+ upload/ + images/ + avatars/，迁移签名不同的自编译版时数据无损
- Debug/Release 共存方案：`build.gradle.kts` 中 debug buildType 设置 `applicationIdSuffix = ".dev"`，debug 版包名为 `com.psyche.kelivo.dev`，与正式版 `com.psyche.kelivo` 共存互不干扰。`AndroidManifest.xml` 的 `android:label` 改为 `@string/app_name` 资源引用，debug 显示 "Kelivo (Dev)"、release 显示 "Kelivo"
- `main.dart` 的 `MaterialApp.title` 会在运行时通过 `Activity.setTaskDescription()` 覆盖 Manifest 的 app_name，导致多任务界面不显示 debug 后缀。已用 `kDebugMode` 三元表达式修复。桌面图标/系统设置仍读 Manifest（安装时写入，Flutter 碰不到）

## 代码陷阱与注意事项

- `world_book_page.dart:_parseKeywordInput`: raw string `r'[\\n,，;；]'` 中 `\\` 被 RegExp 解释为字面反斜杠，`n` 为独立字符，导致关键词按 `\` 和 `n` 拆分而非按换行。正确写法 `r'[\n,，;；]'`。`_safeFileName` 的 `r'\\s+'` 同理
- `message_builder_service.dart:611`: `RegExp(keyword, caseSensitive: ...)` 未传 `multiLine: true`，导致正则中 `^` 只匹配上下文字符串的开头而非每行开头
- `world_book_page.dart:keywordChip`: 长关键词 Text 没有 `Flexible` 包裹，`Row(mainAxisSize: min)` 会无限撑开导致删除按钮被挤出屏幕
- `scroll_controller.dart`: 8 秒自动滚动延迟实际功能鸡肋——Timer 结束后只设置标志位不触发滚动；AI 输出期间 `maxScrollExtent` 增长极快会迅速超出 56px 阈值
- `chat_api_service.dart`: Gemini 3 Pro 只支持 `thinkingLevel: 'low' | 'high'`；Flash 支持 `'minimal' | 'low' | 'medium' | 'high'`；UI 5 档在 Pro 上多对一降级
- `memory_store.dart`: SharedPreferences 存储全部记忆（JSON），有容量限制 (~1MB)，每次全量读写
- `chat_input_bar.dart:1417`: 移动端回车发送通过 `textInputAction: TextInputAction.send` 实现
- `assets/html/mark.html`: WebView 渲染使用 markdown-it（严格 CommonMark），CJK 文本中 `**"底气"**` 无法渲染粗体——当 `**` 右邻标点且左邻 CJK 字符时不满足左侧分隔符条件。Flutter 端 Dart `markdown` 包规则更宽松所以正常。可在 `renderMarkdown()` 前插入零宽空格预处理修复

## 模块间关系

- `MessageBuilderService` → `MemoryProvider` + `ChatService` + `InstructionInjectionProvider` + `WorldBookProvider`: 构建发给 LLM 的完整消息列表
- `ToolHandlerService` → `MemoryProvider` + `McpProvider` + `SearchToolService`: 接收 LLM 返回的 tool_calls 并本地执行
- `HomeViewModel._maybeGenerateSummaryFor` → `ChatApiService.generateText`: 摘要生成走独立 LLM 调用
- `main.dart:_selectHome()` → `DesktopHomePage` / `HomePage`: 移动端与桌面端 UI 的分叉入口，共享 `core/` + `shared/`（~72%），各自独立 UI 壳（~28%）

## 环境与工具

- fork 仓库 CI：自编译 APK 签名与官方版不同，Android 不允许不同签名覆盖安装，切换版本需备份 → 卸载 → 安装 → 恢复
- GitHub Actions 构建 Android arm64：`flutter build apk --release --split-per-abi --target-platform android-arm64` 只编译 arm64 架构，时间和产物体积均为全架构的 1/3
- 本地开发环境路径：Flutter SDK `D:\develop\flutter`、Android SDK `D:\develop\Android\Sdk`、JDK 17 `D:\develop\jdk-17`（绿色版，从 Adoptium MSI 迁移）
- Android SDK 无需安装 Android Studio：下载 "Command line tools only" zip，用 `sdkmanager` 安装 `platform-tools` + `platforms;android-36` + `build-tools;35.0.0` + `ndk;27.0.12077973`
- Gradle 8.12 需要 JDK 17 LTS，通过用户级环境变量 `JAVA_HOME = D:\develop\jdk-17` 指定（绿色版，直接复制文件夹即可使用，不依赖注册表和 PATH）
- F5 调试（DAP 协议）比终端 `flutter run` 多了保存自动热重载、断点、变量查看；原生配置（Manifest/Gradle）变更需全量重编译，Dart 代码改动秒级热重载
- 首次 `flutter run` 编译 Kelivo 约 25 分钟（含 Gradle 依赖下载），后续走缓存只需几十秒
- 调试手机：荣耀 Magic7 Pro (PTP-AN10)，Android 16 (API 36)，arm64。

## 已尝试但放弃的方案

- 自动滚动设计：Kelivo 的 Timer + 位置检测方案不如"用户意图状态机"（`shouldFollowRef`），后者基于用户主动滚回底部来恢复跟随，更符合直觉
- 世界书关键词正则 PR (`9503d80`)：我们修正了 raw string 转义 bug（`\\\\n` → `\\n`），但上游作者未接受，而是另建分支 `origin/fix/worldbook-keyword-newline-only` (`517ebe2`)，采用更激进方案——移除逗号/分号等分隔符，只保留换行拆分 (`[\r\n]+`)，同步更新了 i18n 提示文案。等该分支合并到 master 后 rebase 采用作者版本即可，`_parseKeywordInput` 会冲突但解决简单
