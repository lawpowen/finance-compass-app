package com.financecompass.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Context

class MainActivity : FlutterActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine = FinanceEngine.get(context)
    override fun shouldDestroyEngineWithHost(): Boolean = false
}
