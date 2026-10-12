import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../app/app_messenger.dart';
import '../../auth/auth_service.dart';
import '../../share_intake/share_intake.dart';
import '../../share_intake/shared_map_link.dart';
import 'share_import_repository.dart';

/// App-lifetime glue between the OS share sheet and the share-import
/// feature:
///
/// - Parses text from [ShareIntake] into a [SharedMapLink] and publishes it
///   on [incoming], which the router watches to open `/share-import` (after
///   login, if the user is signed out). Text without a supported map link
///   gets an explanatory message instead.
/// - Flushes queued imports ([ShareImportRepository.flushPending]) when the
///   app returns to the foreground and right after login — the moments
///   connectivity is most likely to have come back. The startup flush is
///   triggered by `TrekApp` once the router (and so the snackbar messenger
///   that reports the result) is on screen.
class ShareImportCoordinator with WidgetsBindingObserver {
  ShareImportCoordinator({
    required ShareIntake intake,
    required ValueNotifier<SharedMapLink?> incoming,
    required ShareImportRepository repository,
    required AuthService authService,
  }) : _intake = intake,
       _incoming = incoming,
       _repository = repository,
       _authService = authService;

  final ShareIntake _intake;
  final ValueNotifier<SharedMapLink?> _incoming;
  final ShareImportRepository _repository;
  final AuthService _authService;

  StreamSubscription<String>? _subscription;
  bool _started = false;

  /// Reads a share that launched the app and starts listening for more.
  /// Call once, after the session has been restored and before the router
  /// is built, so a cold-start share is routed on the first frame.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _subscription = _intake.shares.listen(handleSharedText);
    WidgetsBinding.instance.addObserver(this);
    _authService.isAuthenticated.addListener(_onAuthChanged);

    final initial = await _intake.takeInitialShare();
    if (initial != null) handleSharedText(initial);
  }

  void dispose() {
    _subscription?.cancel();
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
      _authService.isAuthenticated.removeListener(_onAuthChanged);
    }
  }

  void handleSharedText(String text) {
    final link = SharedMapLink.parse(text);
    if (link == null) {
      AppMessenger.showInfo(
        'Trek can add Google Maps, Apple Maps, or Amap links to a trip. '
        'No map link was found in what was shared.',
      );
      return;
    }
    _incoming.value = link;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(flush());
  }

  void _onAuthChanged() {
    if (_authService.isAuthenticated.value) unawaited(flush());
  }

  /// Sends queued imports if signed in, and reports what happened. Never
  /// throws — a storage or parsing failure is logged and retried next time.
  Future<void> flush() async {
    if (!_authService.isAuthenticated.value) return;
    try {
      final report = await _repository.flushPending();
      if (report.added.length == 1) {
        AppMessenger.showSuccess(
          'Added "${report.added.single}" to your trip.',
        );
      } else if (report.added.length > 1) {
        AppMessenger.showSuccess(
          'Added ${report.added.length} shared places to your trips.',
        );
      }
      for (final message in report.rejected) {
        AppMessenger.showError(message);
      }
    } catch (error, stackTrace) {
      debugPrint('ShareImportCoordinator: flush failed: $error\n$stackTrace');
    }
  }
}
