import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/groups_api.dart';
import '../platform/google_auth_gateway.dart';
import '../platform/google_auth_redirect.dart';

class AccountPage extends StatefulWidget {
  AccountPage({
    super.key,
    required this.api,
    GoogleAccountAuthGateway? googleAuth,
  }) : googleAuth = googleAuth ?? defaultGoogleAccountAuthGateway;

  final GroupsApi api;
  final GoogleAccountAuthGateway googleAuth;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

enum _AccountState { loading, setup, signedOut, signedIn, offline, error }

class _AccountPageState extends State<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _AccountState _state = _AccountState.loading;
  String? _accountLabel;
  String? _error;
  bool _signUp = false;
  bool _submitting = false;
  bool _googleHealthKnown = false;
  bool _googleServerConfigured = false;
  String? _googleStatusMessage;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    if (mounted) {
      setState(() {
        _state = _AccountState.loading;
        _error = null;
        _googleStatusMessage = null;
      });
    }
    try {
      final health = await widget.api.health();
      if (!mounted) return;
      setState(() {
        _googleHealthKnown = true;
        _googleServerConfigured = health.googleConfigured;
        _googleStatusMessage = null;
      });

      final session = await widget.api.request('GET', '/api/session');
      if (!mounted) return;
      setState(() {
        _state = _AccountState.signedIn;
        _accountLabel = _accountLabelFromSession(session);
        _error = null;
      });
    } on GroupsSignedOut {
      if (mounted) setState(() => _state = _AccountState.signedOut);
    } on GroupsSetupNeeded {
      if (mounted) setState(() => _state = _AccountState.setup);
    } on GroupsOffline catch (error) {
      if (mounted) {
        setState(() {
          _state = _AccountState.offline;
          _error = error.message;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _state = _AccountState.error;
          _error = _safeMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                switch (_state) {
                  _AccountState.loading => const _AccountLoading(),
                  _AccountState.setup => _AccountMessage(
                    icon: Icons.settings_suggest_outlined,
                    title: 'Server setup needed',
                    message: 'Connect this build to the configured server. Your local tracker is still available.',
                    action: 'Try again',
                    onAction: _loadSession,
                  ),
                  _AccountState.signedOut => _SignedOutCard(
                    formKey: _formKey,
                    name: _name,
                    email: _email,
                    password: _password,
                    signUp: _signUp,
                    submitting: _submitting,
                    error: _error,
                    googleAvailable: _googleAvailable,
                    googleMessage: _googleAvailabilityMessage,
                    onSubmit: _submit,
                    onGoogleSignIn: _continueWithGoogle,
                    onToggleMode: _toggleMode,
                  ),
                  _AccountState.signedIn => _SignedInCard(
                    label: _accountLabel,
                    submitting: _submitting,
                    onSignOut: _signOut,
                  ),
                  _AccountState.offline => _AccountMessage(
                    icon: Icons.cloud_off_outlined,
                    title: 'Offline',
                    message: _error ?? 'Could not reach the server. Your local tracker is still available.',
                    action: 'Try again',
                    onAction: _loadSession,
                  ),
                  _AccountState.error => _AccountMessage(
                    icon: Icons.error_outline,
                    title: 'Account unavailable',
                    message: _error ?? 'Something went wrong. Try again.',
                    action: 'Try again',
                    onAction: _loadSession,
                  ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _googleAvailable =>
      _googleHealthKnown &&
      _googleServerConfigured &&
      (kIsWeb ||
          (widget.googleAuth.isSupported && widget.googleAuth.isConfigured));

  String get _googleAvailabilityMessage {
    if (_googleStatusMessage != null) return _googleStatusMessage!;
    if (!_googleHealthKnown || !_googleServerConfigured) {
      return 'Google sign-in setup needed: configure the Google provider on the server.';
    }
    if (kIsWeb) return '';
    if (!widget.googleAuth.isSupported) {
      return 'Google sign-in setup needed: this platform is not supported.';
    }
    if (!widget.googleAuth.isConfigured) {
      final native = widget.googleAuth;
      final detail = native is NativeGoogleAccountAuthGateway
          ? native.setupMessage
          : 'add the native client IDs to this build.';
      return 'Google sign-in setup needed: $detail';
    }
    return '';
  }

  Future<void> _continueWithGoogle() async {
    if (_submitting || !_googleAvailable) return;
    setState(() {
      _submitting = true;
      _error = null;
      _googleStatusMessage = null;
    });
    try {
      if (kIsWeb) {
        final url = await widget.api.beginGoogleWebSignIn();
        redirectToGoogleAuth(url);
        return;
      }

      final identity = await widget.googleAuth.signIn();
      final result = await widget.api.signInWithGoogleIdToken(identity.idToken);
      if (!mounted) return;
      setState(() {
        _state = _AccountState.signedIn;
        _accountLabel = _accountLabelFromUser(result['user']) ?? identity.email;
        _error = null;
      });
    } on GroupsSetupNeeded {
      if (mounted) {
        setState(() {
          _googleServerConfigured = false;
          _googleHealthKnown = true;
          _googleStatusMessage = 'Google sign-in setup needed: the server provider is not configured.';
          _state = _AccountState.signedOut;
        });
      }
    } on GoogleAccountAuthException catch (error) {
      if (mounted) {
        setState(() {
          _state = _AccountState.signedOut;
          if (error.setupNeeded) {
            _googleStatusMessage = error.message;
          } else {
            _error = error.message;
          }
        });
      }
    } on GroupsOffline catch (error) {
      if (mounted) {
        setState(() {
          _state = _AccountState.offline;
          _error = error.message;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _state = _AccountState.signedOut;
          _error = _safeMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toggleMode() {
    if (_submitting) return;
    setState(() {
      _signUp = !_signUp;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = _signUp
          ? await widget.api.signUp(name, email, password)
          : await widget.api.signIn(email, password);
      if (!mounted) return;
      setState(() {
        _state = _AccountState.signedIn;
        _accountLabel = _accountLabelFromUser(result['user']) ?? email;
        _error = null;
        _password.clear();
      });
    } on GroupsSetupNeeded {
      if (mounted) setState(() => _state = _AccountState.setup);
    } on GroupsOffline catch (error) {
      if (mounted) {
        setState(() {
          _state = _AccountState.offline;
          _error = error.message;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _state = _AccountState.signedOut;
          _error = _safeMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signOut() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.api.signOut();
      if (mounted) {
        setState(() {
          _state = _AccountState.signedOut;
          _accountLabel = null;
          _password.clear();
        });
      }
    } on GroupsOffline catch (error) {
      if (mounted) {
        setState(() {
          _state = _AccountState.offline;
          _error = error.message;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _state = _AccountState.error;
          _error = _safeMessage(error);
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The account screen names the signed-in person. Raw account ids and
  /// session material must never be rendered or copyable.
  static String? _accountLabelFromSession(Map<String, Object?> session) {
    final email = session['email']?.toString().trim();
    if (email != null && email.isNotEmpty) return email;
    final name = session['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    return null;
  }

  static String? _accountLabelFromUser(Object? user) {
    if (user is! Map) return null;
    final email = user['email']?.toString().trim();
    if (email != null && email.isNotEmpty) return email;
    final name = user['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    return null;
  }
}

class _AccountLoading extends StatelessWidget {
  const _AccountLoading();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SizedBox(height: 80),
      CircularProgressIndicator(),
      SizedBox(height: 18),
      Text('Loading account…'),
    ],
  );
}

class _SignedOutCard extends StatelessWidget {
  const _SignedOutCard({
    required this.formKey,
    required this.name,
    required this.email,
    required this.password,
    required this.signUp,
    required this.submitting,
    required this.error,
    required this.googleAvailable,
    required this.googleMessage,
    required this.onSubmit,
    required this.onGoogleSignIn,
    required this.onToggleMode,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController password;
  final bool signUp;
  final bool submitting;
  final String? error;
  final bool googleAvailable;
  final String googleMessage;
  final VoidCallback onSubmit;
  final VoidCallback onGoogleSignIn;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.account_circle_outlined,
                size: 52,
                color: colors.primary,
              ),
              const SizedBox(height: 14),
              Text(
                signUp ? 'Create your account' : 'Sign in to sync',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your local tracker stays usable without an account. Online groups remain unavailable until Iteration 3.',
              ),
              const SizedBox(height: 20),
              if (signUp) ...[
                TextFormField(
                  key: const ValueKey('account-name'),
                  controller: name,
                  enabled: !submitting,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Enter your name' : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                key: const ValueKey('account-email'),
                controller: email,
                enabled: !submitting,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) =>
                    RegExp(r'^\S+@\S+\.\S+$').hasMatch((value ?? '').trim())
                    ? null
                    : 'Enter a valid email',
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('account-password'),
                controller: password,
                enabled: !submitting,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: submitting ? null : (_) => onSubmit(),
                decoration: const InputDecoration(labelText: 'Password'),
                validator: (value) => (value ?? '').length < 8
                    ? 'Use at least 8 characters'
                    : null,
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                Text(error!, style: TextStyle(color: colors.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: submitting ? null : onSubmit,
                child: Text(
                  submitting
                      ? 'Connecting…'
                      : signUp
                      ? 'Create account'
                      : 'Sign in',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('continue-with-google'),
                onPressed: !googleAvailable || submitting
                    ? null
                    : onGoogleSignIn,
                icon: const Icon(Icons.account_circle_outlined),
                label: Text('Continue with Google'),
              ),
              if (!googleAvailable && googleMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(googleMessage, style: TextStyle(color: colors.error)),
              ],
              TextButton(
                onPressed: submitting ? null : onToggleMode,
                child: Text(
                  signUp
                      ? 'Already have an account? Sign in'
                      : 'Create an account',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedInCard extends StatelessWidget {
  const _SignedInCard({
    required this.label,
    required this.submitting,
    required this.onSignOut,
  });

  final String? label;
  final bool submitting;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.verified_user_outlined, size: 52),
          const SizedBox(height: 14),
          Text('Signed in', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            label ?? 'This device',
            key: const ValueKey('account-label'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 10),
          const Text(
            'Groups stay unavailable until Iteration 3. Local goals remain on this device.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: submitting ? null : onSignOut,
            icon: const Icon(Icons.logout),
            label: Text(submitting ? 'Signing out…' : 'Sign out'),
          ),
        ],
      ),
    ),
  );
}

class _AccountMessage extends StatelessWidget {
  const _AccountMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(message),
          const SizedBox(height: 20),
          FilledButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );
}

String _safeMessage(Object error) {
  if (error is GroupsRequestError) return error.message;
  if (error is GroupsPermissionDenied) return error.message;
  if (error is GoogleAccountAuthException) return error.message;
  if (error is GroupsSignedOut) return 'Your session has ended. Sign in again.';
  return 'Could not complete the account request. Try again.';
}
