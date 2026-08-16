package com.barkodhalkmarket.marketplus

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth (parmak izi/biyometrik giriş) paketi Android'de
// FlutterFragmentActivity gerektiriyor (AndroidX BiometricPrompt
// API'si Fragment tabanlı çalışıyor) — FlutterActivity ile çalışmaz.
class MainActivity : FlutterFragmentActivity()
