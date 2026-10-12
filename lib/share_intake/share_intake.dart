import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Text other apps share into Trek through the OS share sheet.
///
/// Android only: `MainActivity` registers an `ACTION_SEND` `text/plain`
/// intent filter and forwards the shared text over the `trek/share_intake`
/// method channel. iOS needs a Share Extension target, which doesn't exist
/// yet — there, [takeInitialShare] returns `null` and [shares] never emits.
abstract class ShareIntake {
  /// The text that launched the app, if it was started from the share
  /// sheet. Returned once; later calls return `null`.
  Future<String?> takeInitialShare();

  /// Text shared while the app is already running.
  Stream<String> get shares;
}

class MethodChannelShareIntake implements ShareIntake {
  MethodChannelShareIntake({
    MethodChannel channel = const MethodChannel('trek/share_intake'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;
  final _controller = StreamController<String>.broadcast();

  Future<void> _handle(MethodCall call) async {
    if (call.method == 'onShare' && call.arguments is String) {
      _controller.add(call.arguments as String);
    }
  }

  @override
  Future<String?> takeInitialShare() async {
    try {
      return await _channel.invokeMethod<String>('getInitialShare');
    } on MissingPluginException {
      // iOS (no share extension yet) — nothing was shared.
      return null;
    } on PlatformException catch (error) {
      debugPrint('ShareIntake: getInitialShare failed: $error');
      return null;
    }
  }

  @override
  Stream<String> get shares => _controller.stream;
}
