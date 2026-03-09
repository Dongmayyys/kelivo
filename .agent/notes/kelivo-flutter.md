# Kelivo & Flutter 跨平台笔记

> 2026-02-25

---

## 一、为什么 Kelivo 选 Flutter 而非 React Native

对 Kelivo 这种**个人开发的六平台重 UI 应用**，Flutter 几乎是唯一现实选择。

| 维度 | Flutter（Kelivo 的选择） | React Native |
|------|------------------------|-------------|
| 桌面支持 | ✅ 官方一等公民 | ⚠️ 社区方案，Linux 几乎无 |
| 渲染一致性 | ✅ 自有引擎，像素级一致 | ⚠️ 依赖原生组件，平台差异多 |
| 自定义 UI 深度 | ✅ CustomPainter 无限制 | ⚠️ 需要桥接原生视图 |
| 单人维护成本 | ✅ 只写 Dart | ⚠️ JS + 可能要写 Swift/Kotlin |

**决定性因素**：Kelivo 的 `lib/desktop/` 有 46 个文件（系统托盘、全局热键、窗口管理），
这些在 RN 桌面端做起来会非常痛苦。

---

## 二、Flutter vs RN 的本质区别

两种截然不同的跨平台哲学：

**Flutter —— 自己画一切**
- 向操作系统只要一个空窗口 + 原始输入事件
- 用自有渲染引擎（Skia/Impeller）从像素级别绘制所有 UI
- 类似游戏引擎的思路

**React Native —— 翻译官**
- JS 代码通过桥接层调用各平台的原生 UI 组件
- `<Text>` 在 iOS 变 UILabel，在 Android 变 TextView
- 看起来更"原生"，但各平台表现有差异

两者都实现了"你的代码不关心平台"，但方式完全不同：
- Flutter：跳过原生 UI 层，自己从像素画
- RN：把你的声明翻译成各平台原生组件

---

## 三、"一套代码"的真相

Kelivo 实际的代码分层：

```
lib/ 约 279 个 Dart 文件
│
├── core/     76 文件  🟢 100% 共享（models / providers / services）
├── shared/   28 文件  🟢 100% 共享（通用 widgets）
├── features/ 96 文件  🟡 大部分共享
├── utils/    15 文件  🟢 100% 共享
├── theme/     8 文件  🟢 100% 共享
├── l10n/      7 文件  🟢 100% 共享
│
├── features/home/ 33 文件  🔵 移动端专属 UI
├── desktop/       46 文件  🟠 桌面端专属 UI
```

分叉点在 `main.dart`：
```dart
return isDesktop ? const DesktopHomePage() : const HomePage();
```

**共享 ~72%，平台专属 ~28%。** 业务逻辑只写一遍，UI 壳各写一套。
这是作者主动选择体验优先的取舍——桌面端专门设计了原生交互范式，而非把手机界面放大。

---

## 四、Kelivo 的架构定位

Kelivo 是**务实的分层架构**，不是洋葱架构：

```
┌─────────────────────────────────────┐
│  UI 层 (features/ + desktop/)       │  依赖 ↓
├─────────────────────────────────────┤
│  状态层 (providers/)                 │  依赖 ↓  ← 耦合 Flutter
├─────────────────────────────────────┤
│  服务层 (services/)                  │  依赖 ↓  ← 耦合 Dio/HTTP
├─────────────────────────────────────┤
│  数据层 (models/)                    │           ← 耦合 Hive
└─────────────────────────────────────┘
```

层有了，方向也对（上层依赖下层），但内层耦合了框架（Model 带 `@HiveType`、
Provider 继承 `ChangeNotifier`），缺少洋葱架构要求的"内层纯净性"。

**这完全合理**——个人项目不需要洋葱架构带来的可替换性（不会换 Hive，不会换 Flutter），
但抽象层的复杂度是每天都要面对的。

---

## 五、WebView 渲染功能

### 作用

将 AI 回复的 Markdown 丢进 WebView 完整渲染，弥补 Flutter 原生渲染的能力缺口。

### 渲染链路

```
消息 Markdown → MarkdownMediaSanitizer（图片内联 base64）
             → MarkdownPreviewHtmlBuilder（注入主题色到 mark.html 模板）
             → WebViewPage 加载（mark.html 内用 markdown-it + KaTeX + highlight.js + Mermaid）
```

### 为什么必须用 WebView

| 能力 | Flutter 原生 | WebView |
|------|------------|---------|
| 基础 Markdown | ✅ | ✅ |
| 代码高亮 | ✅ | ✅ |
| LaTeX 公式 | ✅ flutter_math_fork | ✅ KaTeX |
| Mermaid 图表 | ❌ 无纯 Dart 实现 | ✅ |

瓶颈是 Mermaid——完整的 DSL→SVG 编译器，社区没有纯 Dart 实现。

### CJK 文本兼容问题

`**"底气"**` 在 WebView 中无法渲染粗体，Flutter 端正常。

原因：mark.html 使用 markdown-it，严格遵循 CommonMark emphasis 规则——
当 `**` 右邻标点（引号）且左邻 CJK 字符时，不满足左侧分隔符条件，粗体不开启。
Flutter 端 Dart `markdown` 包规则更宽松，所以能正常渲染。

可在 `mark.html` 的 `renderMarkdown()` 前加预处理修复（零宽空格插入方案）。

---

## 六、业界案例

### Flutter

Google Pay、闲鱼（阿里）、BMW、Nubank（巴西最大数字银行）、eBay Motors、Philips Hue

### React Native

Facebook（部分）、Instagram（部分）、Discord、Shopify、Bloomberg、Pinterest

**趋势**：Flutter 案例多为整个 App 重写；RN 案例多为大型原生 App 中的部分模块。
