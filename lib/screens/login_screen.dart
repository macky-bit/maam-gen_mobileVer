import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onEmailSignIn,
    required this.onRegister,
    required this.onGoogleSignIn,
  });

  final Future<void> Function(String email, String password) onEmailSignIn;
  final Future<bool> Function(
    String email,
    String password,
    Map<String, dynamic> metadata,
  )
  onRegister;
  final Future<void> Function() onGoogleSignIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _dateOfBirth = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _obscure = true;
  bool _registering = false;
  bool _agreed = false;
  bool _isGoogleSigningIn = false;
  bool _isSubmitting = false;
  String? _googleError;
  String? _authMessage;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _dateOfBirth.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _registering = !_registering;
      _errors = const {};
      _authMessage = null;
    });
  }

  Future<void> _submit() async {
    final errors = <String, String>{};
    if (_registering) {
      if (_firstName.text.trim().isEmpty) errors['firstName'] = 'Required.';
      if (_lastName.text.trim().isEmpty) errors['lastName'] = 'Required.';
      if (_dateOfBirth.text.isEmpty) errors['dob'] = 'Required.';
      if (_username.text.trim().isEmpty) errors['username'] = 'Required.';
    }
    if (_email.text.trim().isEmpty) {
      errors['email'] = 'Required.';
    } else if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim())) {
      errors['email'] = 'Enter a valid email.';
    }
    if (_password.text.isEmpty) {
      errors['password'] = 'Required.';
    } else if (_password.text.length < 8) {
      errors['password'] = 'At least 8 characters.';
    }
    if (_registering && !_agreed) {
      errors['terms'] = 'You must agree to continue.';
    }

    setState(() {
      _errors = errors;
      _authMessage = null;
    });
    if (errors.isNotEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      if (_registering) {
        final signedIn = await widget.onRegister(_email.text, _password.text, {
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'username': _username.text.trim(),
          'date_of_birth': _dateOfBirth.text,
        });
        if (mounted && !signedIn) {
          setState(() {
            _authMessage =
                'Account created. Check your email to confirm your account, then sign in.';
          });
        }
      } else {
        await widget.onEmailSignIn(_email.text, _password.text);
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _authMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _authMessage = 'Authentication failed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_isGoogleSigningIn) return;
    setState(() {
      _isGoogleSigningIn = true;
      _googleError = null;
    });

    try {
      await widget.onGoogleSignIn();
    } catch (_) {
      if (mounted) {
        setState(() {
          _googleError = 'Google sign-in could not be started. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _isGoogleSigningIn = false);
    }
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Select date of birth',
    );
    if (selected == null) return;
    _dateOfBirth.text =
        '${selected.month.toString().padLeft(2, '0')}/'
        '${selected.day.toString().padLeft(2, '0')}/'
        '${selected.year}';
    setState(() => _errors = {..._errors}..remove('dob'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.75, -1),
            radius: 1.45,
            colors: [Color(0xFF4C1D95), AppColors.ink],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight > 60
                      ? constraints.maxHeight - 60
                      : 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: BrandLogo(),
                    ),
                    SizedBox(height: _registering ? 34 : 62),
                    Text(
                      _registering ? 'Account' : 'Welcome back.',
                      style: Theme.of(
                        context,
                      ).textTheme.displayLarge?.copyWith(fontSize: 42),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _registering
                          ? 'Join STREAMFLIX and enjoy unlimited entertainment.'
                          : 'The stories you love, ready whenever you are.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: _registering ? 26 : 38),
                    if (_registering)
                      ..._registrationFields()
                    else
                      ..._loginFields(),
                    SizedBox(height: _registering ? 22 : 52),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _registering
                                ? 'Already have an account?'
                                : 'New to StreamFlix?',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _toggleMode,
                          style: TextButton.styleFrom(
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child: Text(_registering ? 'Sign in' : 'Register'),
                        ),
                      ],
                    ),
                    if (!_registering)
                      const Text(
                        'By continuing, you agree to the Terms of Use and Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF756E80),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _loginFields() => [
    TextField(
      key: const ValueKey('email-input'),
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      decoration: InputDecoration(
        labelText: 'Email address',
        prefixIcon: const Icon(Icons.mail_outline_rounded),
        errorText: _errors['email'],
      ),
    ),
    const SizedBox(height: 14),
    _passwordField(label: 'Password', error: _errors['password']),
    Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () {},
        child: const Text('Forgot password?'),
      ),
    ),
    if (_authMessage != null) ...[
      Text(
        _authMessage!,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      const SizedBox(height: 12),
    ],
    FilledButton(
      key: const ValueKey('email-sign-in'),
      onPressed: _isSubmitting ? null : _submit,
      child: _isSubmitting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Sign in'),
    ),
    const SizedBox(height: 20),
    const Row(
      children: [
        Expanded(child: Divider(color: Color(0x447C3AED))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'OR',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0x447C3AED))),
      ],
    ),
    const SizedBox(height: 20),
    OutlinedButton.icon(
      key: const ValueKey('google-sign-in'),
      onPressed: _isGoogleSigningIn ? null : _signInWithGoogle,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        foregroundColor: Colors.white,
        backgroundColor: AppColors.violetDeep,
        side: const BorderSide(color: AppColors.violetLight),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: _isGoogleSigningIn
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.gold,
              ),
            )
          : const _GoogleMark(),
      label: Text(
        _isGoogleSigningIn ? 'Opening Google…' : 'Continue with Google',
      ),
    ),
    if (_googleError != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          _googleError!,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      ),
  ];

  List<Widget> _registrationFields() => [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _firstName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'First Name',
              hintText: 'First name',
              errorText: _errors['firstName'],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _lastName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Last Name',
              hintText: 'Last name',
              errorText: _errors['lastName'],
            ),
          ),
        ),
      ],
    ),
    const SizedBox(height: 14),
    TextField(
      controller: _dateOfBirth,
      readOnly: true,
      onTap: _pickDate,
      decoration: InputDecoration(
        labelText: 'Date of Birth',
        hintText: 'MM/DD/YYYY',
        errorText: _errors['dob'],
        prefixIcon: const Icon(Icons.calendar_today_outlined),
      ),
    ),
    const SizedBox(height: 14),
    TextField(
      controller: _username,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Username',
        hintText: 'Choose a username',
        errorText: _errors['username'],
        prefixIcon: const Icon(Icons.person_outline_rounded),
      ),
    ),
    const SizedBox(height: 14),
    TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.newUsername],
      decoration: InputDecoration(
        labelText: 'Email Address',
        hintText: 'Enter your email',
        errorText: _errors['email'],
        prefixIcon: const Icon(Icons.mail_outline_rounded),
      ),
    ),
    const SizedBox(height: 14),
    _passwordField(
      label: 'Password',
      hint: 'Create a strong password',
      error: _errors['password'],
    ),
    const SizedBox(height: 10),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _agreed,
          activeColor: AppColors.violet,
          visualDensity: VisualDensity.compact,
          onChanged: (value) => setState(() {
            _agreed = value ?? false;
            _errors = {..._errors}..remove('terms');
          }),
        ),
        const SizedBox(width: 2),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 7),
            child: Text(
              'I agree to the Terms of Service and Privacy Policy.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
        ),
      ],
    ),
    if (_errors['terms'] != null)
      Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 8),
        child: Text(
          _errors['terms']!,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 11,
          ),
        ),
      ),
    if (_authMessage != null) ...[
      const SizedBox(height: 6),
      Text(
        _authMessage!,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      const SizedBox(height: 10),
    ] else
      const SizedBox(height: 6),
    FilledButton(
      onPressed: _isSubmitting ? null : _submit,
      child: _isSubmitting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Create Account'),
    ),
  ];

  Widget _passwordField({required String label, String? hint, String? error}) {
    return TextField(
      key: const ValueKey('password-input'),
      controller: _password,
      obscureText: _obscure,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppColors.gold,
      shape: BoxShape.circle,
    ),
    child: const Text(
      'G',
      style: TextStyle(
        color: AppColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}
