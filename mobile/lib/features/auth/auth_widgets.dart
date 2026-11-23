import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_validators.dart';

/// E-mail input with the standard Lithuanian label and validation.
class EmailField extends StatelessWidget {
  const EmailField({
    super.key,
    required this.controller,
    this.errorText,
    this.onChanged,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;

  /// Error from the server, shown next to the field.
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      textInputAction: textInputAction,
      autocorrect: false,
      autofillHints: const [AutofillHints.email],
      validator: validateEmail,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: 'El. paštas',
        border: const OutlineInputBorder(),
        errorText: errorText,
        errorMaxLines: 3,
      ),
    );
  }
}

/// Password input with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.validator,
    this.label = 'Slaptažodis',
    this.helperText,
    this.errorText,
    this.onChanged,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.newPassword = false,
  });

  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final String label;
  final String? helperText;

  /// Error from the server, shown next to the field.
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  /// Hints the password manager to offer a new password.
  final bool newPassword;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      textInputAction: widget.textInputAction,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        errorText: widget.errorText,
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Rodyti slaptažodį' : 'Slėpti slaptažodį',
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// General (not field-specific) error above a form.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Primary form button that shows progress and ignores taps while [loading].
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.loading,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}
