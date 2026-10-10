import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/member_profile.dart';
import '../models/subscription_plan.dart';
import '../services/account_service.dart';
import '../services/settings_preferences.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

typedef AccountProfileUpdater =
    Future<void> Function({
      required String firstName,
      required String lastName,
      required DateTime birthDate,
    });

typedef SupportAttachmentPicker = Future<SupportAttachment?> Function();

String _dateLabel(DateTime? value) {
  if (value == null) return 'Not set';
  return '${value.month.toString().padLeft(2, '0')}/'
      '${value.day.toString().padLeft(2, '0')}/${value.year}';
}

class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({
    super.key,
    required this.supabase,
    this.loadDetails,
    this.updateProfile,
  });
  final SupabaseClient supabase;
  final Future<AccountSettings> Function()? loadDetails;
  final AccountProfileUpdater? updateProfile;

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  late Future<AccountSettings> _details;
  AccountService get _service => AccountService(widget.supabase);

  @override
  void initState() {
    super.initState();
    _details = _fetchDetails();
  }

  Future<AccountSettings> _fetchDetails() =>
      widget.loadDetails?.call() ?? _service.fetchSettings();

  void _reload() {
    setState(() {
      _details = _fetchDetails();
    });
  }

  Future<void> _editPersonalDetails(AccountSettings details) async {
    final firstName = TextEditingController(text: details.firstName);
    final lastName = TextEditingController(text: details.lastName);
    var birthDate = details.birthDate ?? DateTime(2000, 1, 1);
    String? error;
    var saving = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.inkSoft,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: _SheetHandle()),
                const SizedBox(height: 22),
                Text(
                  'Edit personal information',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'These details belong to the signed-in account, not a viewing profile.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: firstName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'First name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastName,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Last name'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          final selected = await showDatePicker(
                            context: context,
                            initialDate: birthDate,
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                            helpText: 'Select birthdate',
                          );
                          if (selected != null) {
                            setSheetState(() => birthDate = selected);
                          }
                        },
                  icon: const Icon(Icons.cake_outlined),
                  label: Text('Birthdate  ${_dateLabel(birthDate)}'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (firstName.text.trim().isEmpty) {
                            setSheetState(
                              () => error = 'First name is required.',
                            );
                            return;
                          }
                          setSheetState(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await (widget.updateProfile ??
                                _service.updateProfile)(
                              firstName: firstName.text,
                              lastName: lastName.text,
                              birthDate: birthDate,
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext, true);
                            }
                          } catch (_) {
                            setSheetState(() {
                              saving = false;
                              error = 'Details could not be saved. Try again.';
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Modal routes complete before their reverse transition has fully removed
    // every text-field listener. Dispose after that transition finishes.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    firstName.dispose();
    lastName.dispose();
    if (saved == true && mounted) {
      _reload();
      _showMessage('Personal information updated.');
    }
  }

  Future<void> _changeEmail(AccountSettings details) async {
    final email = TextEditingController(text: details.email);
    String? error;
    var saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change email address'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Supabase will send confirmation links before your sign-in email changes.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'New email address',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final value = email.text.trim();
                      if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(value)) {
                        setDialogState(() => error = 'Enter a valid email.');
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await _service.requestEmailChange(value);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (_) {
                        setDialogState(() {
                          saving = false;
                          error = 'Email change could not be requested.';
                        });
                      }
                    },
              child: Text(saving ? 'Sending…' : 'Continue'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    email.dispose();
    if (saved == true && mounted) {
      _showMessage('Check your inbox to confirm the new email address.');
    }
  }

  Future<void> _changePassword() async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (password.text.length < 8) {
                  setDialogState(() => error = 'Use at least 8 characters.');
                  return;
                }
                if (password.text != confirm.text) {
                  setDialogState(() => error = 'Passwords do not match.');
                  return;
                }
                try {
                  await _service.changePassword(password.text);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (_) {
                  setDialogState(
                    () => error = 'Password could not be changed.',
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    password.dispose();
    confirm.dispose();
    if (saved == true && mounted) _showMessage('Password updated securely.');
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _SettingsShell(
    title: 'Account details',
    subtitle: 'Personal information and membership details',
    child: FutureBuilder<AccountSettings>(
      future: _details,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return _ErrorCard(
            message: 'Account details could not be loaded.',
            onRetry: _reload,
          );
        }
        final details = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AccountSection(
              title: 'PERSONAL INFORMATION',
              description: 'Details used to identify your StreamFlix account.',
              rows: [
                _AccountRowData(
                  icon: Icons.person_outline_rounded,
                  label: 'Name',
                  value: '${details.firstName} ${details.lastName}'.trim(),
                  action: 'Edit',
                  onTap: () => _editPersonalDetails(details),
                ),
                _AccountRowData(
                  icon: Icons.cake_outlined,
                  label: 'Birthdate',
                  value: _dateLabel(details.birthDate),
                  action: 'Edit',
                  onTap: () => _editPersonalDetails(details),
                ),
                _AccountRowData(
                  icon: Icons.alternate_email_rounded,
                  label: 'Email',
                  value: details.email,
                  action: 'Change',
                  onTap: () => _changeEmail(details),
                ),
                _AccountRowData(
                  icon: Icons.lock_outline_rounded,
                  label: 'Password',
                  value: '••••••••••••',
                  action: 'Change',
                  onTap: _changePassword,
                ),
              ],
            ),
            const SizedBox(height: 30),
            _AccountSection(
              title: 'MEMBERSHIP RECORD',
              description:
                  'Billing and entitlement values are managed by the subscription system.',
              rows: [
                _AccountRowData(
                  icon: Icons.workspace_premium_outlined,
                  label: 'Plan',
                  value: details.planName ?? 'No active plan',
                ),
                _AccountRowData(
                  icon: Icons.sell_outlined,
                  label: 'Monthly price',
                  value: details.monthlyPrice == null
                      ? 'Not set'
                      : '₱${details.monthlyPrice!.toStringAsFixed(0)}',
                ),
                _AccountRowData(
                  icon: Icons.group_outlined,
                  label: 'Profile limit',
                  value: details.maxUsers?.toString() ?? 'Not set',
                ),
                _AccountRowData(
                  icon: Icons.receipt_long_outlined,
                  label: 'Payment amount',
                  value: details.paymentAmount == null
                      ? 'Not set'
                      : '₱${details.paymentAmount!.toStringAsFixed(0)}',
                ),
                _AccountRowData(
                  icon: Icons.calendar_today_outlined,
                  label: 'Started',
                  value: _dateLabel(details.paymentDate),
                ),
                _AccountRowData(
                  icon: Icons.event_available_outlined,
                  label: 'Access until',
                  value: _dateLabel(details.subscriptionEnd),
                ),
                _AccountRowData(
                  icon: Icons.credit_card_outlined,
                  label: 'Payment method',
                  value: details.paymentMethod ?? 'Not set',
                ),
              ],
            ),
            const SizedBox(height: 30),
            _AccountSection(
              title: 'BILLING HISTORY',
              description: 'Your 12 most recent payment transactions.',
              rows: details.billingHistory.isEmpty
                  ? const [
                      _AccountRowData(
                        icon: Icons.receipt_long_outlined,
                        label: 'Transactions',
                        value: 'No billing history is available.',
                      ),
                    ]
                  : [
                      for (final transaction in details.billingHistory)
                        _AccountRowData(
                          icon: Icons.receipt_long_outlined,
                          label: _dateLabel(transaction.paidAt),
                          value:
                              '₱${transaction.amount.toStringAsFixed(2)} · '
                              '${transaction.status}\n'
                              '${transaction.paymentMethod ?? 'Payment method unavailable'}',
                        ),
                    ],
            ),
          ],
        );
      },
    ),
  );
}

class _AccountRowData {
  const _AccountRowData({
    required this.icon,
    required this.label,
    required this.value,
    this.action,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? action;
  final VoidCallback? onTap;
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.title,
    required this.description,
    required this.rows,
  });

  final String title;
  final String description;
  final List<_AccountRowData> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.violetLight,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.15,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const Divider(height: 1, color: AppColors.gold),
      for (var index = 0; index < rows.length; index++) ...[
        _AccountFieldRow(data: rows[index]),
        if (index < rows.length - 1)
          const Divider(height: 1, color: AppColors.gold),
      ],
    ],
  );
}

class _AccountFieldRow extends StatelessWidget {
  const _AccountFieldRow({required this.data});
  final _AccountRowData data;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 360;
    final label = Text(
      data.label,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        height: 1.3,
      ),
    );
    final icon = Icon(data.icon, color: AppColors.violetLight, size: 23);
    final value = SelectableText(
      data.value,
      style: const TextStyle(
        color: Color(0xFFC5BECE),
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
    );
    final action = data.action == null
        ? null
        : TextButton(
            onPressed: data.onTap,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.gold,
              minimumSize: const Size(64, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(data.action!),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: 11),
                    Expanded(child: label),
                    ?action,
                  ],
                ),
                const SizedBox(height: 7),
                value,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 126,
                  child: Row(
                    children: [
                      icon,
                      const SizedBox(width: 11),
                      Expanded(child: label),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: value),
                if (action != null) ...[const SizedBox(width: 6), action],
              ],
            ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 4,
    decoration: BoxDecoration(
      color: AppColors.muted.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(99),
    ),
  );
}

class SubscriptionDetailsScreen extends StatefulWidget {
  const SubscriptionDetailsScreen({
    super.key,
    required this.supabase,
    required this.onSubscriptionCanceled,
  });
  final SupabaseClient supabase;
  final Future<void> Function() onSubscriptionCanceled;

  @override
  State<SubscriptionDetailsScreen> createState() =>
      _SubscriptionDetailsScreenState();
}

class _SubscriptionDetailsScreenState extends State<SubscriptionDetailsScreen>
    with WidgetsBindingObserver {
  late Future<SubscriptionStatus> _status;
  bool _busy = false;

  SubscriptionService get _service => SubscriptionService(widget.supabase);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _status = _service.fetchStatus());
  }

  Future<void> _changePlan(SubscriptionStatus status) async {
    try {
      final plans = availablePlanChanges(
        await _service.fetchPlans(),
        status.subscriptionId,
      );
      if (!mounted) return;
      final selected = await showModalBottomSheet<SubscriptionPlan>(
        context: context,
        showDragHandle: true,
        backgroundColor: AppColors.inkSoft,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                'Change plan',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              for (final plan in plans)
                ListTile(
                  title: Text(plan.name),
                  subtitle: Text(
                    '${plan.price}/month · ${plan.maxUsers} profiles',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, plan),
                ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      setState(() => _busy = true);
      final checkout = await _service.startCheckout(selected);
      if (checkout.updated) {
        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Plan changed to ${selected.name}.')),
          );
        }
        return;
      }
      final uri = checkout.checkoutUrl;
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Stripe Checkout could not be opened.');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('The plan could not be changed.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel membership?'),
        content: const Text(
          'Your access ends immediately. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep membership'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel membership'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.cancel();
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onSubscriptionCanceled();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('The membership could not be canceled.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsShell(
    title: 'Subscription',
    subtitle: 'Your current StreamFlix membership',
    child: FutureBuilder<SubscriptionStatus>(
      future: _status,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return const _ErrorCard(message: 'Subscription could not be loaded.');
        }
        final status = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.violetDeep, AppColors.card],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.violetLight.withValues(alpha: .35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: AppColors.gold,
                      ),
                      const Spacer(),
                      _StatusPill(active: status.isActive),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    status.planName ?? 'No active plan',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    status.monthlyPrice == null
                        ? 'Choose a plan to continue watching.'
                        : '₱${status.monthlyPrice!.toStringAsFixed(0)} per month',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _InfoCard(
              icon: Icons.people_outline_rounded,
              label: 'Profiles included',
              value: '${status.maxUsers ?? 0}',
              caption: 'Maximum active viewing profiles',
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.event_available_outlined,
              label: 'Started',
              value: _dateLabel(status.paymentDate),
              caption: 'Current billing period',
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.event_busy_outlined,
              label: 'Expires',
              value: _dateLabel(status.endDate),
              caption: 'Renew or choose another plan after expiration',
            ),
            if (status.isActive) ...[
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _busy ? null : () => _changePlan(status),
                child: const Text('Change plan'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : _cancel,
                child: const Text('Cancel membership'),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class PlaybackPrivacyScreen extends StatefulWidget {
  const PlaybackPrivacyScreen({super.key, required this.userId});
  final String userId;

  @override
  State<PlaybackPrivacyScreen> createState() => _PlaybackPrivacyScreenState();
}

class _PlaybackPrivacyScreenState extends State<PlaybackPrivacyScreen> {
  late final SettingsPreferences _preferences;
  bool _loading = true;
  bool _autoNext = true;
  bool _autoPreviews = true;
  bool _previewSounds = false;
  bool _searchHistory = true;
  bool _personalized = true;
  String _quality = 'Auto';
  String _dataUsage = 'High';
  String _subtitleSize = 'Medium';

  @override
  void initState() {
    super.initState();
    _preferences = SettingsPreferences(widget.userId);
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<Object>([
      _preferences.getBool('autoNext', true),
      _preferences.getBool('autoPreviews', true),
      _preferences.getBool('previewSounds', false),
      _preferences.getBool('searchHistory', true),
      _preferences.getBool('personalized', true),
      _preferences.getString('streamingQuality', 'Auto'),
      _preferences.getString('dataUsage', 'High'),
      _preferences.getString('subtitleSize', 'Medium'),
    ]);
    if (!mounted) return;
    setState(() {
      _autoNext = values[0] as bool;
      _autoPreviews = values[1] as bool;
      _previewSounds = values[2] as bool;
      _searchHistory = values[3] as bool;
      _personalized = values[4] as bool;
      _quality = values[5] as String;
      _dataUsage = values[6] as String;
      _subtitleSize = values[7] as String;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => _SettingsShell(
    title: 'Playback & privacy',
    subtitle: 'Control streaming behavior and activity data',
    child: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              _SettingsGroup(
                title: 'VIDEO PLAYBACK',
                children: [
                  _SwitchSetting(
                    title: 'Auto-play next episode',
                    subtitle: 'Continue a series automatically.',
                    value: _autoNext,
                    onChanged: (value) {
                      setState(() => _autoNext = value);
                      _preferences.setBool('autoNext', value);
                    },
                  ),
                  _SwitchSetting(
                    title: 'Auto-play previews',
                    subtitle: 'Play previews while browsing.',
                    value: _autoPreviews,
                    onChanged: (value) {
                      setState(() => _autoPreviews = value);
                      _preferences.setBool('autoPreviews', value);
                    },
                  ),
                  _SwitchSetting(
                    title: 'Preview sounds',
                    subtitle: 'Include audio in title previews.',
                    value: _previewSounds,
                    onChanged: (value) {
                      setState(() => _previewSounds = value);
                      _preferences.setBool('previewSounds', value);
                    },
                  ),
                  _ChoiceSetting(
                    title: 'Streaming quality',
                    value: _quality,
                    options: const [
                      'Auto',
                      'Low',
                      'Medium',
                      'High',
                      'Ultra HD',
                    ],
                    onChanged: (value) {
                      setState(() => _quality = value);
                      _preferences.setString('streamingQuality', value);
                    },
                  ),
                  _ChoiceSetting(
                    title: 'Data usage',
                    value: _dataUsage,
                    options: const ['Low', 'Medium', 'High', 'Unlimited'],
                    onChanged: (value) {
                      setState(() => _dataUsage = value);
                      _preferences.setString('dataUsage', value);
                    },
                  ),
                  _ChoiceSetting(
                    title: 'Subtitle size',
                    value: _subtitleSize,
                    options: const ['Small', 'Medium', 'Large', 'Extra Large'],
                    onChanged: (value) {
                      setState(() => _subtitleSize = value);
                      _preferences.setString('subtitleSize', value);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SettingsGroup(
                title: 'DATA & HISTORY',
                children: [
                  _SwitchSetting(
                    title: 'Search history',
                    subtitle: 'Keep recent searches available.',
                    value: _searchHistory,
                    onChanged: (value) {
                      setState(() => _searchHistory = value);
                      _preferences.setBool('searchHistory', value);
                    },
                  ),
                  _SwitchSetting(
                    title: 'Personalized recommendations',
                    subtitle: 'Use activity to suggest titles.',
                    value: _personalized,
                    onChanged: (value) {
                      setState(() => _personalized = value);
                      _preferences.setBool('personalized', value);
                    },
                  ),
                ],
              ),
            ],
          ),
  );
}

class DownloadSettingsScreen extends StatefulWidget {
  const DownloadSettingsScreen({super.key, required this.userId});
  final String userId;

  @override
  State<DownloadSettingsScreen> createState() => _DownloadSettingsScreenState();
}

class _DownloadSettingsScreenState extends State<DownloadSettingsScreen> {
  late final SettingsPreferences _preferences;
  bool _wifiOnly = true;
  String _quality = 'Standard';

  @override
  void initState() {
    super.initState();
    _preferences = SettingsPreferences(widget.userId);
    _load();
  }

  Future<void> _load() async {
    final wifi = await _preferences.getBool('downloadsWifiOnly', true);
    final quality = await _preferences.getString('downloadQuality', 'Standard');
    if (mounted) {
      setState(() {
        _wifiOnly = wifi;
        _quality = quality;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsShell(
    title: 'Downloads',
    subtitle: 'Choose how titles are saved on this device',
    child: _SettingsGroup(
      title: 'DOWNLOAD PREFERENCES',
      children: [
        _SwitchSetting(
          title: 'Wi-Fi only',
          subtitle: 'Prevent downloads over mobile data.',
          value: _wifiOnly,
          onChanged: (value) {
            setState(() => _wifiOnly = value);
            _preferences.setBool('downloadsWifiOnly', value);
          },
        ),
        _ChoiceSetting(
          title: 'Video quality',
          value: _quality,
          options: const ['Standard', 'High', 'Maximum'],
          onChanged: (value) {
            setState(() => _quality = value);
            _preferences.setString('downloadQuality', value);
          },
        ),
        const ListTile(
          leading: Icon(Icons.storage_outlined, color: AppColors.violetLight),
          title: Text('Storage'),
          subtitle: Text(
            'No downloaded titles yet',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      ],
    ),
  );
}

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key, required this.userId});
  final String userId;

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  static const _languages = [
    'English',
    'Filipino',
    'Spanish',
    'French',
    'German',
    'Japanese',
  ];
  late final SettingsPreferences _preferences;
  String _language = 'English';

  @override
  void initState() {
    super.initState();
    _preferences = SettingsPreferences(widget.userId);
    _load();
  }

  Future<void> _load() async {
    final language = await _preferences.getString('language', 'English');
    if (mounted) setState(() => _language = language);
  }

  @override
  Widget build(BuildContext context) => _SettingsShell(
    title: 'Language',
    subtitle: 'Select your preferred display language',
    child: _SettingsGroup(
      title: 'DISPLAY LANGUAGE',
      children: [
        for (final language in _languages)
          ListTile(
            title: Text(language),
            trailing: _language == language
                ? const Icon(Icons.check_rounded, color: AppColors.gold)
                : null,
            onTap: () {
              setState(() => _language = language);
              _preferences.setString('language', language);
            },
          ),
      ],
    ),
  );
}

class ParentalControlsScreen extends StatefulWidget {
  const ParentalControlsScreen({
    super.key,
    required this.supabase,
    required this.profile,
  });
  final SupabaseClient supabase;
  final MemberProfile profile;

  @override
  State<ParentalControlsScreen> createState() => _ParentalControlsScreenState();
}

class _ParentalControlsScreenState extends State<ParentalControlsScreen> {
  bool _saving = false;

  Future<void> _setPin() async {
    final pin = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Set PIN for ${widget.profile.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pin,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: '4-digit PIN'),
              ),
              TextField(
                controller: confirm,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Confirm PIN',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!RegExp(r'^\d{4}$').hasMatch(pin.text)) {
                  setDialogState(() => error = 'Enter exactly four digits.');
                } else if (pin.text != confirm.text) {
                  setDialogState(() => error = 'PINs do not match.');
                } else {
                  Navigator.pop(dialogContext, pin.text);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    pin.dispose();
    confirm.dispose();
    if (value == null) return;
    await _savePin(value, 'Profile PIN updated.');
  }

  Future<void> _clearPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove profile PIN?'),
        content: const Text(
          'This profile will no longer require its current PIN.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _savePin(null, 'Profile PIN removed.');
  }

  Future<void> _savePin(String? pin, String success) async {
    setState(() => _saving = true);
    try {
      await AccountService(
        widget.supabase,
      ).setProfilePin(widget.profile.id, pin);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('PIN could not be updated.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsShell(
    title: 'Parental controls',
    subtitle: 'Viewing protection for ${widget.profile.name}',
    child: Column(
      children: [
        _InfoCard(
          icon: widget.profile.isKids
              ? Icons.child_care_rounded
              : Icons.person_outline_rounded,
          label: 'Profile type',
          value: widget.profile.isKids ? 'Kids profile' : 'Standard profile',
          caption: widget.profile.isKids
              ? 'Child-appropriate browsing is enabled.'
              : 'Uses the account’s normal content access.',
        ),
        const SizedBox(height: 14),
        _ActionCard(
          icon: Icons.pin_outlined,
          title: 'Profile PIN',
          subtitle: 'Use four digits to protect this profile.',
          action: 'Set PIN',
          onTap: _saving ? null : _setPin,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _saving ? null : _clearPin,
          icon: const Icon(Icons.lock_open_rounded),
          label: const Text('Remove existing PIN'),
        ),
      ],
    ),
  );
}

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key, this.supabase, this.pickAttachment});

  final SupabaseClient? supabase;
  final SupportAttachmentPicker? pickAttachment;

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  static const _articles = <({String title, String body})>[
    (
      title: 'How to manage profiles',
      body:
          'Open Settings → Profiles to switch, add, or manage the profiles included with your plan.',
    ),
    (
      title: 'How to change your password',
      body:
          'Open Account details, choose Change beside Password, then enter and confirm your new password.',
    ),
    (
      title: 'How subscription access works',
      body:
          'Your plan stays active until its displayed expiration date. Profile limits follow your active plan.',
    ),
    (
      title: 'How to change playback settings',
      body:
          'Open Playback & privacy for playback preferences, or Watch history to review and remove viewing activity.',
    ),
    (
      title: 'How to protect a profile',
      body:
          'Open Parental controls and assign a four-digit PIN to the active profile.',
    ),
    (
      title: 'Why a Google password is not shown',
      body:
          'Passwords are stored as secure hashes inside Supabase Auth and never in the public user table.',
    ),
  ];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase().trim();
    final articles = _articles
        .where(
          (article) =>
              query.isEmpty ||
              article.title.toLowerCase().contains(query) ||
              article.body.toLowerCase().contains(query),
        )
        .toList();
    return _SettingsShell(
      title: 'Help center',
      subtitle: 'Find answers and contact StreamFlix support',
      child: Column(
        children: [
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              hintText: 'Search help articles',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 18),
          if (articles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'No articles match your search.',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            _SettingsGroup(
              title: 'POPULAR HELP',
              children: [
                for (final article in articles)
                  ListTile(
                    title: Text(article.title),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      backgroundColor: AppColors.inkSoft,
                      builder: (context) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                article.title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                article.body,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openContactForm(context),
              icon: const Icon(Icons.support_agent_rounded),
              label: const Text('Contact support'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openContactForm(BuildContext context) async {
    final subject = TextEditingController();
    final description = TextEditingController();
    SupportAttachment? attachment;
    String? attachmentError;
    final submitted =
        await showModalBottomSheet<
          ({String subject, String description, SupportAttachment? attachment})
        >(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: AppColors.inkSoft,
          builder: (sheetContext) => StatefulBuilder(
            builder: (sheetContext, setSheetState) => Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                4,
                24,
                MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Contact support',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: subject,
                      maxLength: 50,
                      decoration: const InputDecoration(labelText: 'Subject'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      maxLines: 4,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        labelText: 'Describe the issue',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final picked =
                              await (widget.pickAttachment ??
                                  _pickFeedbackAttachment)();
                          if (picked == null || !sheetContext.mounted) return;
                          validateSupportAttachment(picked);
                          setSheetState(() {
                            attachment = picked;
                            attachmentError = null;
                          });
                        } on SupportAttachmentValidationException catch (
                          error
                        ) {
                          if (!sheetContext.mounted) return;
                          setSheetState(() {
                            attachment = null;
                            attachmentError = error.message;
                          });
                        } catch (_) {
                          if (!sheetContext.mounted) return;
                          setSheetState(() {
                            attachment = null;
                            attachmentError = 'Could not open that image.';
                          });
                        }
                      },
                      icon: const Icon(Icons.attach_file_rounded),
                      label: Text(
                        attachment == null
                            ? 'Attach image (optional)'
                            : 'Replace image',
                      ),
                    ),
                    if (attachment != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.image_outlined),
                        title: Text(
                          attachment!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${(attachment!.bytes.lengthInBytes / 1024 / 1024).toStringAsFixed(2)} MB',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove attachment',
                          onPressed: () =>
                              setSheetState(() => attachment = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'PNG, JPG, WebP, or GIF · 5 MB maximum',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (attachmentError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          attachmentError!,
                          style: TextStyle(
                            color: Theme.of(sheetContext).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () {
                        if (subject.text.trim().isEmpty ||
                            description.text.trim().isEmpty) {
                          return;
                        }
                        Navigator.pop(sheetContext, (
                          subject: subject.text.trim(),
                          description: description.text.trim(),
                          attachment: attachment,
                        ));
                      },
                      child: const Text('Submit request'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    subject.dispose();
    description.dispose();
    if (submitted != null && mounted) {
      try {
        final client = widget.supabase;
        if (client == null) throw StateError('Supabase is not configured.');
        await AccountService(client).submitSupportRequest(
          subject: submitted.subject,
          description: submitted.description,
          attachment: submitted.attachment,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('Support request submitted.')),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(
            content: const Text('Support request could not be submitted.'),
            backgroundColor: Theme.of(this.context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<SupportAttachment?> _pickFeedbackAttachment() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (image == null) return null;
    final mimeType = image.mimeType ?? _imageMimeTypeFromName(image.name);
    validateSupportAttachmentMetadata(
      mimeType: mimeType,
      sizeInBytes: await image.length(),
    );
    return SupportAttachment(
      name: image.name,
      mimeType: mimeType,
      bytes: await image.readAsBytes(),
    );
  }

  String _imageMimeTypeFromName(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.webp')) return 'image/webp';
    if (lowerName.endsWith('.gif')) return 'image/gif';
    return '';
  }
}

class AboutStreamFlixScreen extends StatelessWidget {
  const AboutStreamFlixScreen({super.key});

  @override
  Widget build(BuildContext context) => _SettingsShell(
    title: 'About StreamFlix',
    subtitle: 'App information and acknowledgements',
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.violetDeep, AppColors.card],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Column(
            children: [
              BrandLogo(),
              SizedBox(height: 12),
              Text(
                'Version 1.0.0 (1)',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const _InfoCard(
          icon: Icons.movie_filter_outlined,
          label: 'Catalog data',
          value: 'TMDB',
          caption:
              'This product uses the TMDB API but is not endorsed or certified by TMDB.',
        ),
        const SizedBox(height: 12),
        const _InfoCard(
          icon: Icons.shield_outlined,
          label: 'Authentication and data',
          value: 'Supabase',
          caption:
              'Secure authentication, subscriptions, profiles, and storage.',
        ),
        const SizedBox(height: 20),
        const Text(
          'StreamFlix is a prototype streaming experience. Availability and playback sources depend on configured services.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
        ),
      ],
    ),
  );
}

class _SettingsShell extends StatelessWidget {
  const _SettingsShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const BrandLogo(compact: true), centerTitle: true),
    body: Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-.75, -1),
          radius: 1.35,
          colors: [Color(0xFF32165B), AppColors.ink],
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 40),
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 26),
            child,
          ],
        ),
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          title,
          style: const TextStyle(
            color: AppColors.violetLight,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.card.withValues(alpha: .78),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: .07)),
        ),
        child: Column(children: children),
      ),
    ],
  );
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    value: value,
    onChanged: onChanged,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(
      subtitle,
      style: const TextStyle(color: AppColors.muted, fontSize: 12),
    ),
  );
}

class _ChoiceSetting extends StatelessWidget {
  const _ChoiceSetting({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    trailing: DropdownButton<String>(
      value: value,
      underline: const SizedBox.shrink(),
      dropdownColor: AppColors.inkSoft,
      items: [
        for (final option in options)
          DropdownMenuItem(value: option, child: Text(option)),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });
  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.card.withValues(alpha: .78),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withValues(alpha: .07)),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.violet.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: AppColors.violetLight),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.card.withValues(alpha: .78),
    borderRadius: BorderRadius.circular(18),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      leading: Icon(icon, color: AppColors.violetLight),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      trailing: Text(
        action,
        style: const TextStyle(
          color: AppColors.gold,
          fontWeight: FontWeight.w800,
        ),
      ),
      onTap: onTap,
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: (active ? Colors.greenAccent : Colors.redAccent).withValues(
        alpha: .14,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      active ? 'ACTIVE' : 'INACTIVE',
      style: TextStyle(
        color: active ? Colors.greenAccent : Colors.redAccent,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ],
    ),
  );
}
