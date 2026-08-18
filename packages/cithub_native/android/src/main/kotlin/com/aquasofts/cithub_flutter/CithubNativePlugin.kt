package com.aquasofts.cithub_flutter

import io.flutter.embedding.engine.plugins.FlutterPlugin

class CithubNativePlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeApiBootstrap.register(binding.applicationContext, binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeApiBootstrap.unregister(binding.binaryMessenger)
    }
}
