import 'package:budgie_flutter/core/utils/helpers.dart';
import 'package:budgie_flutter/features/planner/domain/planner_models.dart';

AllocationResult calculateAllocation(double pool, List<GoalItem> items) {
  final sanitizedItems = items
      .map((item) {
        final target = item.target.clamp(0, double.infinity).toDouble();
        final saved = item.saved.clamp(0, target).toDouble();
        final percent = item.percent.clamp(0, 100).toDouble();
        return item.copyWith(target: target, saved: saved, percent: percent);
      })
      .toList(growable: false);
  final activeItems = sanitizedItems
      .where((item) => item.target > item.saved + 0.01)
      .toList(growable: false);

  if (pool <= 0 || activeItems.isEmpty) {
    return AllocationResult(
      allocationByGoalId: const {},
      unassigned: pool > 0 ? pool : 0,
      fixedPercentInput: 0,
      fixedPercentApplied: 0,
      scalingApplied: false,
    );
  }

  final allocationByGoalId = <String, double>{};
  final remainingById = <String, double>{
    for (final item in activeItems) item.id: round2(item.target - item.saved),
  };

  var unassigned = round2(pool);

  final fixedItems = activeItems.where((item) => item.percent > 0).toList(growable: false);
  final fixedTotalPercent = fixedItems.fold<double>(
    0,
    (total, item) => total + item.percent.clamp(0, 100),
  );
  final fixedScale = fixedTotalPercent > 100 ? 100 / fixedTotalPercent : 1;
  final fixedApplied = fixedTotalPercent * fixedScale;

  for (final item in fixedItems) {
    final need = remainingById[item.id] ?? 0;
    final share = (item.percent.clamp(0, 100) * fixedScale) / 100;
    final proposed = round2(pool * share);
    final amount = round2(proposed < need ? proposed : need);

    if (amount > 0) {
      allocationByGoalId[item.id] = round2((allocationByGoalId[item.id] ?? 0) + amount);
      remainingById[item.id] = round2(need - amount);
      unassigned = round2(unassigned - amount);
    }
  }

  if (unassigned > 0.01) {
    unassigned = _allocateByWeight(unassigned, activeItems, allocationByGoalId, remainingById);
  }

  return AllocationResult(
    allocationByGoalId: allocationByGoalId,
    unassigned: round2(unassigned < 0 ? 0 : unassigned),
    fixedPercentInput: round2(fixedTotalPercent),
    fixedPercentApplied: round2(fixedApplied),
    scalingApplied: fixedTotalPercent > 100,
  );
}

double _allocateByWeight(
  double pool,
  List<GoalItem> activeItems,
  Map<String, double> map,
  Map<String, double> remainingById,
) {
  var remainder = round2(pool);
  var guard = 0;

  while (remainder > 0.01 && guard < 8) {
    final available = activeItems
        .where((item) => (remainingById[item.id] ?? 0) > 0.01)
        .toList(growable: false);

    if (available.isEmpty) {
      break;
    }

    final totalWeight =
        available.fold<double>(0, (total, item) => total + _priorityWeight(item.priority));
    if (totalWeight <= 0) {
      break;
    }

    var distributed = 0.0;
    final snapshot = remainder;

    for (var index = 0; index < available.length; index += 1) {
      final item = available[index];
      final need = remainingById[item.id] ?? 0;
      if (need <= 0.01) {
        continue;
      }

      final rawShare = (snapshot * _priorityWeight(item.priority)) / totalWeight;
      final share =
          index == available.length - 1 ? snapshot - distributed : round2(rawShare);
      final grant = round2(share < need ? share : need);

      if (grant > 0) {
        map[item.id] = round2((map[item.id] ?? 0) + grant);
        remainingById[item.id] = round2(need - grant);
        distributed += grant;
      }
    }

    if (distributed <= 0) {
      break;
    }

    remainder = round2(remainder - distributed);
    guard += 1;
  }

  return remainder;
}

double _priorityWeight(GoalPriority priority) {
  switch (priority) {
    case GoalPriority.high:
      return 3;
    case GoalPriority.medium:
      return 2;
    case GoalPriority.low:
      return 1;
  }
}
