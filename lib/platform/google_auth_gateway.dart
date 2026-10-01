import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Identity data returned by the native Google Sign-In flow.
///
/// The ID token is short-lived and is only handed to Better Auth immediately;
/// this object must not be persisted or logged.
class GoogleAccountIdentity {
  const GoogleAccountIdentity({
    required this.email,
    required this.idToken,
    this.displayName,
    this.photoUrl,
  });

  final String email;
  final String idToken;
  final String? displayName;
  final String? photoUrl;
}

abstract interface class GoogleAccountAuthGateway {
  bool get isSupported;

  bool get isConfigured;

  Future<GoogleAccountIdentity> signIn();
}

class GoogleAccountAuthException implements Exception {
  const GoogleAccountAuthException(this.message, {this.setupNeeded = false});

  final String message;
  final bool setupNeeded;

  @override
  String toString() => message;
}

/// Native account identity provider backed by google_sign_in 7.2.x.
///
/// Android is initialized by the existing calendar gateway during app startup,
/// so this gateway reuses that initialized singleton and never requests
/// Calendar scopes. iOS and macOS can initialize the same singleton themselves
/// when those platforms are wired into the app.
class NativeGoogleAccountAuthGateway implements GoogleAccountAuthGateway {
  NativeGoogleAccountAuthGateway({
    String? serverClientId,
    String? nativeClientId,
    GoogleSignIn? signIn,
    TargetPlatform? platform,
    bool? web,
    bool assumeAndroidInitialized = true,
  }) : _platform = platform ?? defaultTargetPlatform,
       _isWeb = web ?? kIsWeb,
       _serverClientId =
           serverClientId ??
           const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID'),
       _nativeClientId =
           nativeClientId ??
           _nativeClientIdFromEnvironment(platform ?? defaultTargetPlatform),
       _signIn = signIn ?? GoogleSignIn.instance,
       _assumeAndroidInitialized = assumeAndroidInitialized;

  final TargetPlatform _platform;
  final bool _isWeb;
  final String _serverClientId;
  final String _nativeClientId;
  final GoogleSignIn _signIn;
  final bool _assumeAndroidInitialized;
  bool _initialized = false;

  static String _nativeClientIdFromEnvironment(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.iOS:
        return const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
      case TargetPlatform.macOS:
        return const String.fromEnvironment('GOOGLE_MACOS_CLIENT_ID');
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return '';
    }
  }

  @override
  bool get isSupported =>
      !_isWeb &&
      (_platform == TargetPlatform.android ||
          _platform == TargetPlatform.iOS ||
          _platform == TargetPlatform.macOS);

  @override
  bool get isConfigured {
    if (!isSupported || _serverClientId.trim().isEmpty) return false;
    if (_platform == TargetPlatform.android) return true;
    return _nativeClientId.trim().isNotEmpty;
  }

  String get setupMessage {
    if (_isWeb) {
      return 'Web uses the server Google redirect flow instead of native sign-in.';
    }
    if (!isSupported) return 'Native Google sign-in is unavailable on this platform.';
    if (_serverClientId.trim().isEmpty) {
      return 'This build needs GOOGLE_SERVER_CLIENT_ID, the Google web OAuth client ID.';
    }
    if (_platform == TargetPlatform.iOS && _nativeClientId.trim().isEmpty) {
      return 'This iOS build needs GOOGLE_IOS_CLIENT_ID, the native OAuth client ID.';
    }
    if (_platform == TargetPlatform.macOS && _nativeClientId.trim().isEmpty) {
      return 'This macOS build needs GOOGLE_MACOS_CLIENT_ID, the native OAuth client ID.';
    }
    return 'Google sign-in needs native OAuth configuration for this build.';
  }

  Future<void> _initialize() async {
    if (_initialized || !isSupported || !isConfigured) return;

    // PlatformServices initializes GoogleSignIn.instance through the existing
    // Android Calendar gateway before runApp. Do not call initialize twice:
    // google_sign_in documents initialize as an exactly-once operation.
    if (_platform == TargetPlatform.android && _assumeAndroidInitialized) {
      _initialized = true;
      return;
    }

    await _signIn.initialize(
      clientId: _nativeClientId.trim().isEmpty ? null : _nativeClientId.trim(),
      serverClientId: _serverClientId.trim(),
    );
    _initialized = true;
  }

  @override
  Future<GoogleAccountIdentity> signIn() async {
    if (!isConfigured) {
      throw GoogleAccountAuthException(setupMessage, setupNeeded: true);
    }

    await _initialize();
    try {
      final account = await _signIn.authenticate();
      final idToken = account.authentication.idToken?.trim();
      if (idToken == null || idToken.isEmpty) {
        throw const GoogleAccountAuthException(
          'Google did not return an ID token for the configured server client.',
        );
      }
      return GoogleAccountIdentity(
        email: account.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
        idToken: idToken,
      );
    } on GoogleAccountAuthException {
      rethrow;
    } on GoogleSignInException catch (error) {
      final description = error.description?.trim();
      final detail = description == null || description.isEmpty
          ? ''
          : ' $description';
      final setupError =
          error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError;
      throw GoogleAccountAuthException(
        setupError
            ? 'Google sign-in is not configured for this native build.$detail'
            : error.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was canceled.'
            : 'Google sign-in failed.$detail',
        setupNeeded: setupError,
      );
    }
  }
}

final GoogleAccountAuthGateway defaultGoogleAccountAuthGateway =
    NativeGoogleAccountAuthGateway();
