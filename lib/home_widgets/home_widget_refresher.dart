import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// Keeps the home-screen widget in step with the app, without any UI of
/// its own: refreshes it (see `NextTripWidgetSync`) when mounted with a
/// live session, whenever a session starts, and whenever the app returns
/// to the foreground; clears it on sign-out.
///
/// Every refresh is best-effort — a failure is logged, never surfaced, since
/// the widget keeps showing its last published (or cached) data.
class HomeWidgetRefresher extends ConsumerStatefulWidget {
  const HomeWidgetRefresher({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HomeWidgetRefresher> createState() =>
      _HomeWidgetRefresherState();
}

class _HomeWidgetRefresherState extends ConsumerState<HomeWidgetRefresher>
    with WidgetsBindingObserver {
  late final ValueNotifier<bool> _isAuthenticated;

  @override
  void initState() {
    super.initState();
    _isAuthenticated = ref.read(authServiceProvider).isAuthenticated;
    _isAuthenticated.addListener(_onAuthChanged);
    WidgetsBinding.instance.addObserver(this);
    if (_isAuthenticated.value) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isAuthenticated.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isAuthenticated.value) {
      _refresh();
    }
  }

  void _onAuthChanged() {
    if (_isAuthenticated.value) {
      _refresh();
    } else {
      _run(() => ref.read(nextTripWidgetSyncProvider).clear());
    }
  }

  void _refresh() => _run(() => ref.read(nextTripWidgetSyncProvider).refresh());

  Future<void> _run(Future<Object?> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      debugPrint('HomeWidgetRefresher: $error\n$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
