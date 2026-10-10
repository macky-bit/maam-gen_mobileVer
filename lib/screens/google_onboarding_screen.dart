import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class GoogleOnboardingScreen extends StatefulWidget {
  const GoogleOnboardingScreen({
    super.key,
    required this.email,
    required this.onSubmit,
    required this.onSignOut,
  });

  final String email;
  final Future<void> Function(DateTime birthDate, String password) onSubmit;
  final Future<void> Function() onSignOut;

  @override
  State<GoogleOnboardingScreen> createState() => _GoogleOnboardingScreenState();
}

class _GoogleOnboardingScreenState extends State<GoogleOnboardingScreen> {
  final _birthDateController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  DateTime? _birthDate;
  bool _obscurePassword = true;
  bool _isSaving = false;
  String? _birthDateError;
  String? _passwordError;
  String? _errorMessage;

  @override
  void dispose() {
    _birthDateController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your birthdate',
    );
    if (selected == null) return;
    setState(() {
      _birthDate = selected;
      _birthDateController.text =
          '${selected.month.toString().padLeft(2, '0')}/'
          '${selected.day.toString().padLeft(2, '0')}/'
          '${selected.year}';
      _birthDateError = null;
    });
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final password = _passwordController.text;
    setState(() {
      _birthDateError = _birthDate == null ? 'Birthdate is required.' : null;
      _passwordError = password.length < 8
          ? 'Use at least 8 characters.'
          : password != _confirmPasswordController.text
          ? 'Passwords do not match.'
          : null;
      _errorMessage = null;
    });
    if (_birthDateError != null || _passwordError != null) return;

    setState(() => _isSaving = true);
    try {
      await widget.onSubmit(_birthDate!, password);
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Your account details could not be saved. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const BrandLogo(compact: true),
      centerTitle: true,
      actions: [
        TextButton(
          onPressed: _isSaving ? null : widget.onSignOut,
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-.7, -1),
          radius: 1.4,
          colors: [Color(0xFF4C1D95), AppColors.ink],
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 42, 24, 36),
          children: [
            const Icon(
              Icons.verified_user_outlined,
              color: AppColors.gold,
              size: 52,
            ),
            const SizedBox(height: 20),
            Text(
              'Complete your account',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            const Text(
              'Add a birthdate and create a StreamFlix password so you can also sign in using email.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 34),
            TextFormField(
              initialValue: widget.email,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Google email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
                suffixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('google-birthdate'),
              controller: _birthDateController,
              readOnly: true,
              onTap: _pickBirthDate,
              decoration: InputDecoration(
                labelText: 'Birthdate',
                hintText: 'MM/DD/YYYY',
                errorText: _birthDateError,
                prefixIcon: const Icon(Icons.cake_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('google-password'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Create password',
                helperText: 'At least 8 characters',
                errorText: _passwordError,
                prefixIcon: const Icon(Icons.password_rounded),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('google-confirm-password'),
              controller: _confirmPasswordController,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 26),
            FilledButton(
              key: const ValueKey('complete-google-account'),
              onPressed: _isSaving ? null : _submit,
              child: _isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save and continue'),
            ),
            const SizedBox(height: 14),
            const Text(
              'Your password is secured by Supabase Auth and is never stored in the StreamFlix profile database.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}
