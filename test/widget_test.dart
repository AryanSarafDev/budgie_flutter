import 'package:flutter_test/flutter_test.dart';

import 'package:budgie_flutter/features/planner/domain/allocation.dart';
import 'package:budgie_flutter/features/planner/domain/planner_models.dart';

void main() {
  test('calculateAllocation distributes weighted remainder', () {
    final goals = [
      GoalItem(
        id: 'g1',
        name: 'Emergency Fund',
        target: 10000,
        saved: 0,
        priority: GoalPriority.high,
        percent: 0,
      ),
      GoalItem(
        id: 'g2',
        name: 'Laptop',
        target: 10000,
        saved: 0,
        priority: GoalPriority.medium,
        percent: 0,
      ),
    ];

    final result = calculateAllocation(5000, goals);

    expect(result.unassigned, 0);
    expect((result.allocationByGoalId['g1'] ?? 0) > (result.allocationByGoalId['g2'] ?? 0), isTrue);
    expect((result.allocationByGoalId['g1'] ?? 0) + (result.allocationByGoalId['g2'] ?? 0), 5000);
  });
}
