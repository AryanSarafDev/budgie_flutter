import 'package:budgie_flutter/core/utils/helpers.dart';

enum GoalPriority { high, medium, low }

enum EventType { system, ai, goal, expense, purchase }

class GoalItem {
  GoalItem({
    required this.id,
    required this.name,
    required this.target,
    required this.saved,
    required this.priority,
    required this.percent,
  });

  final String id;
  final String name;
  final double target;
  final double saved;
  final GoalPriority priority;
  final double percent;

  double get remaining => round2((target - saved).clamp(0, double.infinity));

  GoalItem copyWith({
    String? id,
    String? name,
    double? target,
    double? saved,
    GoalPriority? priority,
    double? percent,
  }) {
    return GoalItem(
      id: id ?? this.id,
      name: name ?? this.name,
      target: target ?? this.target,
      saved: saved ?? this.saved,
      priority: priority ?? this.priority,
      percent: percent ?? this.percent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'target': target,
      'saved': saved,
      'priority': priority.name,
      'percent': percent,
    };
  }

  static GoalItem fromJson(Map<String, dynamic> json) {
    final rawPriority = (json['priority'] ?? 'medium').toString();
    final priority = GoalPriority.values.firstWhere(
      (entry) => entry.name == rawPriority,
      orElse: () => GoalPriority.medium,
    );
    final target = toDoubleValue(json['target']).clamp(0, double.infinity).toDouble();
    final saved = toDoubleValue(json['saved']).clamp(0, target).toDouble();

    return GoalItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Untitled Goal').toString(),
      target: target,
      saved: saved,
      priority: priority,
      percent: toDoubleValue(json['percent']).clamp(0, 100).toDouble(),
    );
  }
}

class ExpenseItem {
  ExpenseItem({required this.id, required this.name, required this.amount});

  final String id;
  final String name;
  final double amount;

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'amount': amount};
  }

  static ExpenseItem fromJson(Map<String, dynamic> json) {
    return ExpenseItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      amount: toDoubleValue(json['amount']).clamp(0, double.infinity).toDouble(),
    );
  }
}

class PurchaseEntry {
  PurchaseEntry({
    required this.id,
    required this.goalName,
    required this.amount,
    required this.purchasedAt,
  });

  final String id;
  final String goalName;
  final double amount;
  final DateTime purchasedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'goalName': goalName,
      'amount': amount,
      'purchasedAt': purchasedAt.toIso8601String(),
    };
  }

  static PurchaseEntry fromJson(Map<String, dynamic> json) {
    return PurchaseEntry(
      id: (json['id'] ?? '').toString(),
      goalName: (json['goalName'] ?? '').toString(),
      amount: toDoubleValue(json['amount']).clamp(0, double.infinity).toDouble(),
      purchasedAt: DateTime.tryParse((json['purchasedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DailySpendEntry {
  DailySpendEntry({
    required this.id,
    required this.date,
    required this.amount,
    required this.note,
  });

  final String id;
  final DateTime date;
  final double amount;
  final String note;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'amount': amount,
      'note': note,
    };
  }

  static DailySpendEntry fromJson(Map<String, dynamic> json) {
    return DailySpendEntry(
      id: (json['id'] ?? '').toString(),
      date: DateTime.tryParse((json['date'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      amount: toDoubleValue(json['amount']).clamp(0, double.infinity).toDouble(),
      note: (json['note'] ?? '').toString(),
    );
  }
}

class EventLog {
  EventLog({
    required this.id,
    required this.ts,
    required this.type,
    required this.message,
    this.amount,
    this.meta,
  });

  final String id;
  final DateTime ts;
  final EventType type;
  final String message;
  final double? amount;
  final Map<String, dynamic>? meta;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ts': ts.toIso8601String(),
      'type': type.name,
      'message': message,
      'amount': amount,
      'meta': meta,
    };
  }

  static EventLog fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? 'system').toString();
    final type = EventType.values.firstWhere(
      (entry) => entry.name == rawType,
      orElse: () => EventType.system,
    );

    return EventLog(
      id: (json['id'] ?? '').toString(),
      ts: DateTime.tryParse((json['ts'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0),
      type: type,
      message: (json['message'] ?? '').toString(),
      amount: json['amount'] == null
        ? null
        : toDoubleValue(json['amount']).clamp(0, double.infinity).toDouble(),
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : null,
    );
  }
}

class AdvisorResult {
  AdvisorResult({
    required this.source,
    required this.summary,
    required this.recommendations,
    required this.quickActions,
    required this.suggestedPercents,
  });

  final String source;
  final String summary;
  final List<String> recommendations;
  final List<String> quickActions;
  final List<GoalPercentSuggestion> suggestedPercents;
}

class GoalPercentSuggestion {
  GoalPercentSuggestion({required this.goalName, required this.percent});

  final String goalName;
  final double percent;
}

class PlannerSnapshot {
  PlannerSnapshot({
    required this.salary,
    required this.expenses,
    required this.goals,
    required this.monthsProcessed,
    required this.monthPoolSpent,
    required this.extraSavings,
    required this.spentOnPurchases,
    required this.purchaseHistory,
    required this.logs,
    required this.dailySpends,
    required this.salaryInput,
    required this.goalPriority,
  });

  final double salary;
  final List<ExpenseItem> expenses;
  final List<GoalItem> goals;
  final int monthsProcessed;
  final double monthPoolSpent;
  final double extraSavings;
  final double spentOnPurchases;
  final List<PurchaseEntry> purchaseHistory;
  final List<EventLog> logs;
  final List<DailySpendEntry> dailySpends;
  final String salaryInput;
  final GoalPriority goalPriority;
}

class AllocationResult {
  AllocationResult({
    required this.allocationByGoalId,
    required this.unassigned,
    required this.fixedPercentInput,
    required this.fixedPercentApplied,
    required this.scalingApplied,
  });

  final Map<String, double> allocationByGoalId;
  final double unassigned;
  final double fixedPercentInput;
  final double fixedPercentApplied;
  final bool scalingApplied;
}
