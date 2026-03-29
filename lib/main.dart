import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _storageKey = 'budgie_flutter_state_v2';
const _maxUndoSteps = 40;
const _aiCooldownMs = 60000;
const _geminiModel = 'gemini-2.5-flash';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.tryInitialize();

  runApp(
    ChangeNotifierProvider(
      create: (_) => PlannerViewModel()..hydrate(),
      child: const BudgieApp(),
    ),
  );
}

class BudgieApp extends StatelessWidget {
  const BudgieApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8D9CAF),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Budgie Flutter',
      theme: base.copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080B12),
        textTheme: base.textTheme.apply(
          bodyColor: const Color(0xFFE3E8EF),
          displayColor: const Color(0xFFE3E8EF),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: Color(0xFFE3E8EF),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF101723).withValues(alpha: 0.72),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: const Color(0xFFC8D4E1).withValues(alpha: 0.12)),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: const Color(0xFF2C3D52).withValues(alpha: 0.9),
          backgroundColor: const Color(0xFF0D1420).withValues(alpha: 0.8),
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFD8E0EA)),
          ),
          iconTheme: WidgetStateProperty.all(
            const IconThemeData(color: Color(0xFFD8E0EA)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFA9B8CA),
            foregroundColor: const Color(0xFF101723),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: BorderSide(color: const Color(0xFF93A4B8).withValues(alpha: 0.6)),
            foregroundColor: const Color(0xFFD3DCE6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF121B28).withValues(alpha: 0.86),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: const Color(0xFF91A1B6).withValues(alpha: 0.24)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: const Color(0xFF91A1B6).withValues(alpha: 0.24)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFB6C3D2), width: 1.4),
          ),
          labelStyle: const TextStyle(color: Color(0xFFA5B4C6), fontWeight: FontWeight.w600),
          hintStyle: const TextStyle(color: Color(0xFF7F8EA1)),
        ),
      ),
      home: const PlannerScreen(),
    );
  }
}

class FirebaseBootstrap {
  static bool initialized = false;

  static Future<void> tryInitialize() async {
    if (initialized || Firebase.apps.isNotEmpty) {
      initialized = true;
      return;
    }

    final options = _optionsFromEnvironment();
    if (options == null) {
      return;
    }

    try {
      await Firebase.initializeApp(options: options);
      initialized = true;
    } catch (_) {
      initialized = false;
    }
  }

  static FirebaseOptions? _optionsFromEnvironment() {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const messagingSenderId =
        String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
    const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    const measurementId = String.fromEnvironment('FIREBASE_MEASUREMENT_ID');
    const iosBundleId = String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID');

    if (apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      measurementId: measurementId.isEmpty ? null : measurementId,
      iosBundleId: iosBundleId.isEmpty ? null : iosBundleId,
    );
  }
}

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

  double get remaining => _round2((target - saved).clamp(0, double.infinity));

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

    return GoalItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Untitled Goal').toString(),
      target: _toDouble(json['target']),
      saved: _toDouble(json['saved']),
      priority: priority,
      percent: _toDouble(json['percent']).clamp(0, 100).toDouble(),
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
      amount: _toDouble(json['amount']),
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
      amount: _toDouble(json['amount']),
      purchasedAt:
          DateTime.tryParse((json['purchasedAt'] ?? '').toString()) ?? DateTime.now(),
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
      date: DateTime.tryParse((json['date'] ?? '').toString()) ?? DateTime.now(),
      amount: _toDouble(json['amount']),
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
      ts: DateTime.tryParse((json['ts'] ?? '').toString()) ?? DateTime.now(),
      type: type,
      message: (json['message'] ?? '').toString(),
      amount: json['amount'] == null ? null : _toDouble(json['amount']),
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

class PlannerViewModel extends ChangeNotifier {
  PlannerViewModel();

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
  DateTime dailySpendDate = _dateOnly(DateTime.now());
  DateTime calendarMonth = _monthStart(DateTime.now());

  String aiError = '';
  bool aiLoading = false;
  String aiRawText = '';
  AdvisorResult? aiResult;
  int _lastAiRequestAt = 0;
  int _geminiBlockedUntil = 0;
  bool _aiRequestLock = false;

  final List<PlannerSnapshot> _undoStack = [];

  NumberFormat get _currencyFmt => NumberFormat.currency(
        locale: 'en_IN',
        symbol: 'INR ',
        decimalDigits: 0,
      );

  String asCurrency(double value) => _currencyFmt.format(value);

  double get monthlyExpenseTotal {
    return _round2(expenses.fold(0, (total, item) => total + item.amount));
  }

  double get monthlyPool {
    return _round2((salary - monthlyExpenseTotal).clamp(0, double.infinity));
  }

  double get availableMonthExcess {
    return _round2((monthlyPool - monthPoolSpent).clamp(0, double.infinity));
  }

  double get effectivePlanningPool => availableMonthExcess;

  double get totalGoalSavings {
    return _round2(goals.fold(0, (total, goal) => total + goal.saved));
  }

  double get totalSavings => _round2(totalGoalSavings + extraSavings);

  double get totalSavingsWithCurrentExcess {
    return _round2(totalSavings + availableMonthExcess);
  }

  int get undoDepth => _undoStack.length;

  AllocationResult get allocation => calculateAllocation(effectivePlanningPool, goals);

  List<MapEntry<GoalItem, double>> get plannedAllocation {
    return goals.map((goal) {
      return MapEntry(goal, allocation.allocationByGoalId[goal.id] ?? 0);
    }).toList(growable: false);
  }

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _applyPayload(decoded);
      }
    }

    salaryCtrl.text = salary <= 0 ? '' : salary.toStringAsFixed(0);
    isHydrated = true;
    notifyListeners();

    if (!firebaseReady) {
      cloudLoadDone = true;
      cloudStatus = 'local';
      notifyListeners();
      return;
    }

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      authUser = user;
      authError = '';
      notifyListeners();
      await _hydrateFromCloud();
    });
  }

  Future<void> signInWithGoogle() async {
    if (!firebaseReady) {
      authError = 'Firebase is not configured. Add FIREBASE_* dart-defines.';
      notifyListeners();
      return;
    }

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
        return;
      }

      final account = await GoogleSignIn.instance.authenticate();
      final authData = account.authentication;
      final credential = GoogleAuthProvider.credential(idToken: authData.idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      authError = 'Google sign-in failed: $e';
      notifyListeners();
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
    if (!firebaseReady || authUser == null) {
      cloudLoadDone = true;
      cloudStatus = 'local';
      notifyListeners();
      return;
    }

    cloudLoadDone = false;
    cloudStatus = 'syncing';
    notifyListeners();

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
      cloudStatus = 'synced';
    } catch (_) {
      cloudStatus = 'error';
      authError = 'Cloud load failed. Using local data.';
    } finally {
      cloudLoadDone = true;
      notifyListeners();
    }
  }

  void setTab(int index) {
    activeTab = index;
    notifyListeners();
  }

  void changeGoalPriority(GoalPriority priority) {
    goalPriority = priority;
    notifyListeners();
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
    if (_undoStack.length > _maxUndoSteps) {
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
    notifyListeners();
  }

  void updateSalaryFromInput() {
    final value = _toDouble(salaryCtrl.text);
    _pushUndo();
    salary = value.clamp(0, double.infinity);
    _addLog(EventType.system, 'Salary updated.', amount: salary);
    _save();
    notifyListeners();
  }

  void addExpense() {
    final name = expenseNameCtrl.text.trim();
    final amount = _toDouble(expenseAmountCtrl.text);
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
    notifyListeners();
  }

  void removeExpense(String id) {
    final target = _firstOrNull(expenses.where((item) => item.id == id));
    _pushUndo();
    expenses = expenses.where((item) => item.id != id).toList(growable: false);

    _addLog(
      EventType.expense,
      'Expense removed${target == null ? '' : ': ${target.name}'}.',
      amount: target?.amount,
    );
    _save();
    notifyListeners();
  }

  void addGoal() {
    final name = goalNameCtrl.text.trim();
    final target = _toDouble(goalTargetCtrl.text);
    final percent = _toDouble(goalPercentCtrl.text).clamp(0, 100).toDouble();

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
    notifyListeners();
  }

  void removeGoal(String id) {
    final target = _firstOrNull(goals.where((item) => item.id == id));
    _pushUndo();
    goals = goals.where((item) => item.id != id).toList(growable: false);

    _addLog(EventType.goal, 'Goal removed${target == null ? '' : ': ${target.name}'}');
    _save();
    notifyListeners();
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

    goals = goals.map((goal) {
      final grant = result.allocationByGoalId[goal.id] ?? 0;
      if (grant <= 0) {
        return goal;
      }

      final nextSaved = goal.saved + grant;
      if (nextSaved > goal.target) {
        overflow += nextSaved - goal.target;
      }

      return goal.copyWith(saved: _round2(nextSaved.clamp(0, goal.target)));
    }).toList(growable: false);

    monthsProcessed += 1;
    extraSavings = _round2(extraSavings + result.unassigned + overflow);
    monthPoolSpent = 0;

    _addLog(
      EventType.system,
      'Monthly processing completed.',
      meta: {'overflow': overflow, 'unassigned': result.unassigned},
    );
    _save();
    notifyListeners();
  }

  void buyGoal(String id) {
    final goal = _firstOrNull(goals.where((item) => item.id == id));
    if (goal == null) {
      return;
    }

    final remainingToFund = _round2((goal.target - goal.saved).clamp(0, double.infinity));
    final availableInstant = _round2(extraSavings + availableMonthExcess);

    if (availableInstant + 0.01 < remainingToFund) {
      aiError = 'Not enough available savings to buy this goal yet.';
      _addLog(
        EventType.purchase,
        'Purchase blocked for ${goal.name}.',
        meta: {'needed': remainingToFund, 'available': availableInstant},
      );
      notifyListeners();
      return;
    }

    _pushUndo();

    if (remainingToFund > 0) {
      var stillNeeded = remainingToFund;
      final useFromExtra = stillNeeded < extraSavings ? stillNeeded : extraSavings;
      stillNeeded = _round2(stillNeeded - useFromExtra);
      extraSavings = _round2((extraSavings - useFromExtra).clamp(0, double.infinity));

      if (stillNeeded > 0) {
        monthPoolSpent = _round2(monthPoolSpent + stillNeeded);
      }
    }

    spentOnPurchases = _round2(spentOnPurchases + goal.target);
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
    notifyListeners();
  }

  void resetProgress() {
    _pushUndo();
    goals = goals.map((item) => item.copyWith(saved: 0)).toList(growable: false);
    monthsProcessed = 0;
    monthPoolSpent = 0;
    extraSavings = 0;
    spentOnPurchases = 0;
    purchaseHistory = [];

    _addLog(EventType.system, 'Progress reset for goals and monthly counters.');
    _save();
    notifyListeners();
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
    notifyListeners();
  }

  void setDailySpendDate(DateTime date) {
    dailySpendDate = _dateOnly(date);
    notifyListeners();
  }

  String? addDailySpending() {
    final amountValue = _toDouble(dailySpendAmountCtrl.text);
    if (amountValue <= 0) {
      return 'Enter a valid spending amount.';
    }

    final availableSavingsNow = _round2(extraSavings + availableMonthExcess);
    if (amountValue > availableSavingsNow + 0.01) {
      return 'Not enough savings available for this daily spend entry.';
    }

    _pushUndo();

    var remaining = _round2(amountValue);
    final fromCurrentExcess = remaining < availableMonthExcess ? remaining : availableMonthExcess;

    if (fromCurrentExcess > 0) {
      monthPoolSpent = _round2(monthPoolSpent + fromCurrentExcess);
      remaining = _round2(remaining - fromCurrentExcess);
    }

    if (remaining > 0) {
      extraSavings = _round2((extraSavings - remaining).clamp(0, double.infinity));
    }

    final note = dailySpendNoteCtrl.text.trim();
    dailySpends = [
      DailySpendEntry(
        id: _uuid.v4(),
        date: _dateOnly(dailySpendDate),
        amount: _round2(amountValue),
        note: note,
      ),
      ...dailySpends,
    ];

    _addLog(
      EventType.expense,
      'Daily spend logged: ${note.isEmpty ? 'General' : note}',
      amount: amountValue,
      meta: {
        'source': 'DAILY_SPEND',
        'spendDate': DateFormat('yyyy-MM-dd').format(dailySpendDate),
        'note': note.isEmpty ? null : note,
      },
    );

    dailySpendAmountCtrl.clear();
    dailySpendNoteCtrl.clear();
    _save();
    notifyListeners();
    return null;
  }

  void previousCalendarMonth() {
    calendarMonth = DateTime(calendarMonth.year, calendarMonth.month - 1, 1);
    notifyListeners();
  }

  void nextCalendarMonth() {
    calendarMonth = DateTime(calendarMonth.year, calendarMonth.month + 1, 1);
    notifyListeners();
  }

  void resetCalendarMonth() {
    calendarMonth = _monthStart(DateTime.now());
    notifyListeners();
  }

  Map<String, dynamic> get calendarSnapshot {
    final monthKey = DateFormat('yyyy-MM').format(calendarMonth);
    final firstWeekday = DateTime(calendarMonth.year, calendarMonth.month, 1).weekday % 7;
    final daysInMonth = DateTime(calendarMonth.year, calendarMonth.month + 1, 0).day;

    final totalsByDay = <int, double>{};
    var monthTotal = 0.0;

    for (final spend in dailySpends) {
      if (DateFormat('yyyy-MM').format(spend.date) != monthKey) {
        continue;
      }
      final day = spend.date.day;
      totalsByDay[day] = _round2((totalsByDay[day] ?? 0) + spend.amount);
      monthTotal = _round2(monthTotal + spend.amount);
    }

    for (final purchase in purchaseHistory) {
      if (DateFormat('yyyy-MM').format(purchase.purchasedAt) != monthKey) {
        continue;
      }
      final day = purchase.purchasedAt.day;
      totalsByDay[day] = _round2((totalsByDay[day] ?? 0) + purchase.amount);
      monthTotal = _round2(monthTotal + purchase.amount);
    }

    final cells = <Map<String, dynamic>>[];
    for (var i = 0; i < firstWeekday; i += 1) {
      cells.add({'type': 'empty'});
    }

    for (var day = 1; day <= daysInMonth; day += 1) {
      cells.add({
        'type': 'day',
        'day': day,
        'total': _round2(totalsByDay[day] ?? 0),
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

    final now = DateTime.now().millisecondsSinceEpoch;
    final goalContext = goals
        .map((goal) => {
              'name': goal.name,
              'target': goal.target,
              'saved': goal.saved,
              'priority': goal.priority.name,
              'currentPercent': goal.percent,
              'monthlyAllocation': allocation.allocationByGoalId[goal.id] ?? 0,
            })
        .toList(growable: false);

    final elapsedSinceLast = now - _lastAiRequestAt;
    if (_lastAiRequestAt > 0 && elapsedSinceLast < _aiCooldownMs) {
      final waitSeconds = ((_aiCooldownMs - elapsedSinceLast) / 1000).ceil();
      aiResult = _buildLocalAdvisorPlan(goalContext);
      aiError =
          'Please wait ${waitSeconds}s before generating another AI plan. Showing local smart plan meanwhile.';
      notifyListeners();
      return;
    }

    if (now < _geminiBlockedUntil) {
      final waitSeconds = ((_geminiBlockedUntil - now) / 1000).ceil();
      aiResult = _buildLocalAdvisorPlan(goalContext);
      aiError = 'Gemini is rate-limited. Using local smart plan for ${waitSeconds}s.';
      notifyListeners();
      return;
    }

    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (apiKey.isEmpty) {
      aiResult = _buildLocalAdvisorPlan(goalContext);
      aiError =
          'Missing GEMINI_API_KEY. Using local smart plan. Pass --dart-define=GEMINI_API_KEY=...';
      notifyListeners();
      return;
    }

    _aiRequestLock = true;
    _lastAiRequestAt = now;
    aiLoading = true;
    aiError = '';
    _addLog(EventType.ai, 'AI analysis request started.');
    notifyListeners();

    try {
      final prompt = _buildAiPrompt(goalContext);
      final endpoint =
          'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$apiKey';

      final response = await http.post(
        Uri.parse(endpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.4,
            'responseMimeType': 'application/json',
          }
        }),
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 429) {
          _geminiBlockedUntil =
              DateTime.now().millisecondsSinceEpoch + const Duration(seconds: 20).inMilliseconds;
          aiResult = _buildLocalAdvisorPlan(goalContext);
          aiError = 'Gemini quota exceeded. Using local smart plan temporarily.';
          aiRawText = response.body;
          _addLog(EventType.ai, 'Gemini quota exceeded; local fallback used.');
          return;
        }

        throw Exception('Gemini request failed (${response.statusCode}).');
      }

      final body = jsonDecode(response.body);
      final text = (((body['candidates'] as List?) ?? [])
              .firstOrNull?['content']?['parts'] as List?)
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
      notifyListeners();
    }
  }

  void applyAiPercentSuggestions() {
    final result = aiResult;
    if (result == null || result.suggestedPercents.isEmpty) {
      return;
    }

    _pushUndo();

    final byName = {
      for (final suggestion in result.suggestedPercents)
        suggestion.goalName.trim().toLowerCase(): suggestion.percent,
    };

    goals = goals.map((goal) {
      final key = goal.name.trim().toLowerCase();
      if (!byName.containsKey(key)) {
        return goal;
      }
      final nextPercent = (byName[key] ?? 0).clamp(0, 100).toDouble();
      return goal.copyWith(percent: nextPercent);
    }).toList(growable: false);

    _addLog(
      EventType.ai,
      'AI suggested percentages applied.',
      meta: {'count': result.suggestedPercents.length},
    );
    _save();
    notifyListeners();
  }

  String exportExpenseHistoryJson() {
    final entries = logs
        .where((entry) =>
            entry.type == EventType.expense || entry.type == EventType.purchase)
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

    final fenced = RegExp(r'```json\s*([\s\S]*?)```', caseSensitive: false)
        .firstMatch(text)
        ?.group(1);
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
        .map((entry) => GoalPercentSuggestion(
              goalName: (entry['goalName'] ?? '').toString(),
              percent: _toDouble(entry['percent']).clamp(0, 100).toDouble(),
            ))
        .where((entry) => entry.goalName.trim().isNotEmpty)
        .toList(growable: false);

    if (summary.isEmpty ||
        (recommendations.isEmpty && quickActions.isEmpty && suggestions.isEmpty)) {
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

  AdvisorResult _buildLocalAdvisorPlan(List<Map<String, dynamic>> goalsContext) {
    final activeGoals = goalsContext
        .where((goal) => _toDouble(goal['target']) > _toDouble(goal['saved']) + 0.01)
        .toList(growable: false);

    final sorted = [...activeGoals]..sort((a, b) {
      final pa = a['priority'] == 'high'
          ? 0
          : (a['priority'] == 'medium' ? 1 : 2);
      final pb = b['priority'] == 'high'
          ? 0
          : (b['priority'] == 'medium' ? 1 : 2);
      if (pa != pb) {
        return pa.compareTo(pb);
      }

      final remA = (_toDouble(a['target']) - _toDouble(a['saved'])).clamp(0, double.infinity);
      final remB = (_toDouble(b['target']) - _toDouble(b['saved'])).clamp(0, double.infinity);
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
            percent: _round2((base + boost).clamp(5, 70).toDouble()),
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
          final scaled = _round2(suggestions[i].percent * scale);
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
        if (overSpend) 'Cut or renegotiate at least one recurring expense this month.',
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
    await prefs.setString(_storageKey, jsonEncode(payload));

    if (!firebaseReady || authUser == null || !cloudLoadDone) {
      return;
    }

    _cloudSaveDebounce?.cancel();
    cloudStatus = 'syncing';
    notifyListeners();

    _cloudSaveDebounce = Timer(const Duration(milliseconds: 800), () async {
      try {
        await FirebaseFirestore.instance
            .collection('budgieUsers')
            .doc(authUser!.uid)
            .set(
          {
            'plannerState': payload,
            'updatedAt': FieldValue.serverTimestamp(),
            'email': authUser!.email,
          },
          SetOptions(merge: true),
        );
        cloudStatus = 'synced';
      } catch (_) {
        cloudStatus = 'error';
      }
      notifyListeners();
    });
  }

  Map<String, dynamic> _buildPayload() {
    return {
      'salary': salary,
      'expenses': expenses.map((entry) => entry.toJson()).toList(growable: false),
      'monthsProcessed': monthsProcessed,
      'monthPoolSpent': monthPoolSpent,
      'extraSavings': extraSavings,
      'spentOnPurchases': spentOnPurchases,
      'purchaseHistory':
          purchaseHistory.map((entry) => entry.toJson()).toList(growable: false),
      'logs': logs.map((entry) => entry.toJson()).toList(growable: false),
      'goals': goals.map((entry) => entry.toJson()).toList(growable: false),
      'dailySpends':
          dailySpends.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  void _applyPayload(Map<String, dynamic> payload) {
    salary = _toDouble(payload['salary']);
    expenses = ((payload['expenses'] as List?) ?? [])
        .whereType<Map>()
        .map((entry) => ExpenseItem.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
    monthsProcessed = _toInt(payload['monthsProcessed']);
    monthPoolSpent = _toDouble(payload['monthPoolSpent']);
    extraSavings = _toDouble(payload['extraSavings']);
    spentOnPurchases = _toDouble(payload['spentOnPurchases']);
    purchaseHistory = ((payload['purchaseHistory'] as List?) ?? [])
        .whereType<Map>()
        .map((entry) => PurchaseEntry.fromJson(Map<String, dynamic>.from(entry)))
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
        .map((entry) => DailySpendEntry.fromJson(Map<String, dynamic>.from(entry)))
        .toList(growable: false);
  }

  @override
  void dispose() {
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
    super.dispose();
  }
}

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
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
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
                    vm.setDailySpendDate(selectedDate);
                    vm.dailySpendAmountCtrl.text = amountCtrl.text.trim();
                    vm.dailySpendNoteCtrl.text = noteCtrl.text.trim();
                    final error = vm.addDailySpending();

                    Navigator.of(dialogContext).pop();
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
    return Consumer<PlannerViewModel>(
      builder: (context, vm, _) {
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
                            ? const KeyedSubtree(
                                key: ValueKey('planner-tab'),
                                child: _PlannerTabShell(),
                              )
                            : const KeyedSubtree(
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
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
            padding: const EdgeInsets.all(18),
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
                    _DataMetric(label: 'Total Position', value: vm.asCurrency(vm.totalSavingsWithCurrentExcess), wide: true),
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

class _PlannerExpenses extends StatelessWidget {
  const _PlannerExpenses({required this.vm});

  final PlannerViewModel vm;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
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
        padding: const EdgeInsets.all(18),
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
        padding: const EdgeInsets.all(18),
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
                  width: 170,
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
                  width: 220,
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
            _DataMetric(label: 'Month Spend', value: vm.asCurrency(_toDouble(calendar['monthTotal'])), wide: true),
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
                final total = _toDouble(cell['total']);
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
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHead(
              title: 'AI Advisor',
              subtitle: 'Generate recommendations and apply suggested allocations when relevant.',
              icon: Icons.psychology_alt_outlined,
            ),
            const SizedBox(height: 8),
            Text('Model: $_geminiModel (local fallback enabled).', style: const TextStyle(fontSize: 12, color: Color(0xFF95A6B9))),
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
            padding: const EdgeInsets.all(18),
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
            padding: const EdgeInsets.all(18),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
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
      trendByMonth[key] = _round2((trendByMonth[key] ?? 0) + (entry.amount ?? 0));
    }
    final monthKeys = trendByMonth.keys.toList()..sort();
    final monthRows = monthKeys.reversed.take(8).toList(growable: false);

    if (section == 0) {
      return _GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
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
          padding: const EdgeInsets.all(18),
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
        padding: const EdgeInsets.all(18),
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
              Icon(icon, size: 18, color: const Color(0xFFAEC0D2)),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF95A4B5), height: 1.35),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
      margin: margin ?? const EdgeInsets.only(bottom: 14),
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
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF131B28).withValues(alpha: 0.82),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A2534),
            ),
            child: Icon(icon, color: const Color(0xFFC4CFDB), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
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
                      fontSize: 15,
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
      width: wide ? 220 : 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              fontSize: 11,
              color: Color(0xFF98A7B8),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
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

AllocationResult calculateAllocation(double pool, List<GoalItem> items) {
  final activeItems =
      items.where((item) => item.target > item.saved + 0.01).toList(growable: false);

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
    for (final item in activeItems) item.id: _round2(item.target - item.saved),
  };

  var unassigned = _round2(pool);

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
    final proposed = _round2(pool * share);
    final amount = _round2(proposed < need ? proposed : need);

    if (amount > 0) {
      allocationByGoalId[item.id] = _round2((allocationByGoalId[item.id] ?? 0) + amount);
      remainingById[item.id] = _round2(need - amount);
      unassigned = _round2(unassigned - amount);
    }
  }

  if (unassigned > 0.01) {
    unassigned = _allocateByWeight(unassigned, activeItems, allocationByGoalId, remainingById);
  }

  return AllocationResult(
    allocationByGoalId: allocationByGoalId,
    unassigned: _round2(unassigned < 0 ? 0 : unassigned),
    fixedPercentInput: _round2(fixedTotalPercent),
    fixedPercentApplied: _round2(fixedApplied),
    scalingApplied: fixedTotalPercent > 100,
  );
}

double _allocateByWeight(
  double pool,
  List<GoalItem> activeItems,
  Map<String, double> map,
  Map<String, double> remainingById,
) {
  var remainder = _round2(pool);
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
          index == available.length - 1 ? snapshot - distributed : _round2(rawShare);
      final grant = _round2(share < need ? share : need);

      if (grant > 0) {
        map[item.id] = _round2((map[item.id] ?? 0) + grant);
        remainingById[item.id] = _round2(need - grant);
        distributed += grant;
      }
    }

    if (distributed <= 0) {
      break;
    }

    remainder = _round2(remainder - distributed);
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

DateTime _monthStart(DateTime value) => DateTime(value.year, value.month, 1);
DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

T? _firstOrNull<T>(Iterable<T> values) {
  for (final value in values) {
    return value;
  }
  return null;
}

double _toDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? 0;
  }
  return 0;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
