import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_field_errors.dart';
import '../../core/auth/auth_validators.dart';
import 'auth_widgets.dart';

/// Asks for confirmation and the password, then deletes the account.
/// Resolves to true when the account was deleted.
Future<bool> showDeleteAccountDialog(BuildContext context) async {
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const DeleteAccountDialog(),
  );
  return deleted ?? false;
}

class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  static const _fields = {AuthField.password};

  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _loading = false;
  FormFailure? _failure;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
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
          .deleteAccount(_password.text);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      // The session ended meanwhile (401): the router already opens the login screen.
      if (!ref.read(authControllerProvider).isSignedIn) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _loading = false;
        _failure = FormFailure.from(error, _fields);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final general = _failure?.general;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Ištrinti paskyrą?'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paskyra bus ištrinta negrįžtamai: būsite atjungti, o jūsų '
                'el. paštas ir slaptažodis pašalinti. Anksčiau pateiktos kainos '
                'ir pranešimai liks viešai, bet nebebus susieti su jumis. '
                'Šio veiksmo atšaukti negalima.',
              ),
              const SizedBox(height: 16),
              if (general != null) ...[
                ErrorBanner(general),
                const SizedBox(height: 16),
              ],
              PasswordField(
                controller: _password,
                label: 'Slaptažodis patvirtinimui',
                validator: validateRequiredPassword,
                errorText: _failure?.errorFor(AuthField.password),
                onChanged: (_) => setState(() => _failure = null),
                onSubmitted: (_) => _delete(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Atšaukti'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _loading ? null : _delete,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Ištrinti paskyrą'),
        ),
      ],
    );
  }
}
