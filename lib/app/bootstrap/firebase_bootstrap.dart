import 'package:budgie_flutter/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseBootstrap {
  static bool initialized = false;
  static bool _googleSignInInitialized = false;

  static Future<void> tryInitialize() async {
    if (initialized || Firebase.apps.isNotEmpty) {
      initialized = true;
      return;
    }

    final options = _optionsFromEnvironment() ?? _optionsFromConfiguredApp();
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

  static FirebaseOptions? _optionsFromConfiguredApp() {
    try {
      return DefaultFirebaseOptions.currentPlatform;
    } on UnsupportedError {
      return null;
    }
  }

  static Future<void> ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized || kIsWeb) {
      return;
    }

    try {
      await GoogleSignIn.instance.initialize();
      await GoogleSignIn.instance.attemptLightweightAuthentication();
    } finally {
      _googleSignInInitialized = true;
    }
  }

  static FirebaseOptions? _optionsFromEnvironment() {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const messagingSenderId = String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
    );
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
