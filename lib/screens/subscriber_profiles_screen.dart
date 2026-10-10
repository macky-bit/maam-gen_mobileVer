import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_profile.dart';
import '../services/member_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class SubscriberProfilesScreen extends StatefulWidget {
  const SubscriberProfilesScreen({
    super.key,
    required this.supabase,
    required this.onBack,
    required this.onContinue,
  });

  final SupabaseClient supabase;
  final VoidCallback onBack;
  final ValueChanged<MemberProfile> onContinue;

  @override
  State<SubscriberProfilesScreen> createState() =>
      _SubscriberProfilesScreenState();
}

class _SubscriberProfilesScreenState extends State<SubscriberProfilesScreen> {
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  MemberProfileCatalog? _catalog;
  int? _selectedProfileId;
  String? _selectedAvatarPath;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isCreating = false;
  bool _isKids = false;

  MemberProfileService get _service => MemberProfileService(widget.supabase);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final catalog = await _service.loadCatalog();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _selectedProfileId = catalog.profiles.isEmpty
            ? null
            : catalog.profiles
                  .where((profile) => profile.isEntitled)
                  .firstOrNull
                  ?.id;
        _selectedAvatarPath = catalog.avatars.isEmpty
            ? null
            : catalog.avatars.first.path;
        _isCreating = catalog.profiles.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Profiles could not be loaded. Try again.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startAdding() {
    _nameController.clear();
    _pinController.clear();
    setState(() {
      _isCreating = true;
      _isKids = false;
      _errorMessage = null;
      _selectedAvatarPath = _catalog?.avatars.firstOrNull?.path;
    });
  }

  Future<void> _createProfile() async {
    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Enter a profile name.');
      return;
    }
    if (_selectedAvatarPath == null) {
      setState(() => _errorMessage = 'Choose an avatar.');
      return;
    }
    if (pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _errorMessage = 'The optional PIN must be four digits.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await _service.createProfile(
        name: name,
        avatarPath: _selectedAvatarPath!,
        isKids: _isKids,
        pin: pin,
      );
      if (!mounted) return;
      _nameController.clear();
      _pinController.clear();
      await _load();
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage =
            'The profile could not be created. Check your plan limit and try again.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _continueWith(MemberProfile profile) async {
    if (!profile.isEntitled) return;
    if (!profile.hasPin) {
      widget.onContinue(profile);
      return;
    }

    final controller = TextEditingController();
    var isVerifying = false;
    String? errorMessage;
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Enter profile PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter the four-digit PIN for ${profile.name}.'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setDialogState(() => errorMessage = null),
                onSubmitted: (_) {},
                decoration: InputDecoration(
                  labelText: 'Profile PIN',
                  errorText: errorMessage,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isVerifying
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isVerifying || controller.text.length != 4
                  ? null
                  : () async {
                      setDialogState(() {
                        isVerifying = true;
                        errorMessage = null;
                      });
                      try {
                        final result = await _service.verifyPin(
                          profileId: profile.id,
                          pin: controller.text,
                        );
                        if (!dialogContext.mounted) return;
                        if (result.isVerified) {
                          Navigator.pop(dialogContext, true);
                          return;
                        }
                        final retry = result.retryAfterSeconds;
                        setDialogState(() {
                          isVerifying = false;
                          errorMessage = retry > 0
                              ? 'Too many attempts. Try again in '
                                    '${(retry / 60).ceil()} minute(s).'
                              : 'Incorrect PIN.';
                          controller.clear();
                        });
                      } catch (_) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() {
                          isVerifying = false;
                          errorMessage = 'The PIN could not be verified.';
                          controller.clear();
                        });
                      }
                    },
              child: isVerifying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unlock profile'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (verified == true && mounted) widget.onContinue(profile);
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
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.85),
            radius: 1.1,
            colors: [Color(0xFF32165B), AppColors.ink],
          ),
        ),
        child: SafeArea(
          top: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null && _catalog == null
              ? _LoadError(message: _errorMessage!, onRetry: _load)
              : _isCreating
              ? _buildCreator(context)
              : _buildPicker(context),
        ),
      ),
    );
  }

  Widget _buildPicker(BuildContext context) {
    final catalog = _catalog!;
    final selected = catalog.profiles
        .where((profile) => profile.id == _selectedProfileId)
        .firstOrNull;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            children: [
              Text(
                "Who's watching?",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 9),
              Text(
                '${catalog.context.planName} plan · '
                '${catalog.profiles.length}/${catalog.context.maxProfiles} profiles',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 36),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 18,
                runSpacing: 24,
                children: [
                  for (final profile in catalog.profiles)
                    _ProfileCard(
                      profile: profile,
                      selected: profile.id == _selectedProfileId,
                      onTap: profile.isEntitled
                          ? () =>
                                setState(() => _selectedProfileId = profile.id)
                          : null,
                    ),
                  if (catalog.context.canAddProfile)
                    _AddProfileCard(onTap: _startAdding),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            14,
            24,
            MediaQuery.paddingOf(context).bottom + 18,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: selected == null
                  ? null
                  : () => _continueWith(selected),
              child: Text(
                selected == null
                    ? 'Choose a profile'
                    : 'Continue as ${selected.name}',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreator(BuildContext context) {
    final catalog = _catalog!;
    final firstProfile = catalog.profiles.isEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
      children: [
        Text(
          firstProfile ? 'Create your profile' : 'Add a profile',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 9),
        Text(
          firstProfile
              ? 'Choose how you will appear on StreamFlix.'
              : '${catalog.profiles.length} of ${catalog.context.maxProfiles} profiles used.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 30),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          maxLength: 50,
          decoration: const InputDecoration(
            labelText: 'Profile name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Choose an avatar',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: catalog.avatars.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final avatar = catalog.avatars[index];
            final selected = avatar.path == _selectedAvatarPath;
            return InkWell(
              onTap: () => setState(() => _selectedAvatarPath = avatar.path),
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? AppColors.gold : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.network(
                    avatar.signedUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.person_rounded,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (catalog.context.allowsKids) ...[
          const SizedBox(height: 18),
          SwitchListTile.adaptive(
            value: _isKids,
            onChanged: (value) => setState(() => _isKids = value),
            contentPadding: EdgeInsets.zero,
            title: const Text('Kids profile'),
            subtitle: const Text(
              'Show child-appropriate content and controls.',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Profile PIN (optional)',
            prefixIcon: Icon(Icons.pin_outlined),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _isSaving ? null : _createProfile,
          child: _isSaving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create profile'),
        ),
        if (!firstProfile)
          TextButton(
            onPressed: _isSaving
                ? null
                : () => setState(() {
                    _isCreating = false;
                    _errorMessage = null;
                  }),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final MemberProfile profile;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: profile.isEntitled,
    label: profile.isEntitled
        ? 'Continue as ${profile.name}${profile.hasPin ? ', PIN required' : ''}'
        : '${profile.name} is unavailable on the current plan',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Opacity(
        opacity: profile.isEntitled ? 1 : .45,
        child: SizedBox(
          width: 104,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                width: 90,
                height: 90,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: selected ? AppColors.gold : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: profile.avatarUrl.isEmpty
                      ? const Icon(Icons.person_rounded, color: AppColors.muted)
                      : Image.network(
                          profile.avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.person_rounded,
                            color: AppColors.muted,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
              if (profile.isKids)
                const Text(
                  'KIDS',
                  style: TextStyle(
                    color: AppColors.violetLight,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              if (!profile.isEntitled)
                const Text(
                  'UNAVAILABLE',
                  style: TextStyle(color: AppColors.muted, fontSize: 8),
                )
              else if (profile.hasPin)
                const Icon(Icons.lock_outline_rounded, size: 13),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AddProfileCard extends StatelessWidget {
  const _AddProfileCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: const SizedBox(
      width: 104,
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.all(Radius.circular(22)),
            ),
            child: SizedBox(
              width: 90,
              height: 90,
              child: Icon(Icons.add_rounded, size: 42, color: AppColors.muted),
            ),
          ),
          SizedBox(height: 9),
          Text('Add Profile', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
