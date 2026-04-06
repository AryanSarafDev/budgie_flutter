import 'dart:async';
import 'dart:convert';

import 'package:budgie_flutter/app/bootstrap/firebase_bootstrap.dart';
import 'package:budgie_flutter/core/constants/app_constants.dart';
import 'package:budgie_flutter/core/utils/helpers.dart';
import 'package:budgie_flutter/features/planner/application/planner_state.dart';
import 'package:budgie_flutter/features/planner/domain/allocation.dart';
import 'package:budgie_flutter/features/planner/domain/planner_models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class PlannerViewModel extends Cubit<PlannerState> {
  PlannerViewModel() : super(const PlannerState.initial());

  final _uuid = const Uuid();

  double salary = 0;
  List<ExpenseItem> expenses = [];
  List<GoalItem> goals = [];
  int monthsProcessed = 0;
  double monthPoolSpent = 0;
  double extraSavings = 0;
  double spentOnPurchases = 0;
  List<PurchaseEntry> purchaseHistory = [];
  List<EventLog> logs = [];
  List<DailySpendEntry> dailySpends = [];

  bool isHydrated = false;
  bool firebaseReady = FirebaseBootstrap.initialized;
  bool cloudLoadDone = false;
  String cloudStatus = 'local';
  String authError = '';

  int activeTab = 0;
  User? authUser;
  StreamSubscription<User?>? _authSub;
  Timer? _cloudSaveDebounce;

  final salaryCtrl = TextEditingController();
  final expenseNameCtrl = TextEditingController();
  final expenseAmountCtrl = TextEditingController();
  final goalNameCtrl = TextEditingController();
  final goalTargetCtrl = TextEditingController();
  final goalPercentCtrl = TextEditingController();
  final dailySpendAmountCtrl = TextEditingController();
  final dailySpendNoteCtrl = TextEditingController();

  GoalPriority goalPriority = GoalPriority.medium;
  DateTime dailySpendDate = dateOnly(DateTime.now());
  DateTime calendarMonth = monthStart(DateTime.now());

  String aiError = '';
  bool aiLoading = false;
  String aiRawText = '';
  AdvisorResult? aiResult;
  int _lastAiRequestAt = 0;
  int _geminiBlockedUntil = 0;
  bool _aiRequestLock = false;
  bool _widgetSyncInProgress = false;
  bool _cloudHydrateInProgress = false;

  final List<PlannerSnapshot> _undoStack = [];

  void _emitState() {
    if (!isClosed) {
      emit(state.bump());
    }
  }

  NumberFormat get _currencyFmt =>
      NumberFormat.currency(locale: 'en_IN', symbol: 'INR ', decimalDigits: 0);

  String asCurrency(double value) => _currencyFmt.format(value);

  double get monthlyExpenseTotal {
    return round2(expenses.fold(0, (total, item) => total + item.amount));
  }

  double get monthlyPool {
    return round2((salary - monthlyExpenseTotal).clamp(0, double.infinity));
  }

  double get availableMonthExcess {
    return round2((monthlyPool - monthPoolSpent).clamp(0, double.infinity));
  }

  double get effectivePlanningPool => availableMonthExcess;

  double get totalGoalSavings {
    return round2(goals.fold(0, (total, goal) => total + goal.saved));
  }

  double get totalSavings => round2(totalGoalSavings + extraSavings);

  double get totalSavingsWithCurrentExcess {
    return round2(totalSavings + availableMonthExcess);
  }

  int get undoDepth => _undoStack.length;

  AllocationResult get allocation =>
      calculateAllocation(effectivePlanningPool, goals);

  List<MapEntry<GoalItem, double>> get plannedAllocation {
    return goals
        .map((goal) {
          return MapEntry(goal, allocation.allocationByGoalId[goal.id] ?? 0);
        })
        .toList(growable: false);
  }

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _applyPayload(decoded);
      }
    }

    var importedCount = 0;
    try {
      _widgetSyncInProgress = true;
      importedCount = await _consumeWidgetSpendEvents(prefs);
    } finally {
      _widgetSyncInProgress = false;
    }
    if (importedCount > 0) {
      await prefs.setString(storageKey, jsonEncode(_buildPayload()));
    }

    salaryCtrl.text = salary <= 0 ? '' : salary.toStringAsFixed(0);
    isHydrated = true;
    _emitState();

    if (!firebaseReady) {
      cloudLoadDone = true;
      cloudStatus = 'local';
      _emitState();
      return;
    }

    authUser = FirebaseAuth.instance.currentUser;

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      authUser = user;
      authError = '';
      _emitState();
      await _hydrateFromCloud();
    });

    await _hydrateFromCloud();
  }

  Future<int> syncPendingWidgetSpends() async {
    if (!isHydrated || _widgetSyncInProgress) {
      return 0;
    }

    _widgetSyncInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final importedCount = await _consumeWidgetSpendEvents(prefs);
      if (importedCount > 0) {
        _save();
        _emitState();
      }
      return importedCount;
    } finally {
      _widgetSyncInProgress = false;
    }
  }

  Future<void> signInWithGoogle() async {
    if (!firebaseReady) {
      authError = 'Firebase is not configured. Add FIREBASE_* dart-defines.';
      _emitState();
      return;
    }

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
        return;
      }

      await FirebaseBootstrap.ensureGoogleSignInInitialized();
      final account = await GoogleSignIn.instance.authenticate();
      final authData = account.authentication;

      if (authData.idToken == null || authData.idToken!.isEmpty) {
        authError =
            'Google sign-in did not return an ID token. Verify Firebase/Google OAuth app setup.';
        _emitState();
        return;
      }

      final credential = GoogleAuthProvider.credential(
        idToken: authData.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      authError = 'Google sign-in failed: $e';
      _emitState();
    }
  }

  Future<void> signOut() async {
    if (!firebaseReady) {
      return;
    }

    await FirebaseAuth.instance.signOut();
    await GoogleSignIn.instance.signOut();
  }

  Future<void> _hydrateFromCloud() async {
    if (_cloudHydrateInProgress) {
      return;
    }

    if (!firebaseReady || authUser == null) {
      cloudLoadDone = true;
      cloudStatus = 'local';
      _emitState();
      return;
    }

    _cloudHydrateInProgress = true;
    cloudLoadDone = false;
    cloudStatus = 'syncing';
    _emitState();

    var importedFromWidgetAfterCloud = 0;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('budgieUsers')
          .doc(authUser!.uid)
          .get();
      final plannerState = snap.data()?['plannerState'];
      if (plannerState is Map<String, dynamic>) {
        _applyPayload(plannerState);
      } else if (plannerState is Map) {
        _applyPayload(Map<String, dynamic>.from(plannerState));
      }

      // Re-apply any pending widget events after cloud payload to avoid
      // cloud hydration overwriting widget-originated local events.
      final prefs = await SharedPreferences.getInstance();
      try {
        _widgetSyncInProgress = true;
        importedFromWidgetAfterCloud = await _consumeWidgetSpendEvents(prefs);
      } finally {
        _widgetSyncInProgress = false;
      }
      if (importedFromWidgetAfterCloud > 0) {
        await prefs.setString(storageKey, jsonEncode(_buildPayload()));
      }

      cloudStatus = 'synced';
    } catch (_) {
      cloudStatus = 'error';
      authError = 'Cloud load failed. Using local data.';
    } finally {
      _cloudHydrateInProgress = false;
      cloudLoadDone = true;
      _emitState();
    }

    if (importedFromWidgetAfterCloud > 0 && cloudStatus == 'synced') {
      await _save();
    }
  }

  void setTab(int index) {
    activeTab = index;
    _emitState();
  }

  void changeGoalPriority(GoalPriority priority) {
    goalPriority = priority;
    _emitState();
  }

  void _pushUndo() {
    final snapshot = PlannerSnapshot(
      salary: salary,
      expenses: [...expenses],
      goals: [...goals],
      monthsProcessed: monthsProcessed,
      monthPoolSpent: monthPoolSpent,
      extraSavings: extraSavings,
      spentOnPurchases: spentOnPurchases,
      purchaseHistory: [...purchaseHistory],
      logs: [...logs],
      dailySpends: [...dailySpends],
      salaryInput: salaryCtrl.text,
      goalPriority: goalPriority,
    );

    _undoStack.add(snapshot);
    if (_undoStack.length > maxUndoSteps) {
      _undoStack.removeAt(0);
    }
  }

  void undoLastAction() {
    if (_undoStack.isEmpty) {
      return;
    }

    final snapshot = _undoStack.removeLast();
    salary = snapshot.salary;
    expenses = snapshot.expenses;
    goals = snapshot.goals;
    monthsProcessed = snapshot.monthsProcessed;
    monthPoolSpent = snapshot.monthPoolSpent;
    extraSavings = snapshot.extraSavings;
    spentOnPurchases = snapshot.spentOnPurchases;
    purchaseHistory = snapshot.purchaseHistory;
    logs = snapshot.logs;
    dailySpends = snapshot.dailySpends;
    salaryCtrl.text = snapshot.salaryInput;
    goalPriority = snapshot.goalPriority;

    _save();
    _emitState();
  }

  void updateSalaryFromInput() {
    final value = toDoubleValue(salaryCtrl.text);
    _pushUndo();
    salary = value.clamp(0, double.infinity);
    _addLog(EventType.system, 'Salary updated.', amount: salary);
    _save();
    _emitState();
  }

  void addExpense() {
    final name = expenseNameCtrl.text.trim();
    final amount = toDoubleValue(expenseAmountCtrl.text);
    if (name.isEmpty || amount <= 0) {
      return;
    }

    _pushUndo();
    expenses = [
      ...expenses,
      ExpenseItem(id: _uuid.v4(), name: name, amount: amount),
    ];

    expenseNameCtrl.clear();
    expenseAmountCtrl.clear();

    _addLog(EventType.expense, 'Expense added: $name', amount: amount);
    _save();
    _emitState();
  }

  void removeExpense(String id) {
    final target = firstOrNull(expenses.where((item) => item.id == id));
    if (target == null) {
      return;
    }

    _pushUndo();
    expenses = expenses.where((item) => item.id != id).toList(growable: false);

    _addLog(
      EventType.expense,
      'Expense removed: ${target.name}.',
      amount: target.amount,
    );
    _save();
    _emitState();
  }

  void addGoal() {
    final name = goalNameCtrl.text.trim();
    final target = toDoubleValue(goalTargetCtrl.text);
    final percent = toDoubleValue(
      goalPercentCtrl.text,
    ).clamp(0, 100).toDouble();

    if (name.isEmpty || target <= 0) {
      return;
    }

    _pushUndo();
    goals = [
      ...goals,
      GoalItem(
        id: _uuid.v4(),
        name: name,
        target: target,
        saved: 0,
        priority: goalPriority,
        percent: percent,
      ),
    ];

    goalNameCtrl.clear();
    goalTargetCtrl.clear();
    goalPercentCtrl.clear();
    goalPriority = GoalPriority.medium;

    _addLog(
      EventType.goal,
      'Goal created: $name',
      amount: target,
      meta: {'priority': goalPriority.name, 'percent': percent},
    );
    _save();
    _emitState();
  }

  void removeGoal(String id) {
    final target = firstOrNull(goals.where((item) => item.id == id));
    if (target == null) {
      return;
    }

    _pushUndo();
    goals = goals.where((item) => item.id != id).toList(growable: false);

    _addLog(EventType.goal, 'Goal removed: ${target.name}');
    _save();
    _emitState();
  }

  void processMonth() {
    _pushUndo();
    _addLog(
      EventType.system,
      'Monthly processing started.',
      meta: {'pool': effectivePlanningPool, 'goalCount': goals.length},
    );

    final result = calculateAllocation(effectivePlanningPool, goals);
    var overflow = 0.0;

    goals = goals
        .map((goal) {
          final grant = result.allocationByGoalId[goal.id] ?? 0;
          if (grant <= 0) {
            return goal;
          }

          final nextSaved = goal.saved + grant;
          if (nextSaved > goal.target) {
            overflow += nextSaved - goal.target;
          }

          return goal.copyWith(saved: round2(nextSaved.clamp(0, goal.target)));
        })
        .toList(growable: false);

    monthsProcessed += 1;
    extraSavings = round2(extraSavings + result.unassigned + overflow);
    monthPoolSpent = 0;

    _addLog(
      EventType.system,
      'Monthly processing completed.',
      meta: {'overflow': overflow, 'unassigned': result.unassigned},
    );
    _save();
    _emitState();
  }

  void buyGoal(String id) {
    final goal = firstOrNull(goals.where((item) => item.id == id));
    if (goal == null) {
      return;
    }

    final remainingToFund = round2(
      (goal.target - goal.saved).clamp(0, double.infinity),
    );
    final availableInstant = round2(extraSavings + availableMonthExcess);

    if (availableInstant + 0.01 < remainingToFund) {
      aiError = 'Not enough available savings to buy this goal yet.';
      _addLog(
        EventType.purchase,
        'Purchase blocked for ${goal.name}.',
        meta: {'needed': remainingToFund, 'available': availableInstant},
      );
      _emitState();
      return;
    }

    _pushUndo();

    if (remainingToFund > 0) {
      var stillNeeded = remainingToFund;
      final useFromExtra = stillNeeded < extraSavings
          ? stillNeeded
          : extraSavings;
      stillNeeded = round2(stillNeeded - useFromExtra);
      extraSavings = round2(
        (extraSavings - useFromExtra).clamp(0, double.infinity),
      );

      if (stillNeeded > 0) {
        monthPoolSpent = round2(monthPoolSpent + stillNeeded);
      }
    }

    spentOnPurchases = round2(spentOnPurchases + goal.target);
    purchaseHistory = [
      PurchaseEntry(
        id: _uuid.v4(),
        goalName: goal.name,
        amount: goal.target,
        purchasedAt: DateTime.now(),
      ),
      ...purchaseHistory,
    ];

    goals = goals.where((item) => item.id != id).toList(growable: false);

    _addLog(
      EventType.purchase,
      'Goal purchased: ${goal.name}',
      amount: goal.target,
    );
    _save();
    _emitState();
  }

  void resetProgress() {
    _pushUndo();
    goals = goals
        .map((item) => item.copyWith(saved: 0))
        .toList(growable: false);
    monthsProcessed = 0;
    monthPoolSpent = 0;
    extraSavings = 0;
    spentOnPurchases = 0;
    purchaseHistory = [];

    _addLog(EventType.system, 'Progress reset for goals and monthly counters.');
    _save();
    _emitState();
  }

  void hardReset() {
    _pushUndo();

    salary = 0;
    expenses = [];
    goals = [];
    monthsProcessed = 0;
    monthPoolSpent = 0;
    extraSavings = 0;
    spentOnPurchases = 0;
    purchaseHistory = [];
    logs = [];
    dailySpends = [];
    aiError = '';
    aiResult = null;
    aiRawText = '';

    salaryCtrl.clear();
    expenseNameCtrl.clear();
    expenseAmountCtrl.clear();
    goalNameCtrl.clear();
    goalTargetCtrl.clear();
    goalPercentCtrl.clear();
    dailySpendAmountCtrl.clear();
    dailySpendNoteCtrl.clear();
    goalPriority = GoalPriority.medium;

    _save();
    _emitState();
  }

  void setDailySpendDate(DateTime date) {
    dailySpendDate = dateOnly(date);
    _emitState();
  }

  String? addDailySpending() {
    final amountValue = toDoubleValue(dailySpendAmountCtrl.text);
    if (amountValue <= 0) {
      return 'Enter a valid spending amount.';
    }

    _pushUndo();
    final note = dailySpendNoteCtrl.text.trim();
    final applied = _applyDailySpend(
      amount: amountValue,
      spendDate: dailySpendDate,
      note: note,
      source: 'DAILY_SPEND',
    );
    if (!applied) {
      return 'Not enough savings available for this daily spend entry.';
    }

    dailySpendAmountCtrl.clear();
    dailySpendNoteCtrl.clear();
    _save();
    _emitState();
    return null;
  }

  void previousCalendarMonth() {
    calendarMonth = DateTime(calendarMonth.year, calendarMonth.month - 1, 1);
    _emitState();
  }

  void nextCalendarMonth() {
    calendarMonth = DateTime(calendarMonth.year, calendarMonth.month + 1, 1);
    _emitState();
  }

  void resetCalendarMonth() {
    calendarMonth = monthStart(DateTime.now());
    _emitState();
  }

  Map<String, dynamic> get calendarSnapshot {
    final monthKey = DateFormat('yyyy-MM').format(calendarMonth);
    final firstWeekday =
        DateTime(calendarMonth.year, calendarMonth.month, 1).weekday % 7;
    final daysInMonth = DateTime(
      calendarMonth.year,
      calendarMonth.month + 1,
      0,
    ).day;

    final totalsByDay = <int, double>{};
    var monthTotal = 0.0;

    for (final spend in dailySpends) {
      if (DateFormat('yyyy-MM').format(spend.date) != monthKey) {
        continue;
      }
      final day = spend.date.day;
      totalsByDay[day] = round2((totalsByDay[day] ?? 0) + spend.amount);
      monthTotal = round2(monthTotal + spend.amount);
    }

    for (final purchase in purchaseHistory) {
      if (DateFormat('yyyy-MM').format(purchase.purchasedAt) != monthKey) {
        continue;
      }
      final day = purchase.purchasedAt.day;
      totalsByDay[day] = round2((totalsByDay[day] ?? 0) + purchase.amount);
      monthTotal = round2(monthTotal + purchase.amount);
    }

    final cells = <Map<String, dynamic>>[];
    for (var i = 0; i < firstWeekday; i += 1) {
      cells.add({'type': 'empty'});
    }

    for (var day = 1; day <= daysInMonth; day += 1) {
      cells.add({
        'type': 'day',
        'day': day,
        'total': round2(totalsByDay[day] ?? 0),
      });
    }

    return {
      'monthLabel': DateFormat('MMMM yyyy').format(calendarMonth),
      'monthTotal': monthTotal,
      'cells': cells,
    };
  }

  Future<void> runAiAdvisor() async {
    if (_aiRequestLock) {
      _addLog(EventType.ai, 'AI request blocked: already running.');
      return;
    }

    _aiRequestLock = true;
    final goalContext = goals
        .map(
          (goal) => {
            'name': goal.name,
            'target': goal.target,
            'saved': goal.saved,
            'priority': goal.priority.name,
            'currentPercent': goal.percent,
            'monthlyAllocation': allocation.allocationByGoalId[goal.id] ?? 0,
          },
        )
        .toList(growable: false);

    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      final elapsedSinceLast = now - _lastAiRequestAt;
      if (_lastAiRequestAt > 0 && elapsedSinceLast < aiCooldownMs) {
        final waitSeconds = ((aiCooldownMs - elapsedSinceLast) / 1000).ceil();
        aiResult = _buildLocalAdvisorPlan(goalContext);
        aiError =
            'Please wait ${waitSeconds}s before generating another AI plan. Showing local smart plan meanwhile.';
        _emitState();
        return;
      }

      if (now < _geminiBlockedUntil) {
        final waitSeconds = ((_geminiBlockedUntil - now) / 1000).ceil();
        aiResult = _buildLocalAdvisorPlan(goalContext);
        aiError =
            'Gemini is rate-limited. Using local smart plan for ${waitSeconds}s.';
        _emitState();
        return;
      }

      const apiKey = String.fromEnvironment('GEMINI_API_KEY');
      if (apiKey.isEmpty) {
        aiResult = _buildLocalAdvisorPlan(goalContext);
        aiError =
            'Missing GEMINI_API_KEY. Using local smart plan. Pass --dart-define=GEMINI_API_KEY=...';
        _emitState();
        return;
      }

      _lastAiRequestAt = now;
      aiLoading = true;
      aiError = '';
      _addLog(EventType.ai, 'AI analysis request started.');
      _emitState();

      final prompt = _buildAiPrompt(goalContext);
      final endpoint =
          'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$apiKey';

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature': 0.4,
            'responseMimeType': 'application/json',
          },
        }),
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 429) {
          _geminiBlockedUntil =
              DateTime.now().millisecondsSinceEpoch +
              const Duration(seconds: 20).inMilliseconds;
          aiResult = _buildLocalAdvisorPlan(goalContext);
          aiError =
              'Gemini quota exceeded. Using local smart plan temporarily.';
          aiRawText = response.body;
          _addLog(EventType.ai, 'Gemini quota exceeded; local fallback used.');
          return;
        }

        throw Exception('Gemini request failed (${response.statusCode}).');
      }

      final body = jsonDecode(response.body);
      final text =
          (((body['candidates'] as List?) ?? [])
                      .firstOrNull?['content']?['parts']
                  as List?)
              ?.map((part) => (part['text'] ?? '').toString())
              .join('\n')
              .trim();

      if (text == null || text.isEmpty) {
        throw Exception('Gemini returned empty response.');
      }

      aiRawText = text;
      final parsed = _parseJsonFromText(text);
      if (parsed == null) {
        aiResult = _buildLocalAdvisorPlan(goalContext);
        aiError = 'Could not parse AI output. Showing local smart plan.';
        _addLog(EventType.ai, 'AI parse failed; local fallback used.');
        return;
      }

      aiResult = _mergeAdvisorResult(parsed, goalContext);
      _addLog(EventType.ai, 'AI analysis completed successfully.');
    } catch (e) {
      aiResult = _buildLocalAdvisorPlan(goalContext);
      aiError = '$e Showing local smart plan instead.';
      _addLog(EventType.ai, 'AI request failed; local fallback used.');
    } finally {
      aiLoading = false;
      _aiRequestLock = false;
      _emitState();
    }
  }

  void applyAiPercentSuggestions() {
    final result = aiResult;
    if (result == null || result.suggestedPercents.isEmpty) {
      return;
    }

    final normalizedNames = goals
        .map((goal) => goal.name.trim().toLowerCase())
        .toList();
    if (normalizedNames.toSet().length != normalizedNames.length) {
      aiError =
          'Duplicate goal names found. Rename goals to apply AI percentages.';
      _emitState();
      return;
    }

    _pushUndo();

    final byName = {
      for (final suggestion in result.suggestedPercents)
        suggestion.goalName.trim().toLowerCase(): suggestion.percent,
    };

    goals = goals
        .map((goal) {
          final key = goal.name.trim().toLowerCase();
          if (!byName.containsKey(key)) {
            return goal;
          }
          final nextPercent = (byName[key] ?? 0).clamp(0, 100).toDouble();
          return goal.copyWith(percent: nextPercent);
        })
        .toList(growable: false);

    _addLog(
      EventType.ai,
      'AI suggested percentages applied.',
      meta: {'count': result.suggestedPercents.length},
    );
    _save();
    _emitState();
  }

  String exportExpenseHistoryJson() {
    final entries = logs
        .where(
          (entry) =>
              entry.type == EventType.expense ||
              entry.type == EventType.purchase,
        )
        .map((entry) => entry.toJson())
        .toList(growable: false);

    final payload = {
      'exportedAt': DateTime.now().toIso8601String(),
      'total': entries.length,
      'entries': entries,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  void _addLog(
    EventType type,
    String message, {
    double? amount,
    Map<String, dynamic>? meta,
  }) {
    logs = [
      EventLog(
        id: _uuid.v4(),
        ts: DateTime.now(),
        type: type,
        message: message,
        amount: amount,
        meta: meta,
      ),
      ...logs,
    ].take(500).toList(growable: false);
  }

  String _buildAiPrompt(List<Map<String, dynamic>> goalsContext) {
    return 'You are a financial planning assistant for a monthly savings app.\n\n'
        'Input data:\n'
        '- Monthly salary: $salary\n'
        '- Monthly total expenses: $monthlyExpenseTotal\n'
        '- Monthly savings pool: $effectivePlanningPool\n'
        '- Months processed: $monthsProcessed\n'
        '- Goals: ${jsonEncode(goalsContext)}\n\n'
        'Rules:\n'
        '- Be practical and concise.\n'
        '- If fixed percentages are weak, suggest better percentages.\n'
        '- Prioritize high-priority and nearly-complete goals.\n'
        '- Keep total suggested percentages <= 100.\n'
        '- Mention overspending issues if present.\n\n'
        'Return ONLY valid JSON with shape:\n'
        '{"summary":"string","recommendations":["string"],'
        '"suggestedPercents":[{"goalName":"string","percent":number}],'
        '"quickActions":["string"]}';
  }

  Map<String, dynamic>? _parseJsonFromText(String text) {
    try {
      final parsed = jsonDecode(text);
      if (parsed is Map<String, dynamic>) {
        return parsed;
      }
      if (parsed is Map) {
        return Map<String, dynamic>.from(parsed);
      }
    } catch (_) {
      // Continue with best-effort extraction.
    }

    final fenced = RegExp(
      r'```json\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(text)?.group(1);
    if (fenced != null) {
      try {
        final parsed = jsonDecode(fenced);
        if (parsed is Map<String, dynamic>) {
          return parsed;
        }
        if (parsed is Map) {
          return Map<String, dynamic>.from(parsed);
        }
      } catch (_) {
        // Continue.
      }
    }

    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final snippet = text.substring(start, end + 1);
      try {
        final parsed = jsonDecode(snippet);
        if (parsed is Map<String, dynamic>) {
          return parsed;
        }
        if (parsed is Map) {
          return Map<String, dynamic>.from(parsed);
        }
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  AdvisorResult _mergeAdvisorResult(
    Map<String, dynamic> parsed,
    List<Map<String, dynamic>> goalsContext,
  ) {
    final summary = (parsed['summary'] ?? '').toString().trim();
    final recommendations = ((parsed['recommendations'] as List?) ?? [])
        .map((entry) => entry.toString())
        .where((entry) => entry.trim().isNotEmpty)
        .toList(growable: false);
    final quickActions = ((parsed['quickActions'] as List?) ?? [])
        .map((entry) => entry.toString())
        .where((entry) => entry.trim().isNotEmpty)
        .toList(growable: false);

    final suggestions = ((parsed['suggestedPercents'] as List?) ?? [])
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map(
          (entry) => GoalPercentSuggestion(
            goalName: (entry['goalName'] ?? '').toString(),
            percent: toDoubleValue(entry['percent']).clamp(0, 100).toDouble(),
          ),
        )
        .where((entry) => entry.goalName.trim().isNotEmpty)
        .toList(growable: false);

    if (summary.isEmpty ||
        (recommendations.isEmpty &&
            quickActions.isEmpty &&
            suggestions.isEmpty)) {
      return _buildLocalAdvisorPlan(goalsContext);
    }

    return AdvisorResult(
      source: 'gemini',
      summary: summary,
      recommendations: recommendations,
      quickActions: quickActions,
      suggestedPercents: suggestions,
    );
  }

  AdvisorResult _buildLocalAdvisorPlan(
    List<Map<String, dynamic>> goalsContext,
  ) {
    final activeGoals = goalsContext
        .where(
          (goal) =>
              toDoubleValue(goal['target']) >
              toDoubleValue(goal['saved']) + 0.01,
        )
        .toList(growable: false);

    final sorted = [...activeGoals]
      ..sort((a, b) {
        final pa = a['priority'] == 'high'
            ? 0
            : (a['priority'] == 'medium' ? 1 : 2);
        final pb = b['priority'] == 'high'
            ? 0
            : (b['priority'] == 'medium' ? 1 : 2);
        if (pa != pb) {
          return pa.compareTo(pb);
        }

        final remA = (toDoubleValue(a['target']) - toDoubleValue(a['saved']))
            .clamp(0, double.infinity);
        final remB = (toDoubleValue(b['target']) - toDoubleValue(b['saved']))
            .clamp(0, double.infinity);
        return remA.compareTo(remB);
      });

    final suggestionCount = sorted.length > 4 ? 4 : sorted.length;
    final suggestions = <GoalPercentSuggestion>[];

    if (suggestionCount > 0) {
      final base = 100 / suggestionCount;
      for (var i = 0; i < suggestionCount; i += 1) {
        final boost = i == 0 ? 8 : (i == 1 ? 3 : 0);
        suggestions.add(
          GoalPercentSuggestion(
            goalName: (sorted[i]['name'] ?? 'Untitled Goal').toString(),
            percent: round2((base + boost).clamp(5, 70).toDouble()),
          ),
        );
      }

      final totalPercent = suggestions.fold<double>(
        0,
        (acc, item) => acc + item.percent,
      );
      if (totalPercent > 100) {
        final scale = 100 / totalPercent;
        for (var i = 0; i < suggestions.length; i += 1) {
          final scaled = round2(suggestions[i].percent * scale);
          suggestions[i] = GoalPercentSuggestion(
            goalName: suggestions[i].goalName,
            percent: scaled,
          );
        }
      }
    }

    final expenseRatio = salary <= 0 ? 1.0 : monthlyExpenseTotal / salary;
    final overSpend = monthlyExpenseTotal > salary;

    return AdvisorResult(
      source: 'local',
      summary: overSpend
          ? 'Expenses are above salary. Reduce recurring costs before adding new goals.'
          : expenseRatio >= 0.75
          ? 'Expenses are high relative to salary. Keep fixed goal percentages conservative.'
          : 'Savings health looks stable. Prioritize high-impact goals and process monthly consistently.',
      recommendations: [
        'Keep fixed percentages under 100% total to avoid forced scaling.',
        'Process month once allocations look balanced and revisit priorities monthly.',
        if (overSpend)
          'Cut or renegotiate at least one recurring expense this month.',
      ],
      quickActions: [
        'Apply suggested percentages to active goals.',
        'Log daily spending for 7 days to spot leakage.',
        'Review purchase readiness before buying goals.',
      ],
      suggestedPercents: suggestions,
    );
  }

  Future<void> _save() async {
    final payload = _buildPayload();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(payload));

    if (!firebaseReady || authUser == null || !cloudLoadDone) {
      return;
    }

    _cloudSaveDebounce?.cancel();
    cloudStatus = 'syncing';
    _emitState();

    _cloudSaveDebounce = Timer(const Duration(milliseconds: 800), () async {
      try {
        await FirebaseFirestore.instance
            .collection('budgieUsers')
            .doc(authUser!.uid)
            .set({
              'plannerState': payload,
              'updatedAt': FieldValue.serverTimestamp(),
              'email': authUser!.email,
            }, SetOptions(merge: true));
        cloudStatus = 'synced';
      } catch (_) {
        cloudStatus = 'error';
      }
      _emitState();
    });
  }

  Map<String, dynamic> _buildPayload() {
    return {
      'salary': salary,
      'expenses': expenses
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'monthsProcessed': monthsProcessed,
      'monthPoolSpent': monthPoolSpent,
      'extraSavings': extraSavings,
      'spentOnPurchases': spentOnPurchases,
      'purchaseHistory': purchaseHistory
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'logs': logs.map((entry) => entry.toJson()).toList(growable: false),
      'goals': goals.map((entry) => entry.toJson()).toList(growable: false),
      'dailySpends': dailySpends
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }

  void _applyPayload(Map<String, dynamic> payload) {
    salary = toDoubleValue(payload['salary']);
    expenses = ((payload['expenses'] as List?) ?? [])
        .whereType<Map>()
        .map((entry) => ExpenseItem.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
    monthsProcessed = toIntValue(payload['monthsProcessed']);
    monthPoolSpent = toDoubleValue(payload['monthPoolSpent']);
    extraSavings = toDoubleValue(payload['extraSavings']);
    spentOnPurchases = toDoubleValue(payload['spentOnPurchases']);
    purchaseHistory = ((payload['purchaseHistory'] as List?) ?? [])
        .whereType<Map>()
        .map(
          (entry) => PurchaseEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
    logs = ((payload['logs'] as List?) ?? [])
        .whereType<Map>()
        .map((entry) => EventLog.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
    goals = ((payload['goals'] as List?) ?? [])
        .whereType<Map>()
        .map((entry) => GoalItem.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
    dailySpends = ((payload['dailySpends'] as List?) ?? [])
        .whereType<Map>()
        .map(
          (entry) => DailySpendEntry.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
  }

  Future<int> _consumeWidgetSpendEvents(SharedPreferences prefs) async {
    final rawQueue = prefs.getString(widgetDailySpendEventsKey);
    if (rawQueue == null || rawQueue.trim().isEmpty) {
      return 0;
    }

    List<dynamic> queue;
    try {
      final decoded = jsonDecode(rawQueue);
      if (decoded is! List) {
        await prefs.remove(widgetDailySpendEventsKey);
        return 0;
      }
      queue = decoded;
    } catch (_) {
      await prefs.remove(widgetDailySpendEventsKey);
      return 0;
    }

    var imported = 0;
    var skipped = 0;
    var pendingRetry = 0;
    final processedIds =
        prefs.getStringList(widgetDailySpendProcessedIdsKey)?.toSet() ??
        <String>{};
    final nextQueue = <Map<String, dynamic>>[];

    queue.sort((a, b) {
      if (a is! Map || b is! Map) {
        return 0;
      }
      final aTs = toIntValue(a['createdAtMs']) == 0
          ? toIntValue(a['ts'])
          : toIntValue(a['createdAtMs']);
      final bTs = toIntValue(b['createdAtMs']) == 0
          ? toIntValue(b['ts'])
          : toIntValue(b['createdAtMs']);
      return aTs.compareTo(bTs);
    });

    for (var i = 0; i < queue.length; i += 1) {
      final event = queue[i];
      if (event is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(event);
      final eventId = (map['eventId'] ?? '').toString().trim().isEmpty
          ? '${toIntValue(map['createdAtMs']) == 0 ? toIntValue(map['ts']) : toIntValue(map['createdAtMs'])}-${toIntValue(map['amountMinor']) == 0 ? toDoubleValue(map['amount']) : toIntValue(map['amountMinor'])}-${(map['dateIso'] ?? map['date'] ?? '').toString()}-$i'
          : map['eventId'].toString();

      if (processedIds.contains(eventId)) {
        continue;
      }

      if ((map['type'] ?? '').toString() != 'add') {
        processedIds.add(eventId);
        continue;
      }

      final amountMinor = toIntValue(map['amountMinor']);
      final amount = amountMinor > 0
          ? round2(amountMinor / 100)
          : toDoubleValue(map['amount']);
      if (amount <= 0) {
        processedIds.add(eventId);
        continue;
      }

      final dateRaw = (map['dateIso'] ?? map['date'] ?? '').toString();
      final parsedDate = DateTime.tryParse(dateRaw);
      final spendDate = parsedDate ?? DateTime.now();

      final applied = _applyDailySpend(
        amount: amount,
        spendDate: spendDate,
        note: 'Widget quick add',
        source: 'WIDGET_SYNC',
      );
      if (applied) {
        imported += 1;
        processedIds.add(eventId);
      } else {
        skipped += 1;
        final retries = toIntValue(map['retries']) + 1;
        if (retries <= widgetDailySpendMaxRetries) {
          map['eventId'] = eventId;
          map['retries'] = retries;
          nextQueue.add(map);
          pendingRetry += 1;
        } else {
          processedIds.add(eventId);
        }
      }
    }

    if (skipped > 0) {
      _addLog(
        EventType.system,
        'Widget sync skipped $skipped entr${skipped == 1 ? 'y' : 'ies'} due to insufficient available savings.',
        meta: {'source': 'WIDGET_SYNC', 'pendingRetry': pendingRetry},
      );
    }

    if (nextQueue.isEmpty) {
      await prefs.remove(widgetDailySpendEventsKey);
    } else {
      await prefs.setString(widgetDailySpendEventsKey, jsonEncode(nextQueue));
    }

    final processedList = processedIds.toList(growable: false);
    final trimmed = processedList.length <= widgetDailySpendMaxProcessedIds
        ? processedList
        : processedList.sublist(
            processedList.length - widgetDailySpendMaxProcessedIds,
          );
    await prefs.setStringList(widgetDailySpendProcessedIdsKey, trimmed);

    return imported;
  }

  bool _applyDailySpend({
    required double amount,
    required DateTime spendDate,
    required String note,
    required String source,
  }) {
    final availableSavingsNow = round2(extraSavings + availableMonthExcess);
    if (amount > availableSavingsNow + 0.01) {
      return false;
    }

    var remaining = round2(amount);
    final fromCurrentExcess = remaining < availableMonthExcess
        ? remaining
        : availableMonthExcess;

    if (fromCurrentExcess > 0) {
      monthPoolSpent = round2(monthPoolSpent + fromCurrentExcess);
      remaining = round2(remaining - fromCurrentExcess);
    }

    if (remaining > 0) {
      extraSavings = round2(
        (extraSavings - remaining).clamp(0, double.infinity),
      );
    }

    final trimmedNote = note.trim();
    final normalizedDate = dateOnly(spendDate);
    dailySpends = [
      DailySpendEntry(
        id: _uuid.v4(),
        date: normalizedDate,
        amount: round2(amount),
        note: trimmedNote,
      ),
      ...dailySpends,
    ];

    _addLog(
      EventType.expense,
      'Daily spend logged: ${trimmedNote.isEmpty ? 'General' : trimmedNote}',
      amount: amount,
      meta: {
        'source': source,
        'spendDate': DateFormat('yyyy-MM-dd').format(normalizedDate),
        'note': trimmedNote.isEmpty ? null : trimmedNote,
      },
    );

    return true;
  }

  @override
  Future<void> close() {
    _authSub?.cancel();
    _cloudSaveDebounce?.cancel();
    salaryCtrl.dispose();
    expenseNameCtrl.dispose();
    expenseAmountCtrl.dispose();
    goalNameCtrl.dispose();
    goalTargetCtrl.dispose();
    goalPercentCtrl.dispose();
    dailySpendAmountCtrl.dispose();
    dailySpendNoteCtrl.dispose();
    return super.close();
  }
}
