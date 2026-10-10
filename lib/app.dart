import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/subscription_plan.dart';
import 'models/member_profile.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/google_onboarding_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/subscriber_profiles_screen.dart';
import 'services/subscription_service.dart';
import 'services/supabase_service.dart';
import 'theme/app_theme.dart';

class StreamFlixApp extends StatefulWidget {
  const StreamFlixApp({super.key, this.supabase});

  final SupabaseClient? supabase;

  @override
  State<StreamFlixApp> createState() => _StreamFlixAppState();
}

class _StreamFlixAppState extends State<StreamFlixApp>
    with WidgetsBindingObserver {
  late _AppPage _page;
  List<SubscriptionPlan> _plans = fallbackSubscriptionPlans;
  String? _subscriptionError;
  bool _isResolvingSubscription = false;
  MemberProfile? _activeProfile;
  Timer? _expiryTimer;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final auth = widget.supabase?.auth;
    _page = auth?.currentSession == null ? _AppPage.login : _AppPage.loading;
    if (auth?.currentSession != null) {
      unawaited(_routeAuthenticatedSession());
    }
    _authSubscription = auth?.onAuthStateChange.listen((state) {
      if (!mounted) return;
      if (state.session != null && _page == _AppPage.login) {
        setState(() => _page = _AppPage.loading);
        unawaited(_routeAuthenticatedSession());
      } else if (state.session == null && _page != _AppPage.login) {
        _expiryTimer?.cancel();
        setState(() {
          _page = _AppPage.login;
          _subscriptionError = null;
          _activeProfile = null;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.supabase?.auth.currentSession != null &&
        _page != _AppPage.login &&
        _page != _AppPage.loading) {
      unawaited(_routeAuthenticatedSession(preserveActivePage: true));
    }
  }

  Future<void> _signInWithGoogle() async {
    final client = widget.supabase;
    if (client == null) {
      throw StateError('Supabase is not configured.');
    }
    await SupabaseService.signInWithGoogle(client);
  }

  Future<void> _signInWithEmail(String email, String password) async {
    final client = widget.supabase;
    if (client == null) {
      throw StateError('Supabase is not configured.');
    }
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<bool> _registerWithEmail(
    String email,
    String password,
    Map<String, dynamic> metadata,
  ) async {
    final client = widget.supabase;
    if (client == null) {
      throw StateError('Supabase is not configured.');
    }
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      data: metadata,
    );
    return response.session != null;
  }

  Future<void> _routeAuthenticatedSession({
    bool preserveActivePage = false,
  }) async {
    final client = widget.supabase;
    if (client == null || client.auth.currentSession == null) return;
    try {
      final rows = await client.rpc('get_my_google_onboarding_state') as List;
      final requiresOnboarding =
          rows.isNotEmpty &&
          (rows.first as Map<String, dynamic>)['requires_onboarding'] == true;
      if (!mounted) return;
      if (requiresOnboarding) {
        setState(() => _page = _AppPage.googleOnboarding);
        return;
      }
      await _resolveSubscription(preserveActivePage: preserveActivePage);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _subscriptionError = 'We could not check your account. Try again.';
        _page = _AppPage.loading;
      });
    }
  }

  Future<void> _completeGoogleOnboarding(
    DateTime birthDate,
    String password,
  ) async {
    final client = widget.supabase;
    if (client == null || client.auth.currentUser == null) {
      throw const AuthException('Your Google session has expired.');
    }

    final formattedBirthDate =
        '${birthDate.year.toString().padLeft(4, '0')}-'
        '${birthDate.month.toString().padLeft(2, '0')}-'
        '${birthDate.day.toString().padLeft(2, '0')}';
    await client.rpc(
      'complete_my_google_onboarding',
      params: {'selected_birth_date': formattedBirthDate},
    );
    await client.auth.updateUser(
      UserAttributes(
        password: password,
        data: {
          'streamflix_onboarding_complete': true,
          'date_of_birth': formattedBirthDate,
        },
      ),
    );
    if (!mounted) return;
    setState(() => _page = _AppPage.loading);
    await _resolveSubscription();
  }

  Future<void> _signOut() async {
    await widget.supabase?.auth.signOut();
    if (mounted) {
      setState(() {
        _page = _AppPage.login;
        _subscriptionError = null;
        _activeProfile = null;
      });
      _expiryTimer?.cancel();
    }
  }

  Future<void> _resolveSubscription({bool preserveActivePage = false}) async {
    final client = widget.supabase;
    if (client == null || client.auth.currentSession == null) return;
    if (_isResolvingSubscription) return;
    _isResolvingSubscription = true;
    final previousPage = _page;
    if (mounted) {
      setState(() {
        _page = _AppPage.loading;
        _subscriptionError = null;
      });
    }

    try {
      final service = SubscriptionService(client);
      final plans = await service.fetchPlans();
      if (plans.isEmpty) {
        throw StateError('No subscription plans are available.');
      }
      final status = await service.fetchStatus();
      final activePlan = status.isActive
          ? plans.where((plan) => plan.id == status.subscriptionId).firstOrNull
          : null;
      if (status.isActive && activePlan == null) {
        throw StateError('The active subscription plan could not be found.');
      }
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _page = activePlan == null
            ? _AppPage.subscription
            : preserveActivePage &&
                  (previousPage == _AppPage.profiles ||
                      previousPage == _AppPage.main)
            ? previousPage
            : _AppPage.profiles;
      });
      _scheduleExpiry(status.isActive ? status.endDate : null);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _subscriptionError = 'We could not check your subscription. Try again.';
        _page = _AppPage.loading;
      });
    } finally {
      _isResolvingSubscription = false;
    }
  }

  Future<void> _activateSubscription(SubscriptionPlan plan) async {
    final client = widget.supabase;
    if (client == null || client.auth.currentSession == null) {
      throw StateError('Sign in before subscribing.');
    }
    final status = await SubscriptionService(client).activate(plan);
    if (!status.isActive) throw StateError('Subscription is not active.');
    if (!mounted) return;
    setState(() {
      _page = _AppPage.profiles;
    });
    _scheduleExpiry(status.endDate);
  }

  void _scheduleExpiry(DateTime? endDate) {
    _expiryTimer?.cancel();
    if (endDate == null) return;
    final remaining = endDate.toUtc().difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      unawaited(_resolveSubscription());
      return;
    }
    _expiryTimer = Timer(remaining, _resolveSubscription);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamFlix',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_page) {
          _AppPage.loading => _SubscriptionLoadingView(
            key: const ValueKey('subscription-loading'),
            errorMessage: _subscriptionError,
            onRetry: _routeAuthenticatedSession,
            onSignOut: _signOut,
          ),
          _AppPage.login => LoginScreen(
            key: const ValueKey('login'),
            onEmailSignIn: _signInWithEmail,
            onRegister: _registerWithEmail,
            onGoogleSignIn: _signInWithGoogle,
          ),
          _AppPage.googleOnboarding => GoogleOnboardingScreen(
            key: const ValueKey('google-onboarding'),
            email: widget.supabase!.auth.currentUser?.email ?? '',
            onSubmit: _completeGoogleOnboarding,
            onSignOut: _signOut,
          ),
          _AppPage.subscription => SubscriptionScreen(
            key: const ValueKey('subscription'),
            plans: _plans,
            onBack: _signOut,
            onContinue: _activateSubscription,
          ),
          _AppPage.profiles => SubscriberProfilesScreen(
            key: const ValueKey('profiles'),
            supabase: widget.supabase!,
            onBack: _activeProfile == null
                ? _signOut
                : () => setState(() => _page = _AppPage.main),
            onContinue: (profile) => setState(() {
              _activeProfile = profile;
              _page = _AppPage.main;
            }),
          ),
          _AppPage.main => MainShell(
            key: const ValueKey('main'),
            supabase: widget.supabase!,
            activeProfile: _activeProfile!,
            onProfileChanged: (profile) =>
                setState(() => _activeProfile = profile),
            onManageProfiles: () => setState(() => _page = _AppPage.profiles),
            onSignOut: _signOut,
          ),
        },
      ),
    );
  }
}

class _SubscriptionLoadingView extends StatelessWidget {
  const _SubscriptionLoadingView({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    required this.onSignOut,
  });

  final String? errorMessage;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: errorMessage == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: onSignOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

enum _AppPage { loading, login, googleOnboarding, subscription, profiles, main }
