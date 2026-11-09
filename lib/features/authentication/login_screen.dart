import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../core/widgets/motion.dart';
import 'auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _busy = false, _obscure = true;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(_email.text, _password.text);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error is AuthException && error.code == 'invalid_credentials'
              ? 'The email or password isn’t correct. Please try again.'
              : 'Unable to sign in. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/brand/topolina-logo.png',
                          width: 132,
                          height: 144,
                          fit: BoxFit.contain,
                          semanticLabel:
                              'Topolina — Every flavour tells a story',
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      'TOPOLINA',
                      style: TextStyle(
                        fontSize: 14,
                        letterSpacing: 4,
                        fontWeight: FontWeight.w700,
                        color: TopolinaTheme.forest,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'A little clarity.\nEvery day.',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: TopolinaTheme.forest,
                        fontWeight: FontWeight.w600,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Sign in to your cafe workspace.',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                      validator: (value) =>
                          value == null ||
                              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(value.trim())
                          ? 'Enter your email address.'
                          : null,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter your password.'
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    PressMotion(
                      enabled: !_busy,
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: _busy
                              ? const SizedBox(
                                  key: ValueKey('signing-in'),
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Sign in',
                                  key: ValueKey('sign-in-label'),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Need an account or a password reset?\nContact your cafe administrator.',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
