import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rvv_analyzer/core/l10n/app_localizations.dart';
import 'package:rvv_analyzer/features/map/map_screen.dart';

class RatApp extends StatelessWidget {
  const RatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:"R.A.T. (RVV Analyzing Tool)",
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}
