import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/api_error_messages_lt.dart';
import '../../core/api/view_state.dart';
import '../settings/settings_controller.dart';
import 'location_service.dart';
import 'store_models.dart';
import 'store_repository.dart';

enum StoreSearchMode {
  /// All stores of the chosen city.
  city,

  /// Stores within the chosen radius of the user's position.
  location,
}

class StoresState {
  const StoresState({
    this.mode = StoreSearchMode.city,
    this.origin,
    this.result = const ViewLoading<List<StoreItem>>(),
    this.locating = false,
    this.locationProblem,
    this.showMap = true,
  });

  final StoreSearchMode mode;

  /// The user's position for the current search. Held in memory only: never
  /// saved, never kept as history, gone when the app closes.
  final GeoPoint? origin;

  final ViewState<List<StoreItem>> result;
  final bool locating;
  final LocationFailure? locationProblem;
  final bool showMap;

  StoresState copyWith({
    StoreSearchMode? mode,
    GeoPoint? origin,
    bool clearOrigin = false,
    ViewState<List<StoreItem>>? result,
    bool? locating,
    LocationFailure? locationProblem,
    bool clearLocationProblem = false,
    bool? showMap,
  }) =>
      StoresState(
        mode: mode ?? this.mode,
        origin: clearOrigin ? null : origin ?? this.origin,
        result: result ?? this.result,
        locating: locating ?? this.locating,
        locationProblem:
            clearLocationProblem ? null : locationProblem ?? this.locationProblem,
        showMap: showMap ?? this.showMap,
      );
}

/// The "Parduotuvės" screen: which stores are shown and why.
///
/// City and radius live in [settingsProvider] (persisted); the user's
/// position does not.
class StoresController extends Notifier<StoresState> {
  int _ticket = 0;

  @override
  StoresState build() {
    Future<void>.microtask(_load);
    return const StoresState();
  }

  Future<void> selectCity(String name) async {
    await ref.read(settingsProvider.notifier).setCity(name);
    state = state.copyWith(
      mode: StoreSearchMode.city,
      clearOrigin: true,
      clearLocationProblem: true,
    );
    await _load();
  }

  /// Asks for the location permission (only now, because the user tapped) and
  /// searches around the position. On refusal the city search keeps working.
  Future<void> useMyLocation() async {
    if (state.locating) {
      return;
    }
    state = state.copyWith(locating: true, clearLocationProblem: true);

    final result = await ref.read(locationServiceProvider).requestCurrentPosition();
    if (!ref.mounted) {
      return;
    }

    final point = result.point;
    if (point == null) {
      state = state.copyWith(locating: false, locationProblem: result.failure);
      return;
    }

    state = state.copyWith(
      locating: false,
      mode: StoreSearchMode.location,
      origin: point,
    );
    await _load();
  }

  /// Repeats the current search (retry, or after the radius changed).
  Future<void> reload() => _load();

  void setShowMap(bool value) => state = state.copyWith(showMap: value);

  Future<void> openAppSettings() => ref.read(locationServiceProvider).openAppSettings();

  Future<void> _load() async {
    final ticket = ++_ticket;
    state = state.copyWith(result: const ViewLoading<List<StoreItem>>());

    ViewState<List<StoreItem>> result;
    try {
      final repository = ref.read(storeRepositoryProvider);
      final origin = state.origin;
      final List<StoreItem> items;

      if (state.mode == StoreSearchMode.location && origin != null) {
        items = await repository.nearby(origin, ref.read(settingsProvider).radiusKm);
      } else {
        final cities = await _cities();
        final name = ref.read(settingsProvider).city;
        final city = cities.where((c) => c.name == name).firstOrNull;
        items = city == null ? const [] : await repository.byCity(city.id);
      }

      result = items.isEmpty
          ? const ViewEmpty<List<StoreItem>>()
          : ViewSuccess<List<StoreItem>>(items);
    } on ApiException catch (e) {
      result = ViewError<List<StoreItem>>(e.userMessage);
    } catch (_) {
      result = const ViewError<List<StoreItem>>(messageForUnknown);
    }

    // A newer search started meanwhile: this answer is stale.
    if (ref.mounted && ticket == _ticket) {
      state = state.copyWith(result: result);
    }
  }

  Future<List<City>> _cities() async {
    try {
      return await ref.read(citiesProvider.future);
    } catch (_) {
      ref.invalidate(citiesProvider); // so a retry asks the server again
      rethrow;
    }
  }
}

final storesControllerProvider =
    NotifierProvider<StoresController, StoresState>(StoresController.new);
