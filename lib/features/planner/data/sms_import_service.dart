import 'package:budgie_flutter/core/constants/app_constants.dart';
import 'package:budgie_flutter/features/planner/domain/planner_models.dart';
import 'package:flutter/services.dart';

class SmsImportService {
  SmsImportService._();

  static const MethodChannel _channel = MethodChannel(smsImportChannel);

  static Future<bool> hasPermission() async {
    final granted = await _channel.invokeMethod<bool>('hasSmsPermission');
    return granted ?? false;
  }

  static Future<bool> requestPermission() async {
    final granted = await _channel.invokeMethod<bool>('requestSmsPermission');
    return granted ?? false;
  }

  static Future<List<SmsImportTransaction>> fetchTransactions({
    DateTime? startAt,
    bool includeDebits = true,
    bool includeCredits = true,
    Set<String> excludeKeys = const <String>{},
  }) async {
    final result = await _channel.invokeMethod<List<dynamic>>('fetchUpiSms', {
      'startAtMs': startAt?.millisecondsSinceEpoch,
      'includeDebits': includeDebits,
      'includeCredits': includeCredits,
      'excludeKeys': excludeKeys.toList(growable: false),
    });

    final list = result ?? <dynamic>[];
    return list
        .whereType<Map>()
        .map((entry) => SmsImportTransaction.fromMap(Map<String, dynamic>.from(entry)))
        .where((entry) => entry.sourceKey.trim().isNotEmpty)
        .toList(growable: false);
  }
}
