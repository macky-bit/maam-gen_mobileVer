import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/member_profile.dart';
import '../services/member_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class ActiveProfileEditorScreen extends StatefulWidget {
  const ActiveProfileEditorScreen({
    super.key,
    required this.supabase,
    required this.profile,
    required this.onSaved,
    this.loadCatalog,
  });

  final SupabaseClient supabase;
  final MemberProfile profile;
  final ValueChanged<MemberProfile> onSaved;
  final Future<MemberProfileCatalog> Function()? loadCatalog;

  @override
  State<ActiveProfileEditorScreen> createState() =>
      _ActiveProfileEditorScreenState();
}

class _ActiveProfileEditorScreenState extends State<ActiveProfileEditorScreen> {
  late final TextEditingController _name;
  final _pin = TextEditingController();
  MemberProfileCatalog? _catalog;
  String? _avatarPath;
  String? _error;
  bool _removePin = false;
  bool _loading = true;
  bool _saving = false;

  MemberProfileService get _service => MemberProfileService(widget.supabase);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
    _avatarPath = widget.profile.avatarPath;
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final catalog =
          await (widget.loadCatalog?.call() ?? _service.loadCatalog());
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        if (_avatarPath == null || _avatarPath!.isEmpty) {
          _avatarPath = catalog.avatars.firstOrNull?.path;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Profile avatars could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final pin = _pin.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a profile name.');
      return;
    }
    if (_avatarPath == null) {
      setState(() => _error = 'Choose an avatar.');
      return;
    }
    if (pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = 'A new PIN must contain exactly four digits.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.updateProfile(
        profileId: widget.profile.id,
        name: name,
        avatarPath: _avatarPath!,
        newPin: pin.isEmpty ? null : pin,
        removePin: _removePin,
      );
      final refreshed = await _service.loadCatalog();
      final updated = refreshed.profiles.firstWhere(
        (profile) => profile.id == widget.profile.id,
      );
      widget.onSaved(updated);
      if (mounted) Navigator.pop(context, updated);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'The profile could not be saved. The name may already be used.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const BrandLogo(compact: true), centerTitle: true),
    body: Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-.7, -1),
          radius: 1.35,
          colors: [Color(0xFF32165B), AppColors.ink],
        ),
      ),
      child: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                children: [
                  Text(
                    'Edit active profile',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Change how this profile appears and protect it with a PIN.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 30),
                  Center(child: _SelectedAvatar(profile: _selectedPreview)),
                  const SizedBox(height: 32),
                  const _EditorSectionLabel('PROFILE IDENTITY'),
                  const Divider(height: 1),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    maxLength: 50,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Profile name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Choose an avatar',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  if (_catalog?.avatars.isEmpty ?? true)
                    const Text(
                      'No avatars are available in the avatar bucket.',
                      style: TextStyle(color: AppColors.muted),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _catalog!.avatars.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                      itemBuilder: (context, index) {
                        final avatar = _catalog!.avatars[index];
                        final selected = avatar.path == _avatarPath;
                        return Semantics(
                          button: true,
                          selected: selected,
                          label: 'Avatar ${index + 1}',
                          child: InkWell(
                            onTap: () =>
                                setState(() => _avatarPath = avatar.path),
                            borderRadius: BorderRadius.circular(18),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.gold
                                      : Colors.transparent,
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
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 32),
                  const _EditorSectionLabel('PROFILE LOCK'),
                  const Divider(height: 1),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _pin,
                    enabled: !_removePin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'New PIN (optional)',
                      helperText: 'Leave blank to keep the current PIN.',
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  SwitchListTile.adaptive(
                    value: _removePin,
                    onChanged: (value) => setState(() {
                      _removePin = value;
                      if (value) _pin.clear();
                    }),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Remove profile PIN'),
                    subtitle: const Text(
                      'Anyone will be able to open this profile.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _ReadOnlyProfileType(profile: widget.profile),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save profile'),
                  ),
                ],
              ),
      ),
    ),
  );

  MemberProfile get _selectedPreview {
    final avatar = _catalog?.avatars
        .where((item) => item.path == _avatarPath)
        .firstOrNull;
    return MemberProfile(
      id: widget.profile.id,
      name: _name.text.trim().isEmpty ? widget.profile.name : _name.text.trim(),
      avatarPath: _avatarPath ?? widget.profile.avatarPath,
      avatarUrl: avatar?.signedUrl ?? widget.profile.avatarUrl,
      isKids: widget.profile.isKids,
      displayOrder: widget.profile.displayOrder,
    );
  }
}

class _SelectedAvatar extends StatelessWidget {
  const _SelectedAvatar({required this.profile});
  final MemberProfile profile;

  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 54,
    backgroundColor: AppColors.card,
    backgroundImage: profile.avatarUrl.isEmpty
        ? null
        : NetworkImage(profile.avatarUrl),
    child: profile.avatarUrl.isEmpty
        ? Text(
            profile.name.characters.first.toUpperCase(),
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 38,
              fontWeight: FontWeight.w900,
            ),
          )
        : null,
  );
}

class _EditorSectionLabel extends StatelessWidget {
  const _EditorSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.violetLight,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.1,
      ),
    ),
  );
}

class _ReadOnlyProfileType extends StatelessWidget {
  const _ReadOnlyProfileType({required this.profile});
  final MemberProfile profile;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.shield_outlined, color: AppColors.muted),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Profile type',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              profile.isKids ? 'Kids profile' : 'Standard profile',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
      const Text(
        'Managed',
        style: TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    ],
  );
}
