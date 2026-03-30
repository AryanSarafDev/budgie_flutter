import 'dart:ui';

import 'package:budgie_flutter/core/constants/app_constants.dart';
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
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Budgie',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
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
                padding: const EdgeInsets.only(right: 10),
                child: Center(
                  child: Text(
                    vm.cloudStatus.toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
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
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF070B12),
            Color(0xFF0D121B),
            Color(0xFF111824),
          ],
        ),
      ),
      child: const SizedBox.expand(),
    );
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 108),
      children: [
        _GlassCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Budgie Financial Desk',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Work through one section at a time for clarity: update base numbers, manage expenses, then allocate and execute.',
                  style: TextStyle(color: Color(0xFF9BAABA), height: 1.35),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderChip(label: 'Month #${vm.monthsProcessed}', icon: Icons.calendar_month),
                    _HeaderChip(label: 'Cloud ${vm.cloudStatus.toUpperCase()}', icon: Icons.cloud_done_outlined),
                    _HeaderChip(label: 'Undo ${vm.undoDepth}', icon: Icons.undo),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (vm.authError.isNotEmpty)
          _GlassCard(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(vm.authError),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(titles.length, (index) {
            return ChoiceChip(
              label: Text(titles[index]),
              selected: _section == index,
              onSelected: (_) => setState(() => _section = index),
            );
          }),
        ),
        const SizedBox(height: 12),
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
    final spentRatio = vm.monthlyPool <= 0
        ? 0.0
        : (vm.monthPoolSpent / vm.monthlyPool).clamp(0, 1).toDouble();

    final healthLabel = expenseRatio >= 0.9
        ? 'Pressure'
        : expenseRatio >= 0.7
            ? 'Tight'
            : 'Stable';
    final healthColor = expenseRatio >= 0.9
        ? const Color(0xFFD87F75)
        : expenseRatio >= 0.7
            ? const Color(0xFFBFA36B)
            : const Color(0xFF8DB39E);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: cardWidth,
                child: _KpiTile(
                  label: 'Savings Pool',
                  value: vm.asCurrency(vm.monthlyPool),
                  icon: Icons.account_balance_wallet_outlined,
                  color: const Color(0xFFA6B5C6),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _KpiTile(
                  label: 'Total Saved',
                  value: vm.asCurrency(vm.totalSavingsWithCurrentExcess),
                  icon: Icons.ssid_chart,
                  color: const Color(0xFF8FA0B5),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _KpiTile(
                  label: 'Purchase Spend',
                  value: vm.asCurrency(vm.spentOnPurchases),
                  icon: Icons.shopping_bag_outlined,
                  color: const Color(0xFF9EABB9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHead(
                    title: 'Overview Command Deck',
                    subtitle: 'Track spend pressure, available runway, and savings quality at a glance.',
                    icon: Icons.space_dashboard_outlined,
                  ),
                  const SizedBox(height: 12),
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
                        color: const Color(0xFF8DB39E),
                      ),
                      _OverviewStatusPill(
                        icon: Icons.speed_outlined,
                        label: 'Burn Ratio',
                        value: '${(expenseRatio * 100).toStringAsFixed(1)}%',
                        color: const Color(0xFFBFA36B),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _OverviewSplitBar(
                    leftLabel: 'Expenses',
                    rightLabel: 'Savings Pool',
                    leftValue: vm.monthlyExpenseTotal,
                    rightValue: vm.monthlyPool,
                    leftColor: const Color(0xFF8D6A66),
                    rightColor: const Color(0xFF6A8A8D),
                    format: vm.asCurrency,
                  ),
                  const SizedBox(height: 10),
                  _OverviewSplitBar(
                    leftLabel: 'Used This Month',
                    rightLabel: 'Still Available',
                    leftValue: vm.monthPoolSpent,
                    rightValue: vm.availableMonthExcess,
                    leftColor: const Color(0xFF8A745B),
                    rightColor: const Color(0xFF6E8D7A),
                    format: vm.asCurrency,
                  ),
                ],
              ),
            ),
          ),
          _GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHead(
                    title: 'Finance Overview',
                    subtitle: 'Set salary first. Everything else derives from this baseline.',
                    icon: Icons.account_balance_outlined,
                  ),
                  const SizedBox(height: 14),
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
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: vm.updateSalaryFromInput,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Update'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DataMetric(label: 'Expenses', value: vm.asCurrency(vm.monthlyExpenseTotal)),
                      _DataMetric(label: 'Savings Pool', value: vm.asCurrency(vm.monthlyPool)),
                      _DataMetric(label: 'Available', value: vm.asCurrency(vm.availableMonthExcess)),
                      _DataMetric(label: 'Extra Savings', value: vm.asCurrency(vm.extraSavings)),
                      _DataMetric(
                        label: 'Total Position',
                        value: vm.asCurrency(vm.totalSavingsWithCurrentExcess),
                        wide: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _MiniTrendBar(
                    value: availableRatio,
                    maxValue: 1,
                  ),
                ],
              ),
            ),
          ),
          _GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionHead(
                    title: 'Signal Grid',
                    subtitle: 'Compact indicators for quick financial posture checks.',
                    icon: Icons.grid_view_rounded,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _OverviewMetricTile(
                        label: 'Allocation Applied',
                        value: '${vm.allocation.fixedPercentApplied.toStringAsFixed(1)}%',
                        icon: Icons.rule_folder_outlined,
                      ),
                      _OverviewMetricTile(
                        label: 'Allocation Scaling',
                        value: vm.allocation.scalingApplied ? 'Enabled' : 'Normal',
                        icon: Icons.tune,
                      ),
                      _OverviewMetricTile(
                        label: 'Active Goals',
                        value: '${vm.goals.length}',
                        icon: Icons.flag_circle_outlined,
                      ),
                      _OverviewMetricTile(
                        label: 'Runway In Pool',
                        value: '${(availableRatio * 100).toStringAsFixed(1)}%',
                        icon: Icons.waterfall_chart,
                      ),
                      _OverviewMetricTile(
                        label: 'Pool Consumed',
                        value: '${(spentRatio * 100).toStringAsFixed(1)}%',
                        icon: Icons.pie_chart_outline,
                      ),
                    ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1825).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            '$label: $value',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFFDCE4EE),
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
    final total = leftValue + rightValue;
    final leftRatio = total <= 0 ? 0.5 : (leftValue / total).clamp(0, 1).toDouble();
    final rightRatio = 1 - leftRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                leftLabel,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF98A7B8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                rightLabel,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF98A7B8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                Expanded(
                  flex: (leftRatio * 1000).round().clamp(1, 999),
                  child: Container(color: leftColor),
                ),
                Expanded(
                  flex: (rightRatio * 1000).round().clamp(1, 999),
                  child: Container(color: rightColor),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                format(leftValue),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE2EAF3),
                ),
              ),
            ),
            Expanded(
              child: Text(
                format(rightValue),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE2EAF3),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewMetricTile extends StatelessWidget {
  const _OverviewMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1825).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: const Color(0xFF9AA8B8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF98A7B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE4EBF3),
            ),
          ),
        ],
      ),
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'Expenses',
              subtitle: 'Maintain recurring outflows. This list drives your monthly pool.',
              icon: Icons.receipt_outlined,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: vm.expenseNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Expense name',
                prefixIcon: Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 8),
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
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: vm.addExpense,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'Goals & Allocation',
              subtitle: 'Create goals and review per-goal monthly allocation output.',
              icon: Icons.flag_outlined,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DataMetric(label: 'Fixed Input', value: '${alloc.fixedPercentInput.toStringAsFixed(1)}%'),
                _DataMetric(label: 'Applied %', value: '${alloc.fixedPercentApplied.toStringAsFixed(1)}%'),
                _DataMetric(label: 'Scaling', value: alloc.scalingApplied ? 'Enabled' : 'Normal'),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vm.goalNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Goal name',
                prefixIcon: Icon(Icons.flag_circle_outlined),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: vm.goalTargetCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target amount',
                prefixIcon: Icon(Icons.track_changes_outlined),
              ),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
            TextField(
              controller: vm.goalPercentCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Fixed % allocation (optional)',
                prefixIcon: Icon(Icons.percent),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: vm.addGoal,
              icon: const Icon(Icons.add_task),
              label: const Text('Add Goal'),
            ),
            const SizedBox(height: 12),
            if (vm.plannedAllocation.isEmpty)
              const _EmptyInline(message: 'No active goals yet.')
            else
              ...vm.plannedAllocation.map((entry) {
                final goal = entry.key;
                final planned = entry.value;
                final progress = goal.target <= 0 ? 0.0 : (goal.saved / goal.target).clamp(0, 1).toDouble();
                return _GlassCard(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(goal.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                            IconButton(onPressed: () => vm.removeGoal(goal.id), icon: const Icon(Icons.delete_outline)),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _DataMetric(label: 'Saved', value: vm.asCurrency(goal.saved)),
                            _DataMetric(label: 'Target', value: vm.asCurrency(goal.target)),
                            _DataMetric(label: 'Planned', value: vm.asCurrency(planned)),
                            _DataMetric(label: 'Priority', value: goal.priority.name.toUpperCase()),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.white.withValues(alpha: 0.14),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              goal.priority == GoalPriority.high
                                  ? const Color(0xFFD87F75)
                                  : goal.priority == GoalPriority.medium
                                      ? const Color(0xFFBFA36B)
                                      : const Color(0xFFA0B3C9),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'Daily Spending',
              subtitle: 'Log daily outflows and inspect month distribution.',
              icon: Icons.calendar_view_month_outlined,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
                  width: 140,
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
                  width: 180,
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
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(onPressed: vm.previousCalendarMonth, icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(
                    calendar['monthLabel'].toString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Sun'), Text('Mon'), Text('Tue'), Text('Wed'), Text('Thu'), Text('Fri'), Text('Sat')],
            ),
            const SizedBox(height: 6),
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    color: total > 0 ? const Color(0xFF2A3647) : const Color(0xFF151D2A),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${cell['day']}', style: const TextStyle(fontSize: 11)),
                      const Spacer(),
                      if (total > 0)
                        Text(vm.asCurrency(total), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'AI Advisor',
              subtitle: 'Generate recommendations and apply suggested allocations when relevant.',
              icon: Icons.psychology_alt_outlined,
            ),
            const SizedBox(height: 8),
            Text('Model: $geminiModel (local fallback enabled).', style: const TextStyle(fontSize: 12, color: Color(0xFF95A6B9))),
            if (vm.aiError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(vm.aiError, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: vm.aiLoading ? null : vm.runAiAdvisor,
                  icon: vm.aiLoading
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(vm.aiLoading ? 'Analyzing...' : 'Generate Plan'),
                ),
                const SizedBox(width: 8),
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
              const SizedBox(height: 6),
              Text(vm.aiResult!.summary),
              const SizedBox(height: 8),
              if (vm.aiResult!.recommendations.isNotEmpty)
                ...vm.aiResult!.recommendations.map((line) => Text('• $line')),
              if (vm.aiResult!.quickActions.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Quick Actions', style: TextStyle(fontWeight: FontWeight.w700)),
                ...vm.aiResult!.quickActions.map((line) => Text('• $line')),
              ],
              if (vm.aiResult!.suggestedPercents.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Suggested Allocation', style: TextStyle(fontWeight: FontWeight.w700)),
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
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHead(
                  title: 'Monthly Execution',
                  subtitle: 'Process month-end allocation and maintain reset controls.',
                  icon: Icons.schedule_send_outlined,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _DataMetric(label: 'Processed', value: '${vm.monthsProcessed}'),
                    _DataMetric(label: 'Purchase Spend', value: vm.asCurrency(vm.spentOnPurchases)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: vm.processMonth,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Process Month'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: vm.resetProgress,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset Progress'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
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
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHead(
                  title: 'Purchase History',
                  subtitle: 'Most recent completed goal purchases.',
                  icon: Icons.history,
                ),
                const SizedBox(height: 8),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 108),
      children: [
        _GlassCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Analytics Desk', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                SizedBox(height: 8),
                Text(
                  'Read spending outcomes and operational data through focused panels.',
                  style: TextStyle(color: Color(0xFF9BAABA), height: 1.35),
                ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(sections.length, (index) {
            return ChoiceChip(
              label: Text(sections[index]),
              selected: _section == index,
              onSelected: (_) => setState(() => _section = index),
            );
          }),
        ),
        const SizedBox(height: 12),
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
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHead(
                title: 'Analytics Snapshot',
                subtitle: 'Current state across expenses, purchases, and activity volume.',
                icon: Icons.dashboard_outlined,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionHead(
                title: 'Monthly Spend Trend',
                subtitle: 'Recent eight-month flow with relative intensity.',
                icon: Icons.timeline,
              ),
              const SizedBox(height: 8),
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
                        const SizedBox(height: 6),
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'Event Log',
              subtitle: 'Recent operational and user activity trail.',
              icon: Icons.list_alt_outlined,
            ),
            const SizedBox(height: 8),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: const Color(0xFFAEC0D2)),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xFF95A4B5), height: 1.3),
        ),
      ],
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFD9E2EC)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF121B28).withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(amount, style: const TextStyle(color: Color(0xFF9CADBE), fontSize: 12)),
              ],
            ),
          ),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF121B28).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFF95A5B6)),
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
    final base = color ?? const Color(0xFF111A27).withValues(alpha: 0.78);
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: base,
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF131B28).withValues(alpha: 0.82),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A2534),
            ),
            child: Icon(icon, color: const Color(0xFFC4CFDB), size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9AA8B8),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Text(
                    value,
                    key: ValueKey(value),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Color(0xFFE5EAF2),
                    ),
                  ),
                ),
              ],
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
    final ratio =
        maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0, 1).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 6,
        value: ratio,
        backgroundColor: const Color(0xFF1A2A39),
        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFA9B8CA)),
      ),
    );
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
    return Container(
      width: wide ? 196 : 132,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1825).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF98A7B8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFFE4EBF3),
            ),
          ),
        ],
      ),
    );
  }
}

class _StaggeredAppear extends StatefulWidget {
  const _StaggeredAppear({required this.child, required this.index});

  final Widget child;
  final int index;

  @override
  State<_StaggeredAppear> createState() => _StaggeredAppearState();
}

class _StaggeredAppearState extends State<_StaggeredAppear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    final delay = Duration(milliseconds: 20 + (widget.index * 14));
    Future<void>.delayed(delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.015),
      end: Offset.zero,
    ).animate(opacity);

    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(position: offset, child: widget.child),
    );
  }
}
