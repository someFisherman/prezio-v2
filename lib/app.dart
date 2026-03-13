import 'package:flutter/material.dart';
import 'screens/screens.dart';
import 'utils/theme.dart';
import 'utils/constants.dart';

class PrezioApp extends StatelessWidget {
  const PrezioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}
