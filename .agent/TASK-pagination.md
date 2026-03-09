# 任务：实现消息分页加载

> 创建日期: 2026-03-07
> 状态: 待实施

## 问题

长对话（1645 条消息实测）切换时 UI 无响应数秒。

**根因已定位**：`MessageListView.build()` 中的 `_collapseVersions()` 和 `_groupMessages()` 每次 build 遍历全量消息列表。一次 switchConversation 触发 3+ 次 `notifyListeners`，导致这两个 O(N) 操作重复执行多次。1645 条消息在 debug 下 Skipped 231 frames (~3.8s)，release 下同样有明显卡顿。

**数据加载本身不是瓶颈**：`getMessages()` 命中缓存时仅 2ms，`_restoreMessageUiState()` 约 160ms（已验证延迟恢复方案仅改善 4%，无意义，已回退）。

## 上游参考：commit `48a1e41`

分支 `upstream/pagination`（未合入 master），作者 psyche。

### 核心思路（可复用）

- `ChatController` 新增 `_loadRecentMessages()` — 从 `conversation.messageIds` 尾部取最近 N 条 ID，调用新方法 `chatService.getMessagesByIds(ids)` 按 ID 加载
- `ChatController` 新增 `loadMoreMessages()` — 向前加载下一批旧消息，prepend 到 `_messages`
- `ChatController` 新增 `loadAllMessages()` — 兜底方法，加载全部
- `ChatService` 新增 `getMessagesByIds(List<String> ids)` — 按指定 ID 列表加载
- `MessageListView` 在 `hasMoreMessages && index == 0` 时渲染加载指示器，自动触发 `onLoadMoreMessages`
- `_messagePageSize = 12`

### 上游方案的已知缺陷（必须补全）

#### 🔴 严重：API 上下文丢失

`buildApiMessages()` 直接使用 `chatController.messages` 构建发给 AI 的消息列表。分页后 messages 只有最近 N 条，AI 丢失对话历史：

```dart
// message_builder_service.dart L106-190
List<Map<String, dynamic>> buildApiMessages({
  required List<ChatMessage> messages,  // ← 这就是 chatController.messages
  ...
})
```

**修复**：在 `sendMessage` / `regenerateAtMessage` 前调用 `loadAllMessages()`，或让 `buildApiMessages` 直接从 `chatService.getMessages()` 读全量。

#### 🔴 严重：forkConversation 依赖全量 messages

```dart
// home_view_model.dart L405-445
Future<void> forkConversation(ChatMessage message) async {
  for (int i = 0; i < messages.length; i++) {  // ← 遍历 chatController.messages
    final gid0 = (messages[i].groupId ?? messages[i].id);
    ...
  }
}
```

如果分叉点在未加载范围外，逻辑错误。**修复**：fork 前 `loadAllMessages()`。

#### 🟡 中等：compressContext 只压缩已加载消息

```dart
// home_view_model.dart L464-470
final allMsgs = _chatController.messages;
final collapsed = collapseVersions(allMsgs);
```

**修复**：compress 前 `loadAllMessages()`。

#### 🟡 中等：truncateIndex 映射可能错位

`MessageListView.build()` 将 raw `truncateIndex` 映射到 collapsed index，但分页后 messages 不从 index 0 开始，映射计算会错。

#### 🟡 中等：滚动位置跳动

`loadMoreMessages()` 在 `_messages` 头部插入旧消息，ListView 当前视口对应的 index 会变，导致内容跳动。需要手动补偿 scroll offset。

#### 🟡 低：pageSize = 12 太小

桌面端高分辨率屏幕 12 条可能不够填满一屏，导致反复触发 loadMore。建议 50。

## 需要改动的文件

| 文件 | 改动内容 |
|:---|:---|
| `lib/core/services/chat/chat_service.dart` | 新增 `getMessagesByIds()` |
| `lib/features/home/controllers/chat_controller.dart` | 分页状态 + `_loadRecentMessages` + `loadMoreMessages` + `loadAllMessages` |
| `lib/features/home/widgets/message_list_view.dart` | 顶部加载指示器 + index 偏移 |
| `lib/features/home/controllers/home_page_controller.dart` | 传递分页参数给 MessageListView，处理 loadMore 回调 |
| `lib/features/home/controllers/home_view_model.dart` | `sendMessage`/`regenerate`/`fork`/`compress` 前确保全量加载 |
| `lib/features/home/controllers/chat_actions.dart` | 检查是否直接引用 `chatController.messages`（可能需要调整） |
| `lib/features/home/services/message_builder_service.dart` | 确认 `buildApiMessages` 入参的数据来源 |

## 关键代码位置速查

- 切换对话入口：`HomePageController.switchConversationAnimated()` L489
- 加载消息：`ChatController.setCurrentConversation()` L62-73
- 消息缓存：`ChatService.getMessages()` 使用 `_messagesCache`
- build 瓶颈：`MessageListView.build()` → `_collapseVersions()` L148 + `_groupMessages()` L170
- API 消息构建：`MessageBuilderService.buildApiMessages()` L106
- 恢复 UI 状态：`HomePageController._restoreMessageUiState()` L1248
- 发消息流程：`HomeViewModel.sendMessage()` → `ChatActions.sendMessage()`
- 重新生成：`HomeViewModel.regenerateAtMessage()` → `ChatActions.regenerateAtMessage()`

## 实施建议

1. 先实现 `ChatController` 的分页逻辑（`_loadRecentMessages` + `loadMoreMessages` + `loadAllMessages`）
2. 在所有依赖全量数据的功能点前加 `loadAllMessages()` 调用
3. 修改 `MessageListView` 添加顶部加载指示器
4. pageSize 建议 50（移动端足够，桌面端也合理）
5. 保留 `_deferRestore` 的思路：`_restoreMessageUiState` 只恢复已加载的消息即可
6. 验证：切换 1645 条对话确认流畅 → 向上滚动加载更多 → 发消息/重生成/fork/compress 功能完整
