import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:budgie_flutter/app/bootstrap/firebase_bootstrap.dart';
import 'package:budgie_flutter/features/planner/application/planner_view_model.dart';
import 'package:budgie_flutter/features/planner/presentation/planner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseBootstrap.tryInitialize();

  runApp(
    BlocProvider(
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
            borderRadius: BorderRadius.circular(12),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(color: const Color(0xFF93A4B8).withValues(alpha: 0.6)),
            foregroundColor: const Color(0xFFD3DCE6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF121B28).withValues(alpha: 0.86),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: const Color(0xFF91A1B6).withValues(alpha: 0.24)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: const Color(0xFF91A1B6).withValues(alpha: 0.24)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
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
