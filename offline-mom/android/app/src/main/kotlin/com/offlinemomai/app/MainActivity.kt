package com.offlinemomai.app

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth's Android implementation drives AndroidX's Fragment-based
// BiometricPrompt API, which requires a FragmentActivity host - plain
// FlutterActivity isn't one.
class MainActivity: FlutterFragmentActivity()
