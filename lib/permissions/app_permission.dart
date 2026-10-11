import 'package:flutter/material.dart';

/// An OS permission the app asks for, with the copy shown on its priming
/// sheet (see [PermissionPrimer]) before the system prompt appears.
///
/// Only permissions with a feature that actually uses them belong here —
/// each value needs matching platform declarations (`Info.plist` usage
/// string, `Podfile` `PERMISSION_*` macro, `AndroidManifest.xml`
/// `<uses-permission>`), or the OS request silently returns denied.
enum AppPermission {
  /// "While using the app" location. Android and iOS only expose the
  /// current Wi-Fi network's name (SSID) to apps holding it, and
  /// `ServerConfigResolver` needs the SSID to switch to the private server
  /// URL on trusted networks.
  location(
    icon: Icons.wifi_find,
    title: 'Use your home server on Wi-Fi',
    rationale:
        'Your phone only tells apps the name of the Wi-Fi network you\'re '
        'on if they have location access. Trek uses it to switch to your '
        'private server address on the networks you listed, and never '
        'tracks or uploads your location.',
    blockedMessage:
        'Location access is turned off for Trek, so it can\'t see which '
        'Wi-Fi network you\'re on and will always use your public server '
        'address. You can turn it on in Settings.',
  );

  const AppPermission({
    required this.icon,
    required this.title,
    required this.rationale,
    required this.blockedMessage,
  });

  final IconData icon;

  /// Headline of the priming sheet.
  final String title;

  /// Why the app wants this permission, in terms of what the user gets.
  final String rationale;

  /// Shown instead of the priming sheet once the OS will no longer prompt
  /// (permanently denied or restricted) — the only way back is Settings.
  final String blockedMessage;
}
