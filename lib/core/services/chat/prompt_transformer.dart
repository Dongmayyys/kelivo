import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../models/assistant.dart';

class PromptTransformer {
  static Map<String, String> buildPlaceholders({
    required BuildContext context,
    Assistant? assistant,
    required String? modelId,
    required String? modelName,
    required String userNickname,
  }) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tz = now.timeZoneName;
    final date = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dt = '$date $time';
    final os = Platform.operatingSystem;
    final osv = Platform.operatingSystemVersion;
    final device = os; // Simple fallback; can be extended with device_info plugins
    final battery = 'unknown';

    return <String, String>{
      '{cur_date}': date,
      '{cur_time}': time,
      '{cur_datetime}': dt,
      '{model_id}': modelId ?? '',
      '{model_name}': modelName ?? (modelId ?? ''),
      '{locale}': locale,
      '{timezone}': tz,
      '{system_version}': '$os $osv',
      '{device_info}': device,
      '{battery_level}': battery,
      '{nickname}': userNickname,
      '{assistant_name}': assistant?.name ?? '',
    };
  }

  static String replacePlaceholders(String text, Map<String, String> vars) {
    var out = text;
    vars.forEach((k, v) {
      out = out.replaceAll(k, v);
    });
    return out;
  }

  /// Resolve parameterized placeholders: {days_since:YYYY-MM-DD}, {days_until:YYYY-MM-DD}.
  static String resolveDynamicPlaceholders(String text) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysSinceRe = RegExp(r'\{days_since:(\d{4}-\d{2}-\d{2})\}');
    final daysUntilRe = RegExp(r'\{days_until:(\d{4}-\d{2}-\d{2})\}');

    DateTime? tryParseDate(String s) {
      final d = DateTime.tryParse(s);
      if (d == null) return null;
      // Reject auto-overflowed dates (e.g. 9999-99-99 parses but is invalid)
      final norm = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      return norm == s ? d : null;
    }

    var result = text.replaceAllMapped(daysSinceRe, (match) {
      final d = tryParseDate(match.group(1)!);
      if (d == null) return match.group(0)!;
      return today.difference(DateTime(d.year, d.month, d.day)).inDays.toString();
    });
    result = result.replaceAllMapped(daysUntilRe, (match) {
      final d = tryParseDate(match.group(1)!);
      if (d == null) return match.group(0)!;
      return DateTime(d.year, d.month, d.day).difference(today).inDays.toString();
    });
    return result;
  }

  /// Resolve all placeholders: static {key} vars + parameterized {key:param}.
  static String resolveAll(String text, Map<String, String> vars) {
    return resolveDynamicPlaceholders(replacePlaceholders(text, vars));
  }

  // Very simple mustache-like replacement for message template variables
  // Supported: {{ role }}, {{ message }}, {{ time }}, {{ date }}
  static String applyMessageTemplate(String template, {
    required String role,
    required String message,
    required DateTime now,
  }) {
    final date = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final vars = <String, String>{
      'role': role,
      'message': message,
      'time': time,
      'date': date,
    };

    return template.replaceAllMapped(
      RegExp(r'{{\s*(\w+)\s*}}'),
      (match) {
        final key = match.group(1);
        return key != null && vars.containsKey(key)
            ? vars[key]!
            : match.group(0) ?? '';
      },
    );
  }
}
