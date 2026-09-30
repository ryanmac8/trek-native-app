import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'widget_trip.dart';

/// Hands the "Next trip" widget its data and asks the OS to redraw it.
abstract class HomeWidgetPublisher {
  /// Publishes [candidates] (see [nextTripCandidates]) — an empty list
  /// means "signed in, no upcoming trips".
  Future<void> publishNextTrip(List<WidgetTrip> candidates);

  /// Removes the published data, so the widget shows its signed-out state.
  Future<void> clear();
}

/// Shared-storage keys and the Android provider class, which the native
/// widget (`android/app/src/main/kotlin/com/trek/trek/NextTripWidgetProvider.kt`)
/// reads with the same names.
abstract final class NextTripWidgetKeys {
  /// JSON array of `{id, title, start_date, end_date}` objects.
  static const candidates = 'next_trip.candidates';

  static const androidProvider = 'com.trek.trek.NextTripWidgetProvider';
}

/// [HomeWidgetPublisher] backed by `package:home_widget`, which writes to
/// the `SharedPreferences` file the Android widget reads.
///
/// Only Android has a widget so far; on other platforms every call is a
/// no-op (iOS needs a WidgetKit extension and an App Group before
/// `home_widget` has anywhere to write — see docs/home-widgets.md).
class PluginHomeWidgetPublisher implements HomeWidgetPublisher {
  PluginHomeWidgetPublisher({bool? isSupported})
    : _isSupported =
          isSupported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final bool _isSupported;

  @override
  Future<void> publishNextTrip(List<WidgetTrip> candidates) async {
    if (!_isSupported) return;
    await HomeWidget.saveWidgetData<String>(
      NextTripWidgetKeys.candidates,
      jsonEncode([for (final trip in candidates) trip.toJson()]),
    );
    await _redraw();
  }

  @override
  Future<void> clear() async {
    if (!_isSupported) return;
    await HomeWidget.saveWidgetData<String>(
      NextTripWidgetKeys.candidates,
      null,
    );
    await _redraw();
  }

  Future<void> _redraw() => HomeWidget.updateWidget(
    qualifiedAndroidName: NextTripWidgetKeys.androidProvider,
  );
}
