import 'package:flutter/material.dart';

import 'models/subscription_plan.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/profile_selection_screen.dart';
import 'screens/subscription_screen.dart';
import 'theme/app_theme.dart';

class StreamFlixApp extends StatefulWidget {
  const StreamFlixApp({super.key});

  @override
  State<StreamFlixApp> createState() => _StreamFlixAppState();
}

class _StreamFlixAppState extends State<StreamFlixApp> {
  _AppPage _page = _AppPage.login;
  SubscriptionPlan _plan = subscriptionPlans[1];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamFlix',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: switch (_page) {
          _AppPage.login => LoginScreen(
            key: const ValueKey('login'),
            onAuthenticate: () => setState(() => _page = _AppPage.subscription),
          ),
          _AppPage.subscription => SubscriptionScreen(
            key: const ValueKey('subscription'),
            onBack: () => setState(() => _page = _AppPage.login),
            onContinue: (plan) => setState(() {
              _plan = plan;
              _page = _AppPage.profiles;
            }),
          ),
          _AppPage.profiles => ProfileSelectionScreen(
            key: const ValueKey('profiles'),
            maxProfiles: _plan.maxUsers,
            onContinue: () => setState(() => _page = _AppPage.main),
          ),
          _AppPage.main => MainShell(
            key: const ValueKey('main'),
            onSignOut: () => setState(() => _page = _AppPage.login),
          ),
        },
      ),
    );
  }
}

enum _AppPage { login, subscription, profiles, main }
