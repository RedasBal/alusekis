import 'package:material_ui/material_ui.dart';

/// Standard screen frame: title bar plus an explicit way back.
///
/// * Screens pushed on top of another one get the automatic back arrow.
/// * Top-level tab screens pass [onBack] (e.g. return to the first tab); it is
///   shown as a back arrow and also handles the system back gesture.
/// * With neither, the screen is the app root and system back closes the app.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onBack,
  });

  final String title;
  final Widget body;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final onBack = this.onBack;
    return PopScope(
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          onBack?.call();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: onBack == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: onBack,
                ),
          title: Text(title),
        ),
        body: body,
      ),
    );
  }
}
