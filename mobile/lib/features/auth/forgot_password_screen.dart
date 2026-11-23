import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_field_errors.dart';
import '../../core/router/routes.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'auth_widgets.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static const _fields = {AuthField.email};

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  FormFailure? _failure;

  @override
  void dispose() {
    _email.dispose();
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
          .forgotPassword(_email.text.trim());
      if (mounted) {
        setState(() {
          _loading = false;
          _sent = true;
        });
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
      title: 'Atkurti slaptažodį',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Įveskite el. paštą, kuriuo registravotės. Jei paskyra egzistuoja, '
              'atsiųsime slaptažodžio atkūrimo nuorodą. Ji galioja 30 minučių ir '
              'gali būti panaudota tik vieną kartą.',
            ),
            const SizedBox(height: 16),
            if (general != null) ...[
              ErrorBanner(general),
              const SizedBox(height: 16),
            ],
            EmailField(
              controller: _email,
              errorText: _failure?.errorFor(AuthField.email),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _failure = null),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            SubmitButton(
              label: 'Siųsti nuorodą',
              loading: _loading,
              onPressed: _submit,
            ),
            if (_sent) ...[
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: const Text(
                  'Jei šis el. paštas užregistruotas, nuoroda išsiųsta. '
                  'Patikrinkite pašto dėžutę.',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.push(Routes.resetPassword),
                child: const Text('Turiu atkūrimo kodą'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
