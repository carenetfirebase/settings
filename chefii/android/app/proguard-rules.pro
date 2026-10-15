# Flutter and plugin classes are kept by their own consumer rules.
# Keep notification receivers referenced from the manifest.
-keep class com.dexterous.** { *; }
# Speech and TTS plugins use reflection on Android service classes.
-keep class android.speech.** { *; }
-dontwarn com.google.android.play.core.**
