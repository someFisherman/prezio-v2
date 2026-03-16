import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        return android;
      default:
        return ios;
    }
  }

  static bool get isConfigured => true;

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA07UfM-gTSRBqLuJB42e73PiySkcylKXc',
    appId: '1:604871891802:ios:e55f3b7e007edb03077163',
    messagingSenderId: '604871891802',
    projectId: 'prezio-dc2c1',
    storageBucket: 'prezio-dc2c1.firebasestorage.app',
    iosBundleId: 'ch.soleco.prezioV2',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA07UfM-gTSRBqLuJB42e73PiySkcylKXc',
    appId: '1:604871891802:ios:e55f3b7e007edb03077163',
    messagingSenderId: '604871891802',
    projectId: 'prezio-dc2c1',
    storageBucket: 'prezio-dc2c1.firebasestorage.app',
  );
}
