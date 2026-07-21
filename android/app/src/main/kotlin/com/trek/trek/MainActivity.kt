package com.trek.trek

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth —
// Android's BiometricPrompt needs a FragmentActivity host.
class MainActivity : FlutterFragmentActivity()
