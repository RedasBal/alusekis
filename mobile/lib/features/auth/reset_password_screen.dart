import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_field_errors.dart';
import '../../core/auth/auth_validators.dart';
import '../../core/router/routes.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'auth_widgets.dart';

/// Second step of password recovery: the code (or the whole link) from the
/// e-mail plus the new password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  static const _fields = {AuthField.token, AuthField.password};

  final _formKey = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  FormFailure? _failure;

  @override
  void dispose() {
    _token.dispose();
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
          .resetPassword(extractResetToken(_token.text), _password.text);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Slaptažodis pakeistas. Prisijunkite su nauju slaptažodžiu.'),
        ),
      );
      context.go(Routes.login);
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
      title: 'Naujas slaptažodis',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (general != null) ...[
              ErrorBanner(general),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _token,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'Įveskite atkūrimo kodą.'
                  : null,
              onChanged: (_) => setState(() => _failure = null),
              decoration: InputDecoration(
                labelText: 'Atkūrimo kodas arba nuoroda',
                border: const OutlineInputBorder(),
                errorText: _failure?.errorFor(AuthField.token),
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _password,
              label: 'Naujas slaptažodis',
              newPassword: true,
              helperText: '$minPasswordLength–$maxPasswordLength simbolių',
              validator: validateNewPassword,
              errorText: _failure?.errorFor(AuthField.password),
              onChanged: (_) => setState(() => _failure = null),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            SubmitButton(
              label: 'Pakeisti slaptažodį',
              loading: _loading,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
