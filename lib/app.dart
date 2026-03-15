import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/password_screen.dart';
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
      home: const _EntryGate(),
    );
  }
}

class _EntryGate extends StatefulWidget {
  const _EntryGate();

  @override
  State<_EntryGate> createState() => _EntryGateState();
}

class _EntryGateState extends State<_EntryGate> {
  bool? _unlocked;

  @override
  void initState() {
    super.initState();
    _checkUnlocked();
  }

  Future<void> _checkUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final unlocked = prefs.getBool(StorageKeys.appUnlocked) ?? false;
    if (mounted) {
      setState(() => _unlocked = unlocked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _unlocked! ? const HomeScreen() : const PasswordScreen();
  }
}
