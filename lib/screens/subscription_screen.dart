import 'package:flutter/material.dart';

import '../models/subscription_plan.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({
    super.key,
    required this.plans,
    required this.onBack,
    required this.onContinue,
  });

  final List<SubscriptionPlan> plans;
  final VoidCallback onBack;
  final Future<bool> Function(SubscriptionPlan) onContinue;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late SubscriptionPlan _selected;
  bool _isActivating = false;
  String? _errorMessage;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _selected = widget.plans.length > 1 ? widget.plans[1] : widget.plans.first;
  }

  Future<void> _subscribe() async {
    setState(() {
      _isActivating = true;
      _errorMessage = null;
      _statusMessage = null;
    });
    try {
      final activated = await widget.onContinue(_selected);
      if (!mounted || activated) return;
      setState(
        () => _statusMessage =
            'Complete payment in Stripe Checkout, then return to StreamFlix.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () =>
            _errorMessage = 'Stripe Checkout could not be started. Try again.',
      );
    } finally {
      if (mounted) setState(() => _isActivating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const BrandLogo(compact: true),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                children: [
                  Text(
                    'Choose Your Plan',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'One month of access starts when you subscribe.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 24),
                  ...widget.plans.map(
                    (plan) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _PlanCard(
                        plan: plan,
                        selected: plan == _selected,
                        onTap: () => setState(() => _selected = plan),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _TrustItem(Icons.devices_rounded, 'Watch anywhere'),
                      _TrustItem(Icons.shield_outlined, 'Secure & safe'),
                      _TrustItem(Icons.headset_mic_outlined, '24/7 support'),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.violetLight),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                14,
                20,
                MediaQuery.paddingOf(context).bottom + 14,
              ),
              decoration: const BoxDecoration(
                color: AppColors.inkSoft,
                border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isActivating ? null : _subscribe,
                  child: _isActivating
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('Subscribe to ${_selected.name}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final SubscriptionPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.violet.withValues(alpha: .16)
              : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.gold
                : Colors.white.withValues(alpha: .09),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            plan.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (plan.recommended) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.violet,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'POPULAR',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plan.description,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  plan.price,
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Text('/mo', style: TextStyle(color: AppColors.muted)),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              runSpacing: 7,
              children: plan.features
                  .map(
                    (feature) => SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 17,
                            color: AppColors.violetLight,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 100,
    child: Column(
      children: [
        Icon(icon, color: AppColors.violetLight),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    ),
  );
}
