import 'dart:math' as math;

import 'package:budgie_flutter/core/constants/app_constants.dart';
import 'package:budgie_flutter/core/theme/app_surface_tint.dart';
import 'package:budgie_flutter/core/theme/app_tokens.dart';
import 'package:budgie_flutter/core/utils/helpers.dart';
import 'package:budgie_flutter/features/planner/application/planner_state.dart';
import 'package:budgie_flutter/features/planner/application/planner_view_model.dart';
import 'package:budgie_flutter/features/planner/data/sms_import_service.dart';
import 'package:budgie_flutter/features/planner/data/statement_import_service.dart';
import 'package:budgie_flutter/features/planner/domain/planner_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen>
    with WidgetsBindingObserver {
  bool _didInitialWidgetSync = false;
  bool _isQuickAddDialogOpen = false;
  final TextEditingController _quickAddAmountCtrl = TextEditingController();
  final TextEditingController _quickAddNoteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleSyncOnAppOpen();
  }

  @override
  void dispose() {
    _quickAddAmountCtrl.dispose();
    _quickAddNoteCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted ||
        state != AppLifecycleState.resumed ||
        _isQuickAddDialogOpen) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isQuickAddDialogOpen) {
        return;
      }
      context.read<PlannerViewModel>().syncPendingWidgetSpends();
    });
  }

  void _scheduleSyncOnAppOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _didInitialWidgetSync) {
        return;
      }

      final vm = context.read<PlannerViewModel>();
      if (vm.isHydrated) {
        _didInitialWidgetSync = true;
        vm.syncPendingWidgetSpends();
        return;
      }

      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted && !_didInitialWidgetSync) {
          _scheduleSyncOnAppOpen();
        }
      });
    });
  }

  Future<void> _openQuickDailyExpenseDialog(PlannerViewModel vm) async {
    if (_isQuickAddDialogOpen) {
      return;
    }

    _isQuickAddDialogOpen = true;
    try {
      await _showQuickDailyExpenseDialog(vm);
    } finally {
      _isQuickAddDialogOpen = false;
    }
  }

  Future<void> _showQuickDailyExpenseDialog(PlannerViewModel vm) async {
    if (!mounted) {
      return;
    }

    _quickAddAmountCtrl.clear();
    _quickAddNoteCtrl.clear();
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
                    controller: _quickAddAmountCtrl,
                    autofocus: true,
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
                    controller: _quickAddNoteCtrl,
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
                  onPressed: () => Navigator.of(dialogContext).maybePop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    final amountInput = _quickAddAmountCtrl.text.trim();
                    if (amountInput.isEmpty) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text('Please enter an amount.'),
                        ),
                      );
                      return;
                    }

                    vm.setDailySpendDate(selectedDate);
                    vm.dailySpendAmountCtrl.text = amountInput;
                    vm.dailySpendNoteCtrl.text = _quickAddNoteCtrl.text.trim();
                    final error = vm.addDailySpending();

                    Navigator.of(dialogContext).maybePop();
                    if (!mounted) {
                      return;
                    }

                    if (error != null) {
                      ScaffoldMessenger.maybeOf(
                        context,
                      )?.showSnackBar(SnackBar(content: Text(error)));
                    } else {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlannerViewModel, PlannerState>(
      builder: (context, _) {
        final vm = context.read<PlannerViewModel>();
        final textTheme = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(
            title: Text('Budgie', style: textTheme.titleLarge),
            actions: [
              IconButton(
                onPressed: () async {
                  final imported = await vm.syncPendingWidgetSpends();
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        imported > 0
                            ? 'Synced $imported widget entr${imported == 1 ? 'y' : 'ies'}.'
                            : 'No pending widget entries to sync.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.sync),
                tooltip: 'Sync widget data',
              ),
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
                    const SnackBar(
                      content: Text(
                        'Expense history JSON copied to clipboard.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Export expense history (copy JSON)',
              ),
              if (vm.firebaseReady)
                TextButton.icon(
                  onPressed: vm.authUser == null
                      ? vm.signInWithGoogle
                      : vm.signOut,
                  icon: Icon(vm.authUser == null ? Icons.login : Icons.logout),
                  label: Text(vm.authUser == null ? 'Login' : 'Logout'),
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
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
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
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: SizedBox(
                height: 84,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        child: NavigationBar(
                          height: 56,
                          selectedIndex: vm.activeTab,
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.savings),
                              label: 'Planner',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.analytics),
                              label: 'Analytics',
                            ),
                          ],
                          onDestinationSelected: vm.setTab,
                        ),
                      ),
                    ),
                    if (vm.isHydrated && vm.activeTab == 0)
                      Positioned(
                        top: -18,
                        child: FloatingActionButton(
                          onPressed: () => _openQuickDailyExpenseDialog(vm),
                          child: const Icon(Icons.add),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
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
  DateTime _smsImportFromDate = dateOnly(DateTime.now());
  DateTime _statementImportFromDate = dateOnly(DateTime.now());

  String _smsModeLabel(SmsImportMode mode) {
    switch (mode) {
      case SmsImportMode.today:
        return 'Today only';
      case SmsImportMode.fromDate:
        return 'From specific date';
      case SmsImportMode.newOnly:
        return 'Only new transactions';
    }
  }

  Future<void> _openSmsImportDialog(PlannerViewModel vm) async {
    if (Theme.of(context).platform != TargetPlatform.android) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS import is currently available only on Android.'),
        ),
      );
      return;
    }

    var hasPermission = await SmsImportService.hasPermission();
    if (!hasPermission) {
      hasPermission = await SmsImportService.requestPermission();
    }
    if (!mounted) {
      return;
    }

    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS permission is required to import UPI transactions.'),
        ),
      );
      return;
    }

    var mode = SmsImportMode.today;
    var includeDebits = true;
    var includeCredits = true;
    var loading = false;
    var error = '';
    var initialized = false;
    var candidates = <SmsImportTransaction>[];
    final selectedKeys = <String>{};

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> fetchCandidates() async {
              setDialogState(() {
                loading = true;
                error = '';
              });

              DateTime? startAt;
              if (mode == SmsImportMode.today) {
                startAt = dateOnly(DateTime.now());
              } else if (mode == SmsImportMode.fromDate) {
                startAt = dateOnly(_smsImportFromDate);
              }

              try {
                final results = await SmsImportService.fetchTransactions(
                  startAt: startAt,
                  includeDebits: includeDebits,
                  includeCredits: includeCredits,
                  excludeKeys: mode == SmsImportMode.newOnly
                      ? vm.importedSmsKeysView
                      : const <String>{},
                );

                if (!mounted) {
                  return;
                }

                setDialogState(() {
                  candidates = results;
                  selectedKeys
                    ..clear()
                    ..addAll(results.map((entry) => entry.sourceKey));
                  loading = false;
                });
              } catch (e) {
                if (!mounted) {
                  return;
                }
                setDialogState(() {
                  loading = false;
                  error = 'Unable to read SMS: $e';
                });
              }
            }

            if (!initialized) {
              initialized = true;
              Future<void>.microtask(fetchCandidates);
            }

            final canImport = !loading && selectedKeys.isNotEmpty;

            return AlertDialog(
              title: const Text('Import UPI SMS'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<SmsImportMode>(
                      initialValue: mode,
                      decoration: const InputDecoration(labelText: 'Import mode'),
                      items: SmsImportMode.values
                          .map(
                            (entry) => DropdownMenuItem<SmsImportMode>(
                              value: entry,
                              child: Text(_smsModeLabel(entry)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => mode = value);
                        fetchCandidates();
                      },
                    ),
                    if (mode == SmsImportMode.fromDate) ...[
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final chosen = await showDatePicker(
                            context: dialogContext,
                            initialDate: _smsImportFromDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (chosen != null) {
                            setDialogState(() {
                              _smsImportFromDate = chosen;
                            });
                            fetchCandidates();
                          }
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          DateFormat('dd MMM yyyy').format(_smsImportFromDate),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        FilterChip(
                          label: const Text('Debits'),
                          selected: includeDebits,
                          onSelected: (selected) {
                            if (!selected && !includeCredits) {
                              return;
                            }
                            setDialogState(() => includeDebits = selected);
                            fetchCandidates();
                          },
                        ),
                        FilterChip(
                          label: const Text('Credits'),
                          selected: includeCredits,
                          onSelected: (selected) {
                            if (!selected && !includeDebits) {
                              return;
                            }
                            setDialogState(() => includeCredits = selected);
                            fetchCandidates();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else if (error.isNotEmpty)
                      Text(
                        error,
                        style: Theme.of(
                          dialogContext,
                        ).textTheme.bodySmall?.copyWith(color: Theme.of(dialogContext).colorScheme.error),
                      )
                    else if (candidates.isEmpty)
                      const Text('No matching UPI SMS found for this filter.')
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: candidates.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final tx = candidates[index];
                            final selected = selectedKeys.contains(tx.sourceKey);
                            final isCredit = tx.direction == SmsImportDirection.credit;
                            final amountPrefix = isCredit ? '+' : '-';
                            final directionLabel = isCredit ? 'Credit' : 'Debit';

                            return CheckboxListTile(
                              value: selected,
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked ?? false) {
                                    selectedKeys.add(tx.sourceKey);
                                  } else {
                                    selectedKeys.remove(tx.sourceKey);
                                  }
                                });
                              },
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                              ),
                              title: Text(
                                '$amountPrefix${vm.asCurrency(tx.amount)} • $directionLabel',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              subtitle: Text(
                                '${DateFormat('dd MMM, hh:mm a').format(tx.timestamp)} • ${tx.sender.isEmpty ? 'Unknown sender' : tx.sender}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton.icon(
                  onPressed: loading ? null : fetchCandidates,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
                FilledButton.icon(
                  onPressed: canImport
                      ? () {
                          final selectedTransactions = candidates
                              .where(
                                (entry) => selectedKeys.contains(entry.sourceKey),
                              )
                              .toList(growable: false);

                          final result = vm.importSmsTransactions(
                            selectedTransactions,
                          );
                          Navigator.of(dialogContext).pop();
                          if (!mounted) {
                            return;
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Imported ${result.importedTotal} (${result.importedDebits} debits, ${result.importedCredits} credits). '
                                'Skipped ${result.skippedDuplicate} duplicates and ${result.skippedInvalid} invalid.',
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.file_download_done_outlined),
                  label: const Text('Import Selected'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openStatementImportDialog(PlannerViewModel vm) async {
    var mode = SmsImportMode.today;
    var includeDebits = true;
    var includeCredits = true;
    var loading = false;
    var error = '';
    var fileName = '';
    var candidates = <StatementImportTransaction>[];
    var debitColumnName = '';
    var creditColumnName = '';
    final selectedKeys = <String>{};

    Future<void> loadFile(StateSetter setDialogState) async {
      setDialogState(() {
        loading = true;
        error = '';
      });

      try {
        final normalizedDebit = debitColumnName.trim();
        final normalizedCredit = creditColumnName.trim();
        final result = await StatementImportService.pickAndParseStatement(
          debitColumnName: normalizedDebit.isEmpty ? null : normalizedDebit,
          creditColumnName: normalizedCredit.isEmpty ? null : normalizedCredit,
        );
        if (!mounted) {
          return;
        }

        if (result == null) {
          setDialogState(() {
            loading = false;
            error = 'No file selected.';
          });
          return;
        }

        setDialogState(() {
          fileName = result.fileName;
          candidates = result.transactions;
          selectedKeys
            ..clear()
            ..addAll(result.transactions.map((entry) => entry.sourceKey));
          loading = false;
        });
      } catch (e) {
        if (!mounted) {
          return;
        }
        setDialogState(() {
          loading = false;
          error = 'Could not parse statement file: $e';
        });
      }
    }

    List<StatementImportTransaction> filtered() {
      final today = dateOnly(DateTime.now());
      final startFrom = dateOnly(_statementImportFromDate);

      return candidates.where((entry) {
        if (mode == SmsImportMode.today && dateOnly(entry.timestamp) != today) {
          return false;
        }
        if (mode == SmsImportMode.fromDate && dateOnly(entry.timestamp).isBefore(startFrom)) {
          return false;
        }
        if (mode == SmsImportMode.newOnly && vm.importedStatementKeysView.contains(entry.sourceKey)) {
          return false;
        }
        if (!includeDebits && entry.direction == SmsImportDirection.debit) {
          return false;
        }
        if (!includeCredits && entry.direction == SmsImportDirection.credit) {
          return false;
        }
        return true;
      }).toList(growable: false);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final visible = filtered();
            final canImport = !loading && visible.any((entry) => selectedKeys.contains(entry.sourceKey));

            return AlertDialog(
              title: const Text('Import Statement (CSV/XLSX)'),
              content: SizedBox(
                width: 620,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: loading ? null : () => loadFile(setDialogState),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Choose file'),
                        ),
                        if (fileName.isNotEmpty)
                          Chip(label: Text(fileName, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: debitColumnName,
                            onChanged: (value) {
                              setDialogState(() => debitColumnName = value);
                            },
                            decoration: const InputDecoration(
                              labelText: 'Debit column name (optional)',
                              hintText: 'e.g. Withdrawal',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextFormField(
                            initialValue: creditColumnName,
                            onChanged: (value) {
                              setDialogState(() => creditColumnName = value);
                            },
                            decoration: const InputDecoration(
                              labelText: 'Credit column name (optional)',
                              hintText: 'e.g. Deposit',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Set custom debit/credit headers before choosing a file for non-standard bank statements.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<SmsImportMode>(
                      initialValue: mode,
                      decoration: const InputDecoration(labelText: 'Import mode'),
                      items: SmsImportMode.values
                          .map(
                            (entry) => DropdownMenuItem<SmsImportMode>(
                              value: entry,
                              child: Text(_smsModeLabel(entry)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() => mode = value);
                      },
                    ),
                    if (mode == SmsImportMode.fromDate) ...[
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: _statementImportFromDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setDialogState(() => _statementImportFromDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(DateFormat('dd MMM yyyy').format(_statementImportFromDate)),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        FilterChip(
                          label: const Text('Debits'),
                          selected: includeDebits,
                          onSelected: (selected) {
                            if (!selected && !includeCredits) {
                              return;
                            }
                            setDialogState(() => includeDebits = selected);
                          },
                        ),
                        FilterChip(
                          label: const Text('Credits'),
                          selected: includeCredits,
                          onSelected: (selected) {
                            if (!selected && !includeDebits) {
                              return;
                            }
                            setDialogState(() => includeCredits = selected);
                          },
                        ),
                        TextButton(
                          onPressed: visible.isEmpty
                              ? null
                              : () {
                                  setDialogState(() {
                                    final selectedVisible = visible.where(
                                      (entry) => selectedKeys.contains(entry.sourceKey),
                                    );
                                    final allSelected = selectedVisible.length == visible.length;
                                    if (allSelected) {
                                      selectedKeys.removeAll(visible.map((entry) => entry.sourceKey));
                                    } else {
                                      selectedKeys.addAll(visible.map((entry) => entry.sourceKey));
                                    }
                                  });
                                },
                          child: const Text('Toggle all'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else if (error.isNotEmpty)
                      Text(
                        error,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      )
                    else if (visible.isEmpty)
                      const Text('No matching rows found. Choose a file or adjust filters.')
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 320),
                        child: ListView.separated(
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final tx = visible[index];
                            final selected = selectedKeys.contains(tx.sourceKey);
                            return CheckboxListTile(
                              value: selected,
                              dense: true,
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked ?? false) {
                                    selectedKeys.add(tx.sourceKey);
                                  } else {
                                    selectedKeys.remove(tx.sourceKey);
                                  }
                                });
                              },
                              title: Text(
                                '${tx.direction == SmsImportDirection.credit ? '+' : '-'}${vm.asCurrency(tx.amount)} • ${tx.direction.name.toUpperCase()}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              subtitle: Text(
                                '${DateFormat('dd MMM yyyy').format(tx.timestamp)} • ${tx.description}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: canImport
                      ? () {
                          final picked = visible
                              .where((entry) => selectedKeys.contains(entry.sourceKey))
                              .toList(growable: false);
                          final result = vm.importStatementTransactions(picked);
                          Navigator.of(dialogContext).pop();
                          if (!mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Imported ${result.importedTotal} (${result.importedDebits} debits, ${result.importedCredits} credits). '
                                'Skipped ${result.skippedDuplicate} duplicates and ${result.skippedInvalid} invalid.',
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.file_download_done_outlined),
                  label: const Text('Import Selected'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showSalaryDialog(
    PlannerViewModel vm, {
    required String title,
    required String initialValue,
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    final isHandlingAction = ValueNotifier<bool>(false);

    void closeDialogSafely(BuildContext dialogContext) {
      if (!dialogContext.mounted) {
        return;
      }
      final navigator = Navigator.maybeOf(dialogContext);
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
      }
    }

    void commitSalary(BuildContext dialogContext) {
      if (isHandlingAction.value) {
        return;
      }
      isHandlingAction.value = true;
      vm.salaryCtrl.text = ctrl.text.trim();
      vm.updateSalaryFromInput();
      closeDialogSafely(dialogContext);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
            ],
            decoration: const InputDecoration(
              labelText: 'Monthly salary',
              hintText: 'Enter amount',
            ),
            onSubmitted: (_) => commitSalary(dialogContext),
          ),
          actions: [
            ValueListenableBuilder<bool>(
              valueListenable: isHandlingAction,
              builder: (context, busy, _) => TextButton(
                onPressed: busy ? null : () => closeDialogSafely(dialogContext),
                child: const Text('Cancel'),
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: isHandlingAction,
              builder: (context, busy, _) => FilledButton(
                onPressed: busy ? null : () => commitSalary(dialogContext),
                child: const Text('Save'),
              ),
            ),
          ],
        );
      },
    );

    isHandlingAction.dispose();
    ctrl.dispose();
  }

  _HeaderChipTone _cloudTone(String cloudStatus) {
    switch (cloudStatus.toLowerCase()) {
      case 'synced':
        return _HeaderChipTone.success;
      case 'syncing':
        return _HeaderChipTone.info;
      case 'error':
        return _HeaderChipTone.warning;
      default:
        return _HeaderChipTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final titles = ['Overview', 'Reccuring', 'Daily', 'Goals', 'Advisor', 'Run'];
    final icons = [
      Icons.space_dashboard_outlined,
      Icons.receipt_long_outlined,
      Icons.calendar_today_outlined,
      Icons.flag_circle_outlined,
      Icons.psychology_alt_outlined,
      Icons.play_circle_outline,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        108,
      ),
      children: [
        _HeroPanel(
          compact: _section != 0,
          monthLabel: 'Month #${vm.monthsProcessed}',
          title: 'Monthly finance snapshot',
          value: vm.asCurrency(vm.totalSavingsWithCurrentExcess),
          subtitle: 'Salary, spending, and runway at a glance.',
          chips: [
            _HeaderChip(
              label: 'Month #${vm.monthsProcessed}',
              icon: Icons.calendar_month,
              tone: _HeaderChipTone.info,
            ),
            _HeaderChip(
              label: 'Cloud ${vm.cloudStatus.toUpperCase()}',
              icon: Icons.cloud_done_outlined,
              tone: _cloudTone(vm.cloudStatus),
            ),
            _HeaderChip(
              label: 'Undo ${vm.undoDepth}',
              icon: Icons.undo,
              tone: vm.undoDepth > 0
                  ? _HeaderChipTone.info
                  : _HeaderChipTone.neutral,
            ),
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
            padding: const EdgeInsets.all(AppSpacing.panel),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHead(
                  title: 'Sections',
                  subtitle: 'Move between overview, recurring, daily, goals, and more.',
                  icon: Icons.explore_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
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
              ],
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
        return _PlannerOverview(
          vm: vm,
          onAddSalary: () => _showSalaryDialog(
            vm,
            title: 'Add salary',
            initialValue: '',
          ),
          onEditSalary: () => _showSalaryDialog(
            vm,
            title: 'Edit salary',
            initialValue: vm.salary > 0 ? vm.salary.toStringAsFixed(0) : '',
          ),
        );
      case 1:
        return _PlannerExpenses(vm: vm);
      case 2:
        return _PlannerDaily(
          vm: vm,
          onImportSms: () => _openSmsImportDialog(vm),
          onImportStatement: () => _openStatementImportDialog(vm),
        );
      case 3:
        return _PlannerGoals(vm: vm);
      case 4:
        return _PlannerAdvisor(vm: vm);
      case 5:
      default:
        return _PlannerRun(vm: vm);
    }
  }
}

class _PlannerOverview extends StatelessWidget {
  const _PlannerOverview({
    required this.vm,
    this.onAddSalary,
    this.onEditSalary,
  });

  final PlannerViewModel vm;
  final VoidCallback? onAddSalary;
  final VoidCallback? onEditSalary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final expenseRatio = vm.salary <= 0
        ? 0.0
        : (vm.monthlyExpenseTotal / vm.salary).clamp(0, 1).toDouble();
    final savingsRate = vm.salary <= 0
        ? 0.0
        : (vm.monthlyPool / vm.salary).clamp(0, 1).toDouble();

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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxs,
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _OverviewStatusPill(
                    icon: Icons.favorite_outline,
                    label: 'Health',
                    value: healthLabel,
                    color: healthColor,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _OverviewStatusPill(
                    icon: Icons.percent,
                    label: 'Savings Rate',
                    value: '${(savingsRate * 100).toStringAsFixed(1)}%',
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _OverviewStatusPill(
                    icon: Icons.speed_outlined,
                    label: 'Burn Ratio',
                    value: '${(expenseRatio * 100).toStringAsFixed(1)}%',
                    color: scheme.tertiary,
                  ),
                ),
              ],
            ),
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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Monthly Salary',
                          style: text.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          vm.salary > 0 ? vm.asCurrency(vm.salary) : 'Not set',
                          style: text.titleLarge?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: onAddSalary,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                      ),
                      TextButton.icon(
                        onPressed: onEditSalary,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Budget Breakdown',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
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
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 11, color: color),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
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
    final leftRatio = total <= 0
        ? 0.5
        : (leftValue / total).clamp(0, 1).toDouble();

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
                style: text.titleSmall?.copyWith(color: scheme.onSurface),
              ),
            ),
            Expanded(
              child: Text(
                format(rightValue),
                textAlign: TextAlign.right,
                style: text.titleSmall?.copyWith(color: scheme.onSurface),
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
              subtitle:
                  'Add your recurring monthly expenses here. We use this list to calculate your monthly pool.',
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
              subtitle:
                  'Create goals and review per-goal monthly allocation output.',
              icon: Icons.flag_outlined,
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _DataMetric(
                  label: 'Fixed Input',
                  value: '${alloc.fixedPercentInput.toStringAsFixed(1)}%',
                ),
                _DataMetric(
                  label: 'Applied %',
                  value: '${alloc.fixedPercentApplied.toStringAsFixed(1)}%',
                ),
                _DataMetric(
                  label: 'Scaling',
                  value: alloc.scalingApplied ? 'Enabled' : 'Normal',
                ),
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
                DropdownMenuItem(
                  value: GoalPriority.medium,
                  child: Text('Medium'),
                ),
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
                final progress = goal.target <= 0
                    ? 0.0
                    : (goal.saved / goal.target).clamp(0, 1).toDouble();
                return _GlassCard(
                  margin: const EdgeInsets.symmetric(
                    vertical: AppSpacing.compact,
                  ),
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
                            IconButton(
                              onPressed: () => vm.removeGoal(goal.id),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            _DataMetric(
                              label: 'Saved',
                              value: vm.asCurrency(goal.saved),
                            ),
                            _DataMetric(
                              label: 'Target',
                              value: vm.asCurrency(goal.target),
                            ),
                            _DataMetric(
                              label: 'Planned',
                              value: vm.asCurrency(planned),
                            ),
                            _DataMetric(
                              label: 'Priority',
                              value: goal.priority.name.toUpperCase(),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _SquigglyProgressBar(
                          value: progress,
                          height: AppSpacing.sm,
                          trackColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
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
  const _PlannerDaily({required this.vm, this.onImportSms, this.onImportStatement});

  final PlannerViewModel vm;
  final Future<void> Function()? onImportSms;
  final Future<void> Function()? onImportStatement;

  static const List<String> _weekLabels = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  double _amountFontSize(String amountLabel) {
    final length = amountLabel.length;
    if (length >= 16) {
      return 8;
    }
    if (length >= 13) {
      return 9;
    }
    if (length >= 10) {
      return 10;
    }
    return 11;
  }

  String _signedCurrency(double value) {
    if (value == 0) {
      return vm.asCurrency(0);
    }
    return '${value > 0 ? '+' : '-'}${vm.asCurrency(value.abs())}';
  }

  Future<void> _showDaySpendingsPopup(
    BuildContext context, {
    required DateTime date,
  }) async {
    final selectedDay = dateOnly(date);
    final items = <_DaySpendingItem>[];

    for (final spend in vm.dailySpends) {
      if (dateOnly(spend.date) != selectedDay) {
        continue;
      }
      items.add(
        _DaySpendingItem(
          time: spend.date,
          label: spend.note.trim().isEmpty ? 'Daily spend' : spend.note.trim(),
          amount: spend.amount,
          sourceLabel: 'Daily',
          icon: Icons.payments_outlined,
          isCredit: false,
        ),
      );
    }

    for (final purchase in vm.purchaseHistory) {
      if (dateOnly(purchase.purchasedAt) != selectedDay) {
        continue;
      }
      items.add(
        _DaySpendingItem(
          time: purchase.purchasedAt,
          label: purchase.goalName,
          amount: purchase.amount,
          sourceLabel: 'Purchase',
          icon: Icons.shopping_bag_outlined,
          isCredit: false,
        ),
      );
    }

    for (final log in vm.logs) {
      final isImportedCredit = log.type == EventType.system &&
          log.amount != null &&
          log.amount! > 0 &&
          log.message.toLowerCase().contains('credit imported');
      if (!isImportedCredit) {
        continue;
      }

      final metaTimestamp = (log.meta?['timestamp'] ?? '').toString();
      final creditTime = DateTime.tryParse(metaTimestamp) ?? log.ts;
      if (dateOnly(creditTime) != selectedDay) {
        continue;
      }

      final source = (log.meta?['source'] ?? '').toString();
      final sourceLabel = source == 'SMS_IMPORT'
          ? 'SMS Credit'
          : source == 'STATEMENT_IMPORT'
          ? 'Statement Credit'
          : 'Credit';

      items.add(
        _DaySpendingItem(
          time: creditTime,
          label: log.message,
          amount: log.amount!,
          sourceLabel: sourceLabel,
          icon: Icons.south_west_outlined,
          isCredit: true,
        ),
      );
    }

    items.sort((a, b) => b.time.compareTo(a.time));
    final debitTotal = items
        .where((item) => !item.isCredit)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final creditTotal = items
        .where((item) => item.isCredit)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final net = creditTotal - debitTotal;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(DateFormat('dd MMM yyyy').format(selectedDay)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Debits ${vm.asCurrency(debitTotal)} • Credits ${vm.asCurrency(creditTotal)}',
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Net ${net >= 0 ? '+' : '-'}${vm.asCurrency(net.abs())}',
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (items.isEmpty)
                  const Text('No spendings on this day.')
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: 2,
                          ),
                          leading: Icon(item.icon, size: 18),
                          title: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${item.sourceLabel} • ${item.isCredit ? 'Credit' : 'Debit'}',
                          ),
                          trailing: Text(
                            '${item.isCredit ? '+' : '-'}${vm.asCurrency(item.amount)}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: item.isCredit
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

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
                  label: Text(
                    DateFormat('dd MMM yyyy').format(vm.dailySpendDate),
                  ),
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
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
                  icon: const Icon(Icons.add_chart_outlined),
                  label: const Text('Log Entry'),
                ),
                OutlinedButton.icon(
                  onPressed: onImportSms,
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('Import SMS'),
                ),
                OutlinedButton.icon(
                  onPressed: onImportStatement,
                  icon: const Icon(Icons.table_view_outlined),
                  label: const Text('Import Statement'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                IconButton(
                  onPressed: vm.previousCalendarMonth,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    calendar['monthLabel'].toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  onPressed: vm.nextCalendarMonth,
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton.icon(
                  onPressed: vm.resetCalendarMonth,
                  icon: const Icon(Icons.today),
                  label: const Text('Today'),
                ),
              ],
            ),
            _DataMetric(
              label: 'Month Net',
              value: _signedCurrency(toDoubleValue(calendar['monthTotal'])),
              wide: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: _weekLabels.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 2.8,
                crossAxisSpacing: 5,
                mainAxisSpacing: 0,
              ),
              itemBuilder: (context, index) {
                return Center(
                  child: Text(
                    _weekLabels[index],
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              },
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
                final debit = toDoubleValue(cell['debit']);
                final credit = toDoubleValue(cell['credit']);
                final net = toDoubleValue(cell['total']);
                final hasActivity = debit > 0 || credit > 0;
                final amountLabel = _signedCurrency(net);
                final day = (cell['day'] as num).toInt();
                final tileColor = !hasActivity
                    ? Theme.of(context).colorScheme.surfaceContainer
                    : credit > 0 && debit == 0
                    ? Theme.of(context).colorScheme.primaryContainer
                    : debit > 0 && credit == 0
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.tertiaryContainer;

                return Material(
                  color: tileColor,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () => _showDaySpendingsPopup(
                      context,
                      date: DateTime(vm.calendarMonth.year, vm.calendarMonth.month, day),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.compact),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              '$day',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                          if (hasActivity)
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: SizedBox(
                                width: double.infinity,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    amountLabel,
                                    maxLines: 1,
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      fontSize: _amountFontSize(amountLabel),
                                      color: net > 0
                                          ? Theme.of(context).colorScheme.primary
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
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

class _DaySpendingItem {
  const _DaySpendingItem({
    required this.time,
    required this.label,
    required this.amount,
    required this.sourceLabel,
    required this.icon,
    required this.isCredit,
  });

  final DateTime time;
  final String label;
  final double amount;
  final String sourceLabel;
  final IconData icon;
  final bool isCredit;
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
              subtitle:
                  'Generate recommendations and apply suggested allocations when relevant.',
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
                child: Text(
                  vm.aiError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: vm.aiLoading ? null : vm.runAiAdvisor,
                  icon: vm.aiLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(vm.aiLoading ? 'Analyzing...' : 'Generate Plan'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(
                  onPressed: vm.aiResult == null
                      ? null
                      : vm.applyAiPercentSuggestions,
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
              _DataMetric(
                label: 'Source',
                value: vm.aiResult!.source.toUpperCase(),
                wide: true,
              ),
              const SizedBox(height: AppSpacing.compact),
              Text(vm.aiResult!.summary),
              const SizedBox(height: AppSpacing.sm),
              if (vm.aiResult!.recommendations.isNotEmpty)
                ...vm.aiResult!.recommendations.map((line) => Text('• $line')),
              if (vm.aiResult!.quickActions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Quick Actions',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                ...vm.aiResult!.quickActions.map((line) => Text('• $line')),
              ],
              if (vm.aiResult!.suggestedPercents.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Suggested Allocation',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                ...vm.aiResult!.suggestedPercents.map(
                  (entry) => Text(
                    '${entry.goalName}: ${entry.percent.toStringAsFixed(1)}%',
                  ),
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
                  subtitle:
                      'Process month-end allocation and maintain reset controls.',
                  icon: Icons.schedule_send_outlined,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _DataMetric(
                      label: 'Processed',
                      value: '${vm.monthsProcessed}',
                    ),
                    _DataMetric(
                      label: 'Purchase Spend',
                      value: vm.asCurrency(vm.spentOnPurchases),
                    ),
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
                  ...vm.purchaseHistory
                      .take(8)
                      .map(
                        (entry) => ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: 4,
                          ),
                          visualDensity: VisualDensity.compact,
                          minTileHeight: 42,
                          title: Text(entry.goalName),
                          subtitle: Text(
                            DateFormat('dd MMM yyyy').format(entry.purchasedAt),
                          ),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        108,
      ),
      children: [
        _HeroPanel(
          compact: false,
          monthLabel: 'Analytics',
          title: 'Activity snapshot',
          value: '${vm.logs.length} events',
          subtitle: 'Recent expenses, purchases, and planner activity.',
          chips: const [
            _HeaderChip(label: 'Snapshot', icon: Icons.dashboard_outlined),
            _HeaderChip(label: 'Trend', icon: Icons.timeline),
            _HeaderChip(label: 'Logs', icon: Icons.list_alt_outlined),
          ],
        ),
        _GlassCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
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
        .where(
          (entry) =>
              entry.type == EventType.expense &&
              entry.message.toLowerCase().contains('added'),
        )
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
      trendByMonth[key] = round2(
        (trendByMonth[key] ?? 0) + (entry.amount ?? 0),
      );
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
                subtitle:
                    'Current state across expenses, purchases, and activity volume.',
                icon: Icons.dashboard_outlined,
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _DataMetric(
                    label: 'Expenses Added',
                    value: vm.asCurrency(expenseAdded),
                  ),
                  _DataMetric(
                    label: 'Purchases',
                    value: vm.asCurrency(purchases),
                  ),
                  _DataMetric(
                    label: 'Active Goals',
                    value: '${vm.goals.length}',
                  ),
                  _DataMetric(
                    label: 'Daily Entries',
                    value: '${vm.dailySpends.length}',
                  ),
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
                  final label = labelDate == null
                      ? key
                      : DateFormat('MMM yyyy').format(labelDate);
                  final amount = trendByMonth[key] ?? 0;
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 4,
                    ),
                    visualDensity: VisualDensity.compact,
                    minTileHeight: 42,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label),
                        const SizedBox(height: AppSpacing.compact),
                        _MiniTrendBar(
                          value: amount,
                          maxValue: monthRows
                              .map((monthKey) => trendByMonth[monthKey] ?? 0)
                              .fold<double>(
                                1,
                                (max, value) => value > max ? value : max,
                              ),
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,
                  minTileHeight: 42,
                  title: Text(entry.message),
                  subtitle: Text(
                    '${entry.type.name.toUpperCase()} | ${DateFormat('dd MMM HH:mm').format(entry.ts)}',
                  ),
                  trailing: entry.amount == null
                      ? null
                      : Text(vm.asCurrency(entry.amount!)),
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
          style: text.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _HeroPanel extends StatefulWidget {
  const _HeroPanel({
    required this.compact,
    required this.monthLabel,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.chips,
  });

  final bool compact;
  final String monthLabel;
  final String title;
  final String value;
  final String subtitle;
  final List<Widget> chips;

  @override
  State<_HeroPanel> createState() => _HeroPanelState();
}

class _HeroPanelState extends State<_HeroPanel> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AnimatedSize(
      duration: AppDuration.medium,
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AppDuration.medium,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          );
          final slide =
              Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );

          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
        child: Container(
          key: ValueKey(widget.compact),
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: EdgeInsets.all(
            widget.compact ? AppSpacing.md : AppSpacing.panel,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            color: widget.compact
                ? scheme.surfaceContainerHigh
                : scheme.surfaceContainerLow,
            border: Border.all(
              color: scheme.outlineVariant.withValues(
                alpha: widget.compact ? 0.24 : 0.32,
              ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: widget.compact ? -6 : -18,
                top: widget.compact ? -6 : -12,
                child: AnimatedContainer(
                  duration: AppDuration.medium,
                  curve: Curves.easeOutCubic,
                  width: widget.compact ? 56 : 112,
                  height: widget.compact ? 56 : 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(
                      alpha: widget.compact ? 0.05 : 0.08,
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedContainer(
                        duration: AppDuration.medium,
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.all(
                          widget.compact
                              ? AppSpacing.xs + 1
                              : AppSpacing.sm + 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.auto_graph_outlined,
                          color: scheme.primary,
                          size: widget.compact ? 16 : 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: widget.compact ? 3 : 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                              ),
                              child: Text(
                                widget.monthLabel,
                                style: text.labelSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.title,
                              maxLines: widget.compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                fontSize: widget.compact ? 16 : null,
                              ),
                            ),
                            if (widget.compact) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.full,
                                  ),
                                ),
                                child: Text(
                                  widget.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (widget.compact) ...[
                        const SizedBox(width: AppSpacing.sm),
                        AnimatedContainer(
                          duration: AppDuration.medium,
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm + 1,
                            vertical: AppSpacing.xs + 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.32,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.savings_outlined,
                                    size: 13,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Total',
                                    style: text.labelSmall?.copyWith(
                                      color: scheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.value,
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: scheme.onSecondaryContainer,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      widget.value,
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      widget.subtitle,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  AnimatedContainer(
                    duration: AppDuration.medium,
                    curve: Curves.easeOutCubic,
                    width: double.infinity,
                    padding: EdgeInsets.all(
                      widget.compact ? AppSpacing.xs + 2 : AppSpacing.sm + 1,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(
                          alpha: widget.compact ? 0.24 : 0.32,
                        ),
                      ),
                    ),
                    child: Wrap(
                      spacing: widget.compact ? 6 : AppSpacing.xs,
                      runSpacing: widget.compact ? 6 : AppSpacing.xs,
                      children: widget.chips,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _HeaderChipTone { neutral, info, success, warning }

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.label,
    required this.icon,
    this.tone = _HeaderChipTone.neutral,
  });

  final String label;
  final IconData icon;
  final _HeaderChipTone tone;

  Color _chipContainer(ColorScheme scheme) {
    switch (tone) {
      case _HeaderChipTone.info:
        return scheme.primaryContainer;
      case _HeaderChipTone.success:
        return scheme.tertiaryContainer;
      case _HeaderChipTone.warning:
        return scheme.errorContainer;
      case _HeaderChipTone.neutral:
        return scheme.surfaceContainerHighest;
    }
  }

  Color _chipForeground(ColorScheme scheme) {
    switch (tone) {
      case _HeaderChipTone.info:
        return scheme.onPrimaryContainer;
      case _HeaderChipTone.success:
        return scheme.onTertiaryContainer;
      case _HeaderChipTone.warning:
        return scheme.onErrorContainer;
      case _HeaderChipTone.neutral:
        return scheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final container = _chipContainer(scheme);
    final foreground = _chipForeground(scheme);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.full),
        color: container,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 14, color: foreground),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppSurfaceTint.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        title: Text(
          name,
          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          amount,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        trailing: IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 1,
      ),
      decoration: BoxDecoration(
        color: AppSurfaceTint.card(scheme),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child, this.margin, this.color});

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppDuration.short,
      margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        color: color ?? AppSurfaceTint.card(scheme),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: child,
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
    final ratio = maxValue <= 0
        ? 0.0
        : (value / maxValue).clamp(0, 1).toDouble();
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
    return SizedBox(
      width: wide ? AppSize.metricWide : AppSize.metricCompact,
      child: Container(
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: AppSurfaceTint.card(scheme),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 1,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: text.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
