import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Placeholder - run `flutterfire configure` to generate real options.
///
/// Steps:
/// 1. Create a Firebase project at https://console.firebase.google.com
/// 2. Install FlutterFire CLI: `dart pub global activate flutterfire_cli`
/// 3. Run: `flutterfire configure`
/// 4. This file will be overwritten with real configuration
class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: 'PLACEHOLDER',
    messagingSenderId: 'PLACEHOLDER',
    projectId: 'PLACEHOLDER',
  );

  static bool get isConfigured =>
      currentPlatform.apiKey != 'PLACEHOLDER';
}
