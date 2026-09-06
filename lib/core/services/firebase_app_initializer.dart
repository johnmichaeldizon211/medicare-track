import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseAppInitializer {
  FirebaseAppInitializer._();

  static const _apiKey = 'AIzaSyD875qAvneFmdKTtxy7IYeuexEpzK-XjOg';
  static const _projectId = 'medicare-track-af1cf';
  static const _messagingSenderId = '750611042559';
  static const _storageBucket = 'medicare-track-af1cf.firebasestorage.app';

  static const _androidOptions = FirebaseOptions(
    apiKey: _apiKey,
    appId: '1:750611042559:android:280fff3c2dfb638ac9fcca',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    storageBucket: _storageBucket,
  );

  static const _webOptions = FirebaseOptions(
    apiKey: _apiKey,
    appId: '1:750611042559:web:280fff3c2dfb638ac9fcca',
    messagingSenderId: _messagingSenderId,
    projectId: _projectId,
    authDomain: 'medicare-track-af1cf.firebaseapp.com',
    storageBucket: _storageBucket,
  );

  static FirebaseOptions get currentOptions {
    if (kIsWeb) {
      return _webOptions;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidOptions;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return _webOptions;
    }
  }

  static Future<void> initialize() async {
    if (Firebase.apps.isNotEmpty) {
      return;
    }

    await Firebase.initializeApp(options: currentOptions);
  }
}
