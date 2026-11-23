import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_field_errors.dart';
import '../../core/auth/auth_validators.dart';
import '../../core/router/routes.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'auth_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _fields = {AuthField.email, AuthField.password};

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  FormFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_email.text.trim(), _password.text);
      if (!mounted) {
        return;
      }
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.account);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failure = FormFailure.from(error, _fields);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired =
        ref.watch(authControllerProvider.select((s) => s.sessionExpired));
    final general = _failure?.general;

    return AppScaffold(
      title: 'Prisijungti',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (expired) ...[
              const ErrorBanner('Sesija baigėsi. Prisijunkite iš naujo.'),
              const SizedBox(height: 16),
            ],
            if (general != null) ...[
              ErrorBanner(general),
              const SizedBox(height: 16),
            ],
            EmailField(
              controller: _email,
              errorText: _failure?.errorFor(AuthField.email),
              onChanged: (_) => setState(() => _failure = null),
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              validator: validateRequiredPassword,
              errorText: _failure?.errorFor(AuthField.password),
              onChanged: (_) => setState(() => _failure = null),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            SubmitButton(
              label: 'Prisijungti',
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.push(Routes.forgotPassword),
              child: const Text('Pamiršau slaptažodį'),
            ),
            TextButton(
              onPressed: () => context.pushReplacement(Routes.register),
              child: const Text('Neturite paskyros? Registruotis'),
            ),
          ],
        ),
      ),
    );
  }
}
