import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models/subscription_plan.dart';
import 'models/member_profile.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/opening_video_screen.dart';
import 'screens/google_onboarding_screen.dart';
import 'screens/reset_password_screen.dart';
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
  bool _checkoutPending = false;
  String _planName = 'Basic';
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
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _expiryTimer?.cancel();
        setState(() {
          _page = _AppPage.resetPassword;
          _subscriptionError = null;
          _activeProfile = null;
        });
      } else if (state.session != null && _page == _AppPage.login) {
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
        _page != _AppPage.resetPassword &&
        _page != _AppPage.opening &&
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

  Future<void> _resetPassword(String email) async {
    final client = widget.supabase;
    if (client == null) throw StateError('Supabase is not configured.');
    await client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: SupabaseService.oauthRedirectUri,
    );
  }

  Future<void> _completePasswordRecovery(String password) async {
    final client = widget.supabase;
    if (client?.auth.currentSession == null) {
      throw const AuthException(
        'This password reset link has expired. Request a new one.',
      );
    }
    await client!.auth.updateUser(UserAttributes(password: password));
    await client.auth.signOut();
    if (!mounted) return;
    setState(() {
      _page = _AppPage.login;
      _subscriptionError = null;
      _activeProfile = null;
    });
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
    if (client == null ||
        client.auth.currentSession == null ||
        _page == _AppPage.resetPassword) {
      return;
    }
    try {
      final rows = await client.rpc('get_my_google_onboarding_state') as List;
      final requiresOnboarding =
          rows.isNotEmpty &&
          (rows.first as Map<String, dynamic>)['requires_onboarding'] == true;
      if (!mounted || _page == _AppPage.resetPassword) return;
      if (requiresOnboarding) {
        setState(() => _page = _AppPage.googleOnboarding);
        return;
      }
      await _resolveSubscription(preserveActivePage: preserveActivePage);
    } catch (_) {
      if (!mounted || _page == _AppPage.resetPassword) return;
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
    if (client == null ||
        client.auth.currentSession == null ||
        _page == _AppPage.resetPassword) {
      return;
    }
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
      var status = await service.fetchStatus();
      if (_checkoutPending && !status.isActive) {
        for (var attempt = 0; attempt < 10 && !status.isActive; attempt++) {
          await Future<void>.delayed(const Duration(seconds: 1));
          status = await service.fetchStatus();
        }
      }
      final activePlan = status.isActive
          ? plans.where((plan) => plan.id == status.subscriptionId).firstOrNull
          : null;
      if (status.isActive && activePlan == null) {
        throw StateError('The active subscription plan could not be found.');
      }
      if (!mounted || _page == _AppPage.resetPassword) return;
      setState(() {
        _plans = plans;
        _planName = activePlan?.name ?? 'Basic';
        _page = activePlan == null
            ? _AppPage.subscription
            : preserveActivePage &&
                  (previousPage == _AppPage.profiles ||
                      previousPage == _AppPage.main)
            ? previousPage
            : _AppPage.profiles;
      });
      _scheduleExpiry(status.isActive ? status.endDate : null);
      _checkoutPending = false;
    } catch (_) {
      if (!mounted || _page == _AppPage.resetPassword) return;
      setState(() {
        _subscriptionError = 'We could not check your subscription. Try again.';
        _page = _AppPage.loading;
      });
    } finally {
      _isResolvingSubscription = false;
    }
  }

  Future<bool> _startSubscriptionCheckout(SubscriptionPlan plan) async {
    final client = widget.supabase;
    if (client == null || client.auth.currentSession == null) {
      throw StateError('Sign in before subscribing.');
    }
    final service = SubscriptionService(client);
    final checkout = await service.startCheckout(plan);
    if (!checkout.updated) {
      final uri = checkout.checkoutUrl;
      _checkoutPending = true;
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _checkoutPending = false;
        throw StateError('Stripe Checkout could not be opened.');
      }
      return false;
    }
    _checkoutPending = false;
    final status = await service.fetchStatus();
    if (!status.isActive) throw StateError('Subscription is not active.');
    if (!mounted) return true;
    setState(() {
      _planName = status.planName ?? plan.name;
      _page = _AppPage.profiles;
    });
    _scheduleExpiry(status.endDate);
    return true;
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
            onPasswordReset: _resetPassword,
            onRegister: _registerWithEmail,
            onGoogleSignIn: _signInWithGoogle,
          ),
          _AppPage.resetPassword => ResetPasswordScreen(
            key: const ValueKey('reset-password-page'),
            onSubmit: _completePasswordRecovery,
          ),
          _AppPage.googleOnboarding => GoogleOnboardingScreen(
            key: const ValueKey('google-onboarding'),
            email: widget.supabase!.auth.currentUser?.email ?? '',
            onSubmit: _completeGoogleOnboarding,
            onSignOut: _signOut,
          ),
          _AppPage.opening => OpeningVideoScreen(
            key: const ValueKey('opening'),
            supabase: widget.supabase!,
            onComplete: () => setState(() => _page = _AppPage.main),
          ),
          _AppPage.subscription => SubscriptionScreen(
            key: const ValueKey('subscription'),
            plans: _plans,
            onBack: _signOut,
            onContinue: _startSubscriptionCheckout,
          ),
          _AppPage.profiles => SubscriberProfilesScreen(
            key: const ValueKey('profiles'),
            supabase: widget.supabase!,
            onBack: _activeProfile == null
                ? _signOut
                : () => setState(() => _page = _AppPage.main),
            onContinue: (profile) => setState(() {
              _activeProfile = profile;
              _page = _AppPage.opening;
            }),
          ),
          _AppPage.main => MainShell(
            key: const ValueKey('main'),
            supabase: widget.supabase!,
            activeProfile: _activeProfile!,
            planName: _planName,
            onProfileChanged: (profile) =>
                setState(() => _activeProfile = profile),
            onProfileDeleted: () => setState(() {
              _activeProfile = null;
              _page = _AppPage.profiles;
            }),
            onManageProfiles: () => setState(() => _page = _AppPage.profiles),
            onSubscriptionChanged: () =>
                _resolveSubscription(preserveActivePage: true),
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

enum _AppPage {
  loading,
  login,
  resetPassword,
  googleOnboarding,
  opening,
  subscription,
  profiles,
  main,
}
