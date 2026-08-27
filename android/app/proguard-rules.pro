# Keep the Flutter engine, embedding, and plugin registrant classes intact.
# The plugin registrant is generated and invoked via reflection-adjacent
# codegen; stripping/renaming it breaks plugin registration at runtime.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# flutter_local_notifications posts the day-1 recap notification from the
# background engine; its Android side (icon/action handling) is looked up
# by class name from plugin + manifest metadata.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# sqflite (federated: sqflite_android) drives IntentStore's persistent
# connection from both the UI and background engines — keep its plugin and
# native bridge classes so shrinking can't touch the method-channel surface.
-keep class com.tekartik.sqflite.** { *; }

# Our flutter_overlay_window fork (diniiidinesh/flutter_overlay_window) runs
# the bubble's second Flutter engine + native OverlayService; keep it whole
# so R8 doesn't strip anything the overlay/background port relay depends on.
-keep class flutter.overlay.window.flutter_overlay_window.** { *; }

# Flutter's embedding references Play Core's deferred-components (dynamic
# feature module) classes unconditionally, even though we don't use deferred
# components and don't depend on play-core — R8 fails outright on the
# missing classes without these. Generated verbatim from R8's own
# missing_rules.txt output; safe as -dontwarn since the referencing code
# paths (PlayStoreDeferredComponentManager, FlutterPlayStoreSplitApplication)
# are never reached.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
