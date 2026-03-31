import 'dart:math' as math;

import 'package:budgie_flutter/core/constants/app_constants.dart';
import 'package:budgie_flutter/core/theme/app_surface_tint.dart';
import 'package:budgie_flutter/core/theme/app_tokens.dart';
import 'package:budgie_flutter/core/utils/helpers.dart';
import 'package:budgie_flutter/features/planner/application/planner_state.dart';
import 'package:budgie_flutter/features/planner/application/planner_view_model.dart';
import 'package:budgie_flutter/features/planner/domain/planner_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key});

  Future<void> _showQuickDailyExpenseDialog(
    BuildContext context,
    PlannerViewModel vm,
  ) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime selectedDate = vm.dailySpendDate;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.receipt_long_outlined),
                  SizedBox(width: 8),
                  Text('Add Daily Expense'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(DateFormat('dd MMM yyyy').format(selectedDate)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final amountInput = amountCtrl.text.trim();
                    if (amountInput.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter an amount.')),
                      );
                      return;
                    }

                    vm.setDailySpendDate(selectedDate);
                    vm.dailySpendAmountCtrl.text = amountInput;
                    vm.dailySpendNoteCtrl.text = noteCtrl.text.trim();
                    final error = vm.addDailySpending();

                    Navigator.of(dialogContext).pop();
                    if (!context.mounted) {
                      return;
                    }

                    if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(error)),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Daily expense added.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    amountCtrl.dispose();
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlannerViewModel, PlannerState>(
      builder: (context, _) {
        final vm = context.read<PlannerViewModel>();
        final textTheme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Budgie',
              style: textTheme.titleLarge,
            ),
            actions: [
              IconButton(
                onPressed: vm.undoDepth > 0 ? vm.undoLastAction : null,
                icon: const Icon(Icons.undo),
                tooltip: 'Undo',
              ),
              IconButton(
                onPressed: () async {
                  final json = vm.exportExpenseHistoryJson();
                  await Clipboard.setData(ClipboardData(text: json));
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Expense history JSON copied to clipboard.')),
                  );
                },
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Export expense history (copy JSON)',
              ),
              if (vm.firebaseReady)
                TextButton.icon(
                  onPressed: vm.authUser == null ? vm.signInWithGoogle : vm.signOut,
                  icon: Icon(vm.authUser == null ? Icons.login : Icons.logout),
                  label: Text(vm.authUser == null ? 'Login' : 'Logout'),
                ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Center(
                  child: Text(
                    vm.cloudStatus.toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          extendBody: true,
          body: Stack(
            children: [
              const _ModernBackground(),
              SafeArea(
                child: vm.isHydrated
                    ? AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0.06, 0),
                            end: Offset.zero,
                          ).animate(animation);

                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(position: offset, child: child),
                          );
                        },
                        child: vm.activeTab == 0
                            ? KeyedSubtree(
                                key: ValueKey('planner-tab'),
                                child: _PlannerTabShell(),
                              )
                            : KeyedSubtree(
                                key: ValueKey('analytics-tab'),
                                child: _AnalyticsTabShell(),
                              ),
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: NavigationBar(
                selectedIndex: vm.activeTab,
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.savings), label: 'Planner'),
                  NavigationDestination(icon: Icon(Icons.analytics), label: 'Analytics'),
                ],
                onDestinationSelected: vm.setTab,
              ),
            ),
          ),
          floatingActionButton: vm.isHydrated && vm.activeTab == 0
              ? FloatingActionButton(
                  onPressed: () => _showQuickDailyExpenseDialog(context, vm),
                  child: const Icon(Icons.add),
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        );
      },
    );
  }
}

class _PlannerTabShell extends StatelessWidget {
  const _PlannerTabShell();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlannerViewModel>();
    return _PlannerTab(vm: vm);
  }
}

class _AnalyticsTabShell extends StatelessWidget {
  const _AnalyticsTabShell();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<PlannerViewModel>();
    return _AnalyticsTab(vm: vm);
  }
}

class _ModernBackground extends StatelessWidget {
  const _ModernBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(color: AppSurfaceTint.background(scheme));
  }
}

class _PlannerTab extends StatefulWidget {
  const _PlannerTab({required this.vm});

  final PlannerViewModel vm;

  @override
  State<_PlannerTab> createState() => _PlannerTabState();
}

class _PlannerTabState extends State<_PlannerTab> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final titles = ['Overview', 'Expenses', 'Goals', 'Daily', 'Advisor', 'Run'];
    final icons = [
      Icons.space_dashboard_outlined,
      Icons.receipt_long_outlined,
      Icons.flag_circle_outlined,
      Icons.calendar_today_outlined,
      Icons.psychology_alt_outlined,
      Icons.play_circle_outline,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 108),
      children: [
        _HeroPanel(
          chips: [
            _HeaderChip(label: 'Month #${vm.monthsProcessed}', icon: Icons.calendar_month),
            _HeaderChip(label: 'Cloud ${vm.cloudStatus.toUpperCase()}', icon: Icons.cloud_done_outlined),
            _HeaderChip(label: 'Undo ${vm.undoDepth}', icon: Icons.undo),
          ],
        ),
        if (vm.authError.isNotEmpty)
          _GlassCard(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(vm.authError),
            ),
          ),
        _GlassCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: List.generate(
                  titles.length,
                  (index) => ButtonSegment<int>(
                    value: index,
                    icon: Icon(icons[index], size: 18),
                    label: Text(titles[index]),
                  ),
                ),
                selected: <int>{_section},
                onSelectionChanged: (selection) {
                  setState(() => _section = selection.first);
                },
                showSelectedIcon: false,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildSection(vm, _section),
      ],
    );
  }

  Widget _buildSection(PlannerViewModel vm, int section) {
    switch (section) {
      case 0:
        return _PlannerOverview(vm: vm);
      case 1:
        return _PlannerExpenses(vm: vm);
      case 2:
        return _PlannerGoals(vm: vm);
      case 3:
        return _PlannerDaily(vm: vm);
      case 4:
        return _PlannerAdvisor(vm: vm);
      case 5:
      default:
        return _PlannerRun(vm: vm);
    }
  }
}

class _PlannerOverview extends StatelessWidget {
  const _PlannerOverview({required this.vm});

  final PlannerViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final cardWidth = width > 900 ? (width - 32 - 16) / 3 : (width - 32 - 8) / 2;
    final expenseRatio = vm.salary <= 0
        ? 0.0
        : (vm.monthlyExpenseTotal / vm.salary).clamp(0, 1).toDouble();
    final savingsRate = vm.salary <= 0
        ? 0.0
        : (vm.monthlyPool / vm.salary).clamp(0, 1).toDouble();
    final availableRatio = vm.monthlyPool <= 0
        ? 0.0
        : (vm.availableMonthExcess / vm.monthlyPool).clamp(0, 1).toDouble();

    final healthLabel = expenseRatio >= 0.9
        ? 'Pressure'
        : expenseRatio >= 0.7
            ? 'Tight'
            : 'Stable';
    final healthColor = expenseRatio >= 0.9
      ? scheme.error
        : expenseRatio >= 0.7
        ? scheme.tertiary
        : scheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxs, AppSpacing.xs, AppSpacing.xxs, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(
                width: cardWidth,
                child: _KpiTile(
                  label: 'Pool',
                  value: vm.asCurrency(vm.monthlyPool),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _KpiTile(
                  label: 'Saved',
                  value: vm.asCurrency(vm.totalSavingsWithCurrentExcess),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _KpiTile(
                  label: 'Spent',
                  value: vm.asCurrency(vm.spentOnPurchases),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.panel),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHead(
                    title: 'Overview',
                    subtitle: 'Health, burn, and runway at a glance.',
                    icon: Icons.space_dashboard_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _OverviewStatusPill(
                        icon: Icons.favorite_outline,
                        label: 'Health',
                        value: healthLabel,
                        color: healthColor,
                      ),
                      _OverviewStatusPill(
                        icon: Icons.percent,
                        label: 'Savings Rate',
                        value: '${(savingsRate * 100).toStringAsFixed(1)}%',
                        color: scheme.primary,
                      ),
                      _OverviewStatusPill(
                        icon: Icons.speed_outlined,
                        label: 'Burn Ratio',
                        value: '${(expenseRatio * 100).toStringAsFixed(1)}%',
                        color: scheme.tertiary,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _OverviewSplitBar(
                    leftLabel: 'Expenses',
                    rightLabel: 'Savings Pool',
                    leftValue: vm.monthlyExpenseTotal,
                    rightValue: vm.monthlyPool,
                    leftColor: scheme.error,
                    rightColor: scheme.primary,
                    format: vm.asCurrency,
                  ),
                  const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                  _OverviewSplitBar(
                    leftLabel: 'Used This Month',
                    rightLabel: 'Still Available',
                    leftValue: vm.monthPoolSpent,
                    rightValue: vm.availableMonthExcess,
                    leftColor: scheme.tertiary,
                    rightColor: scheme.secondary,
                    format: vm.asCurrency,
                  ),
                ],
              ),
            ),
          ),
          _GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.panel),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHead(
                    title: 'Salary Baseline',
                    subtitle: 'Update salary and review monthly totals.',
                    icon: Icons.account_balance_outlined,
                  ),
                  const SizedBox(height: AppSpacing.panel),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: vm.salaryCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Monthly Salary',
                            prefixIcon: Icon(Icons.payments_outlined),
                          ),
                          onSubmitted: (_) => vm.updateSalaryFromInput(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed: vm.updateSalaryFromInput,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Update'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DataMetric(label: 'Expenses', value: vm.asCurrency(vm.monthlyExpenseTotal)),
                      _DataMetric(label: 'Savings Pool', value: vm.asCurrency(vm.monthlyPool)),
                      _DataMetric(label: 'Available', value: vm.asCurrency(vm.availableMonthExcess)),
                      _DataMetric(
                        label: 'Total Position',
                        value: vm.asCurrency(vm.totalSavingsWithCurrentExcess),
                        wide: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                  _MiniTrendBar(
                    value: availableRatio,
                    maxValue: 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewStatusPill extends StatelessWidget {
  const _OverviewStatusPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$label: $value',
            style: text.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewSplitBar extends StatelessWidget {
  const _OverviewSplitBar({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftValue,
    required this.rightValue,
    required this.leftColor,
    required this.rightColor,
    required this.format,
  });

  final String leftLabel;
  final String rightLabel;
  final double leftValue;
  final double rightValue;
  final Color leftColor;
  final Color rightColor;
  final String Function(double value) format;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final total = leftValue + rightValue;
    final leftRatio = total <= 0 ? 0.5 : (leftValue / total).clamp(0, 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                leftLabel,
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                rightLabel,
                textAlign: TextAlign.right,
                style: text.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _SquigglyProgressBar(
          value: leftRatio,
          height: AppSpacing.sm + AppSpacing.xxs,
          color: leftColor,
          trackColor: rightColor,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                format(leftValue),
                style: text.titleSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
            Expanded(
              child: Text(
                format(rightValue),
                textAlign: TextAlign.right,
                style: text.titleSmall?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlannerExpenses extends StatelessWidget {
  const _PlannerExpenses({required this.vm});

  final PlannerViewModel vm;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.panel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'Expenses',
              subtitle: 'Maintain recurring outflows. This list drives your monthly pool.',
              icon: Icons.receipt_outlined,
            ),
            const SizedBox(height: AppSpacing.panel),
            TextField(
              controller: vm.expenseNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Expense name',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: vm.expenseAmountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: vm.addExpense,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
            if (vm.expenses.isEmpty)
              const _EmptyInline(message: 'No expenses yet.')
            else
              ...vm.expenses.map(
                (expense) => _ExpenseRow(
                  name: expense.name,
                  amount: vm.asCurrency(expense.amount),
                  onDelete: () => vm.removeExpense(expense.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlannerGoals extends StatelessWidget {
  const _PlannerGoals({required this.vm});

  final PlannerViewModel vm;

  @override
  Widget build(BuildContext context) {
    final alloc = vm.allocation;
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.panel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'Goals & Allocation',
              subtitle: 'Create goals and review per-goal monthly allocation output.',
              icon: Icons.flag_outlined,
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _DataMetric(label: 'Fixed Input', value: '${alloc.fixedPercentInput.toStringAsFixed(1)}%'),
                _DataMetric(label: 'Applied %', value: '${alloc.fixedPercentApplied.toStringAsFixed(1)}%'),
                _DataMetric(label: 'Scaling', value: alloc.scalingApplied ? 'Enabled' : 'Normal'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: vm.goalNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Goal name',
                prefixIcon: Icon(Icons.flag_circle_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: vm.goalTargetCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target amount',
                prefixIcon: Icon(Icons.track_changes_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<GoalPriority>(
              initialValue: vm.goalPriority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                prefixIcon: Icon(Icons.low_priority),
              ),
              items: const [
                DropdownMenuItem(value: GoalPriority.high, child: Text('High')),
                DropdownMenuItem(value: GoalPriority.medium, child: Text('Medium')),
                DropdownMenuItem(value: GoalPriority.low, child: Text('Low')),
              ],
              onChanged: (value) {
                if (value != null) {
                  vm.changeGoalPriority(value);
                }
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: vm.goalPercentCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Fixed % allocation (optional)',
                prefixIcon: Icon(Icons.percent),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: vm.addGoal,
              icon: const Icon(Icons.add_task),
              label: const Text('Add Goal'),
            ),
            const SizedBox(height: AppSpacing.md),
            if (vm.plannedAllocation.isEmpty)
              const _EmptyInline(message: 'No active goals yet.')
            else
              ...vm.plannedAllocation.map((entry) {
                final goal = entry.key;
                final planned = entry.value;
                final progress = goal.target <= 0 ? 0.0 : (goal.saved / goal.target).clamp(0, 1).toDouble();
                return _GlassCard(
                  margin: const EdgeInsets.symmetric(vertical: AppSpacing.compact),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.panel),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                goal.name,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            IconButton(onPressed: () => vm.removeGoal(goal.id), icon: const Icon(Icons.delete_outline)),
                          ],
                        ),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            _DataMetric(label: 'Saved', value: vm.asCurrency(goal.saved)),
                            _DataMetric(label: 'Target', value: vm.asCurrency(goal.target)),
                            _DataMetric(label: 'Planned', value: vm.asCurrency(planned)),
                            _DataMetric(label: 'Priority', value: goal.priority.name.toUpperCase()),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _SquigglyProgressBar(
                          value: progress,
                          height: AppSpacing.sm,
                          trackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          color: goal.priority == GoalPriority.high
                              ? Theme.of(context).colorScheme.error
                              : goal.priority == GoalPriority.medium
                                  ? Theme.of(context).colorScheme.tertiary
                                  : Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        FilledButton.tonalIcon(
                          onPressed: () => vm.buyGoal(goal.id),
                          icon: const Icon(Icons.shopping_cart_checkout),
                          label: const Text('Buy Goal'),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _PlannerDaily extends StatelessWidget {
  const _PlannerDaily({required this.vm});

  final PlannerViewModel vm;

  @override
  Widget build(BuildContext context) {
    final calendar = vm.calendarSnapshot;
    final cells = (calendar['cells'] as List).cast<Map<String, dynamic>>();

    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.panel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'Daily Spending',
              subtitle: 'Log daily outflows and inspect month distribution.',
              icon: Icons.calendar_view_month_outlined,
            ),
            const SizedBox(height: AppSpacing.panel),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: vm.dailySpendDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (chosen != null) {
                      vm.setDailySpendDate(chosen);
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(DateFormat('dd MMM yyyy').format(vm.dailySpendDate)),
                ),
                SizedBox(
                  width: AppSize.compactInput,
                  child: TextField(
                    controller: vm.dailySpendAmountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                  ),
                ),
                SizedBox(
                  width: AppSize.mediumInput,
                  child: TextField(
                    controller: vm.dailySpendNoteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      prefixIcon: Icon(Icons.note_alt_outlined),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final error = vm.addDailySpending();
                    if (error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
                  icon: const Icon(Icons.add_chart_outlined),
                  label: const Text('Log Entry'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                IconButton(onPressed: vm.previousCalendarMonth, icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(
                    calendar['monthLabel'].toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(onPressed: vm.nextCalendarMonth, icon: const Icon(Icons.chevron_right)),
                TextButton.icon(
                  onPressed: vm.resetCalendarMonth,
                  icon: const Icon(Icons.today),
                  label: const Text('Today'),
                ),
              ],
            ),
            _DataMetric(label: 'Month Spend', value: vm.asCurrency(toDoubleValue(calendar['monthTotal'])), wide: true),
            const SizedBox(height: AppSpacing.sm),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Sun'), Text('Mon'), Text('Tue'), Text('Wed'), Text('Thu'), Text('Fri'), Text('Sat')],
            ),
            const SizedBox(height: AppSpacing.compact),
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: cells.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.15,
                crossAxisSpacing: 5,
                mainAxisSpacing: 5,
              ),
              itemBuilder: (context, index) {
                final cell = cells[index];
                if (cell['type'] == 'empty') {
                  return const SizedBox.shrink();
                }
                final total = toDoubleValue(cell['total']);
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.compact),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    color: total > 0
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.surfaceContainer,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${cell['day']}', style: Theme.of(context).textTheme.labelSmall),
                      const Spacer(),
                      if (total > 0)
                        Text(
                          vm.asCurrency(total),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PlannerAdvisor extends StatelessWidget {
  const _PlannerAdvisor({required this.vm});

  final PlannerViewModel vm;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.panel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'AI Advisor',
              subtitle: 'Generate recommendations and apply suggested allocations when relevant.',
              icon: Icons.psychology_alt_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Model: $geminiModel (local fallback enabled).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (vm.aiError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(vm.aiError, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: vm.aiLoading ? null : vm.runAiAdvisor,
                  icon: vm.aiLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(vm.aiLoading ? 'Analyzing...' : 'Generate Plan'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: vm.aiResult == null ? null : vm.applyAiPercentSuggestions,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.checklist_rtl),
                      SizedBox(width: 6),
                      Text('Apply Suggestions'),
                    ],
                  ),
                ),
              ],
            ),
            if (vm.aiResult != null) ...[
              const SizedBox(height: 12),
              _DataMetric(label: 'Source', value: vm.aiResult!.source.toUpperCase(), wide: true),
              const SizedBox(height: AppSpacing.compact),
              Text(vm.aiResult!.summary),
              const SizedBox(height: AppSpacing.sm),
              if (vm.aiResult!.recommendations.isNotEmpty)
                ...vm.aiResult!.recommendations.map((line) => Text('• $line')),
              if (vm.aiResult!.quickActions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Quick Actions', style: Theme.of(context).textTheme.titleSmall),
                ...vm.aiResult!.quickActions.map((line) => Text('• $line')),
              ],
              if (vm.aiResult!.suggestedPercents.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Suggested Allocation', style: Theme.of(context).textTheme.titleSmall),
                ...vm.aiResult!.suggestedPercents.map(
                  (entry) => Text('${entry.goalName}: ${entry.percent.toStringAsFixed(1)}%'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PlannerRun extends StatelessWidget {
  const _PlannerRun({required this.vm});

  final PlannerViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.panel),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHead(
                  title: 'Monthly Execution',
                  subtitle: 'Process month-end allocation and maintain reset controls.',
                  icon: Icons.schedule_send_outlined,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _DataMetric(label: 'Processed', value: '${vm.monthsProcessed}'),
                    _DataMetric(label: 'Purchase Spend', value: vm.asCurrency(vm.spentOnPurchases)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: vm.processMonth,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Process Month'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: vm.resetProgress,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset Progress'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: vm.hardReset,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Hard Reset App Data'),
                ),
              ],
            ),
          ),
        ),
        _GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.panel),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHead(
                  title: 'Purchase History',
                  subtitle: 'Most recent completed goal purchases.',
                  icon: Icons.history,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (vm.purchaseHistory.isEmpty)
                  const _EmptyInline(message: 'No purchases yet.')
                else
                  ...vm.purchaseHistory.take(8).map(
                        (entry) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          minTileHeight: 34,
                          title: Text(entry.goalName),
                          subtitle: Text(DateFormat('dd MMM yyyy').format(entry.purchasedAt)),
                          trailing: Text(vm.asCurrency(entry.amount)),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalyticsTab extends StatefulWidget {
  const _AnalyticsTab({required this.vm});

  final PlannerViewModel vm;

  @override
  State<_AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<_AnalyticsTab> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final sections = ['Snapshot', 'Trend', 'Logs'];
    final icons = [
      Icons.dashboard_outlined,
      Icons.timeline,
      Icons.list_alt_outlined,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 108),
      children: [
        _HeroPanel(
          chips: const [
            _HeaderChip(label: 'Snapshot', icon: Icons.dashboard_outlined),
            _HeaderChip(label: 'Trend', icon: Icons.timeline),
            _HeaderChip(label: 'Logs', icon: Icons.list_alt_outlined),
          ],
        ),
        _GlassCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                segments: List.generate(
                  sections.length,
                  (index) => ButtonSegment<int>(
                    value: index,
                    icon: Icon(icons[index], size: 18),
                    label: Text(sections[index]),
                  ),
                ),
                selected: <int>{_section},
                onSelectionChanged: (selection) {
                  setState(() => _section = selection.first);
                },
                showSelectedIcon: false,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildSection(vm, _section),
      ],
    );
  }

  Widget _buildSection(PlannerViewModel vm, int section) {
    final expenseAdded = vm.logs
        .where((entry) => entry.type == EventType.expense && entry.message.toLowerCase().contains('added'))
        .fold<double>(0, (total, entry) => total + (entry.amount ?? 0));
    final purchases = vm.logs
        .where((entry) => entry.type == EventType.purchase)
        .fold<double>(0, (total, entry) => total + (entry.amount ?? 0));

    final trendByMonth = <String, double>{};
    for (final entry in vm.logs) {
      if (entry.type != EventType.expense && entry.type != EventType.purchase) {
        continue;
      }
      final key = DateFormat('yyyy-MM').format(entry.ts);
      trendByMonth[key] = round2((trendByMonth[key] ?? 0) + (entry.amount ?? 0));
    }
    final monthKeys = trendByMonth.keys.toList()..sort();
    final monthRows = monthKeys.reversed.take(8).toList(growable: false);

    if (section == 0) {
      return _GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.panel),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHead(
                title: 'Analytics Snapshot',
                subtitle: 'Current state across expenses, purchases, and activity volume.',
                icon: Icons.dashboard_outlined,
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _DataMetric(label: 'Expenses Added', value: vm.asCurrency(expenseAdded)),
                  _DataMetric(label: 'Purchases', value: vm.asCurrency(purchases)),
                  _DataMetric(label: 'Active Goals', value: '${vm.goals.length}'),
                  _DataMetric(label: 'Daily Entries', value: '${vm.dailySpends.length}'),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (section == 1) {
      return _GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.panel),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHead(
                title: 'Monthly Spend Trend',
                subtitle: 'Recent eight-month flow with relative intensity.',
                icon: Icons.timeline,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (monthRows.isEmpty)
                const _EmptyInline(message: 'No monthly trend yet.')
              else
                ...monthRows.map((key) {
                  final labelDate = DateTime.tryParse('$key-01');
                  final label = labelDate == null ? key : DateFormat('MMM yyyy').format(labelDate);
                  final amount = trendByMonth[key] ?? 0;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    minTileHeight: 34,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label),
                        const SizedBox(height: AppSpacing.compact),
                        _MiniTrendBar(
                          value: amount,
                          maxValue: monthRows
                              .map((monthKey) => trendByMonth[monthKey] ?? 0)
                              .fold<double>(1, (max, value) => value > max ? value : max),
                        ),
                      ],
                    ),
                    trailing: Text(vm.asCurrency(amount)),
                  );
                }),
            ],
          ),
        ),
      );
    }

    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.panel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'Event Log',
              subtitle: 'Recent operational and user activity trail.',
              icon: Icons.list_alt_outlined,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (vm.logs.isEmpty)
              const _EmptyInline(message: 'No logs yet.')
            else
              ...vm.logs.take(140).map((entry) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  minTileHeight: 34,
                  title: Text(entry.message),
                  subtitle: Text('${entry.type.name.toUpperCase()} | ${DateFormat('dd MMM HH:mm').format(entry.ts)}'),
                  trailing: entry.amount == null ? null : Text(vm.asCurrency(entry.amount!)),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, required this.subtitle, this.icon});

  final String title;
  final String subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              title,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.3),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.chips,
  });

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shadowAlpha = Theme.of(context).brightness == Brightness.dark ? 0.24 : 0.1;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg + 2, AppSpacing.lg + 2, AppSpacing.lg + 2, AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: AppSurfaceTint.card(scheme),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: shadowAlpha),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: chips),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: scheme.onSecondaryContainer),
      backgroundColor: scheme.secondaryContainer,
      label: Text(label),
      onPressed: () {},
      labelStyle: TextStyle(
        color: scheme.onSecondaryContainer,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.name,
    required this.amount,
    required this.onDelete,
  });

  final String name;
  final String amount;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shadowAlpha = Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.08;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppSurfaceTint.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: shadowAlpha),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs),
        title: Text(name, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(
          amount,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        trailing: IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
      ),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shadowAlpha = Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.08;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppSurfaceTint.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: shadowAlpha),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    this.margin,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shadowAlpha = Theme.of(context).brightness == Brightness.dark ? 0.24 : 0.1;
    return AnimatedContainer(
      duration: AppDuration.short,
      margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: color ?? AppSurfaceTint.card(scheme),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: shadowAlpha),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: child,
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shadowAlpha = Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.08;
    return Container(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppSurfaceTint.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: shadowAlpha),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedSwitcher(
            duration: AppDuration.medium,
            child: Text(
              value,
              key: ValueKey(value),
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTrendBar extends StatelessWidget {
  const _MiniTrendBar({required this.value, required this.maxValue});

  final double value;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio =
        maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0, 1).toDouble();
    return _SquigglyProgressBar(
      value: ratio,
      height: AppSpacing.compact,
      color: scheme.primary,
      trackColor: scheme.onSurfaceVariant,
    );
  }
}

class _SquigglyProgressBar extends StatelessWidget {
  const _SquigglyProgressBar({
    required this.value,
    required this.height,
    required this.color,
    required this.trackColor,
  });

  final double value;
  final double height;
  final Color color;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final progress = value.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, height),
            painter: _SquigglyProgressPainter(
              progress: progress,
              color: color,
              trackColor: trackColor,
            ),
          );
        },
      ),
    );
  }
}

class _SquigglyProgressPainter extends CustomPainter {
  const _SquigglyProgressPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final progressWidth = size.width * progress;
    final baseline = size.height / 2;
    final amplitude = math.max(1.0, size.height * 0.22);
    const wavelength = 24.0;
    const step = 2.0;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.height * 0.46)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = trackColor.withValues(alpha: 0.72);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, size.height * 0.46)
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = color;

    final trackPath = Path()..moveTo(0, baseline);
    for (double x = 0; x <= size.width; x += step) {
      final y = baseline + amplitude * math.sin((x / wavelength) * 2 * math.pi);
      trackPath.lineTo(x, y);
    }
    canvas.drawPath(trackPath, trackPaint);

    final progressPath = Path()..moveTo(0, baseline);
    for (double x = 0; x <= progressWidth; x += step) {
      final y = baseline + amplitude * math.sin((x / wavelength) * 2 * math.pi);
      progressPath.lineTo(x, y);
    }
    canvas.drawPath(progressPath, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _SquigglyProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

class _DataMetric extends StatelessWidget {
  const _DataMetric({
    required this.label,
    required this.value,
    this.wide = false,
  });

  final String label;
  final String value;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shadowAlpha = Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.08;
    return SizedBox(
      width: wide ? AppSize.metricWide : AppSize.metricCompact,
      child: Container(
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: AppSurfaceTint.card(scheme),
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: shadowAlpha),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs),
          title: Text(
            label,
            style: text.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          subtitle: Text(
            value,
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
