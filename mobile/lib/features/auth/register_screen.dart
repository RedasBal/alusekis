import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_field_errors.dart';
import '../../core/auth/auth_validators.dart';
import '../../core/router/routes.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
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
          .register(_email.text.trim(), _password.text);
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
    final general = _failure?.general;

    return AppScaffold(
      title: 'Registruotis',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
              newPassword: true,
              helperText: '$minPasswordLength–$maxPasswordLength simbolių',
              validator: validateNewPassword,
              errorText: _failure?.errorFor(AuthField.password),
              onChanged: (_) => setState(() => _failure = null),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            SubmitButton(
              label: 'Registruotis',
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.pushReplacement(Routes.login),
              child: const Text('Jau turite paskyrą? Prisijungti'),
            ),
          ],
        ),
      ),
    );
  }
}
