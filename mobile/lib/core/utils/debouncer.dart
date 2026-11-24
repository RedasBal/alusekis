import 'dart:async';

/// Runs only the last of a burst of calls, [delay] after the burst ends.
/// Typing "a", "ab", "abc" quickly results in one action, for "abc".
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Drops a pending call.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
