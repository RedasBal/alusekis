import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_preferences.dart';

enum AgeStatus {
  /// Not answered yet (first launch).
  unknown,

  /// Confirmed 20+; remembered on the device.
  confirmed,

  /// Answered "no" in this session. Not remembered: the user is asked again
  /// next time the app starts.
  declined,
}

class AgeGateController extends Notifier<AgeStatus> {
  @override
  AgeStatus build() => ref.read(appPreferencesProvider).ageConfirmed
      ? AgeStatus.confirmed
      : AgeStatus.unknown;

  Future<void> confirm() async {
    state = AgeStatus.confirmed;
    await ref.read(appPreferencesProvider).setAgeConfirmed(true);
  }

  void decline() => state = AgeStatus.declined;
}

final ageGateProvider =
    NotifierProvider<AgeGateController, AgeStatus>(AgeGateController.new);
