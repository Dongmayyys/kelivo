import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/chat/prompt_transformer.dart';

void main() {
  group('resolveDynamicPlaceholders', () {
    test('resolves {days_since:YYYY-MM-DD}', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // 使用 10 天前的日期
      final tenDaysAgo = today.subtract(const Duration(days: 10));
      final dateStr =
          '${tenDaysAgo.year.toString().padLeft(4, '0')}-${tenDaysAgo.month.toString().padLeft(2, '0')}-${tenDaysAgo.day.toString().padLeft(2, '0')}';

      final input = '已坚持 {days_since:$dateStr} 天';
      final result = PromptTransformer.resolveDynamicPlaceholders(input);
      expect(result, '已坚持 10 天');
    });

    test('resolves {days_until:YYYY-MM-DD}', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // 使用 30 天后的日期
      final thirtyDaysLater = today.add(const Duration(days: 30));
      final dateStr =
          '${thirtyDaysLater.year.toString().padLeft(4, '0')}-${thirtyDaysLater.month.toString().padLeft(2, '0')}-${thirtyDaysLater.day.toString().padLeft(2, '0')}';

      final input = '距离考试还有 {days_until:$dateStr} 天';
      final result = PromptTransformer.resolveDynamicPlaceholders(input);
      expect(result, '距离考试还有 30 天');
    });

    test('handles multiple placeholders in one string', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final fiveDaysAgo = today.subtract(const Duration(days: 5));
      final tenDaysLater = today.add(const Duration(days: 10));
      final agoStr =
          '${fiveDaysAgo.year.toString().padLeft(4, '0')}-${fiveDaysAgo.month.toString().padLeft(2, '0')}-${fiveDaysAgo.day.toString().padLeft(2, '0')}';
      final laterStr =
          '${tenDaysLater.year.toString().padLeft(4, '0')}-${tenDaysLater.month.toString().padLeft(2, '0')}-${tenDaysLater.day.toString().padLeft(2, '0')}';

      final input = '冥想 {days_since:$agoStr} 天，考试倒计时 {days_until:$laterStr} 天';
      final result = PromptTransformer.resolveDynamicPlaceholders(input);
      expect(result, '冥想 5 天，考试倒计时 10 天');
    });

    test('leaves invalid dates unchanged', () {
      final input = '测试 {days_since:9999-99-99} 天';
      final result = PromptTransformer.resolveDynamicPlaceholders(input);
      // 无效日期应保留原样
      expect(result, '测试 {days_since:9999-99-99} 天');
    });

    test('ignores text without placeholders', () {
      const input = '普通文本没有占位符';
      final result = PromptTransformer.resolveDynamicPlaceholders(input);
      expect(result, input);
    });
  });

  group('resolveAll', () {
    test('resolves both static and dynamic placeholders', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final sevenDaysAgo = today.subtract(const Duration(days: 7));
      final dateStr =
          '${sevenDaysAgo.year.toString().padLeft(4, '0')}-${sevenDaysAgo.month.toString().padLeft(2, '0')}-${sevenDaysAgo.day.toString().padLeft(2, '0')}';

      final vars = <String, String>{
        '{nickname}': '小明',
        '{cur_date}': '2026-02-26',
      };
      final input = '{nickname} 从 $dateStr 开始冥想，已坚持 {days_since:$dateStr} 天。今天是 {cur_date}。';
      final result = PromptTransformer.resolveAll(input, vars);
      expect(result, '小明 从 $dateStr 开始冥想，已坚持 7 天。今天是 2026-02-26。');
    });
  });
}
