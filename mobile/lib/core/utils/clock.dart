import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current instant (UTC). A provider so tests can fix the time.
final nowProvider = Provider<DateTime Function()>((ref) => () => DateTime.now().toUtc());
