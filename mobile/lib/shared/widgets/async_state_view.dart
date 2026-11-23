import 'package:material_ui/material_ui.dart';

import '../../core/api/view_state.dart';

/// Renders the four data states. State is never conveyed by color alone:
/// every state has an icon and a text.
class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.state,
    required this.builder,
    this.onRetry,
    this.emptyMessage = 'Nieko nerasta.',
  });

  final ViewState<T> state;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      ViewLoading<T>() => const _Message(
          icon: null,
          text: 'Kraunama…',
          showProgress: true,
        ),
      ViewError<T>(:final message) => _Message(
          icon: Icons.error_outline,
          text: message,
          action: onRetry == null
              ? null
              : FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Bandyti dar kartą'),
                ),
        ),
      ViewEmpty<T>() => _Message(icon: Icons.inbox_outlined, text: emptyMessage),
      ViewSuccess<T>(:final data) => builder(context, data),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.showProgress = false,
    this.action,
  });

  final IconData? icon;
  final String text;
  final bool showProgress;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showProgress)
                const CircularProgressIndicator()
              else if (icon != null)
                Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}
