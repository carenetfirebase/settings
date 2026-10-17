import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../l10n/l10n.dart';

/// On-device speech recognition for "I used two eggs". Transcripts are parsed
/// locally first; nothing is sent anywhere unless the local parser fails and
/// the user has AI processing enabled.
abstract class VoiceInput {
  Future<bool> available();

  /// Listens once and completes with the final transcript (or null).
  Future<String?> listenOnce({void Function(String partial)? onPartial, String? localeId});
  Future<void> stop();
}

class SpeechVoiceInput implements VoiceInput {
  final _stt = SpeechToText();
  bool? _ok;

  @override
  Future<bool> available() async {
    try {
      return _ok ??= await _stt.initialize();
    } catch (_) {
      return _ok = false;
    }
  }

  @override
  Future<String?> listenOnce({void Function(String partial)? onPartial, String? localeId}) async {
    if (!await available()) return null;
    final done = Completer<String?>();
    await _stt.listen(
      onResult: (r) {
        onPartial?.call(r.recognizedWords);
        if (r.finalResult && !done.isCompleted) done.complete(r.recognizedWords.trim().isEmpty ? null : r.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        onDevice: false,
        localeId: localeId ?? ActiveLanguage.speechLocaleId,
        cancelOnError: true,
      ),
    );
    return done.future.timeout(const Duration(seconds: 15), onTimeout: () async {
      await _stt.stop();
      return _stt.lastRecognizedWords.trim().isEmpty ? null : _stt.lastRecognizedWords;
    });
  }

  @override
  Future<void> stop() => _stt.stop();
}

/// Reads guided-cooking steps aloud.
abstract class Speaker {
  Future<void> speak(String text);
  Future<void> stop();
}

class TtsSpeaker implements Speaker {
  final _tts = FlutterTts();
  String? _language;

  @override
  Future<void> speak(String text) async {
    final language = ActiveLanguage.tag;
    if (_language != language) {
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(0.47);
      _language = language;
    }
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() => _tts.stop();
}

class SilentSpeaker implements Speaker {
  final spoken = <String>[];
  @override
  Future<void> speak(String text) async => spoken.add(text);
  @override
  Future<void> stop() async {}
}

class UnavailableVoiceInput implements VoiceInput {
  @override
  Future<bool> available() async => false;
  @override
  Future<String?> listenOnce({void Function(String partial)? onPartial, String? localeId}) async => null;
  @override
  Future<void> stop() async {}
}

final voiceInputProvider = Provider<VoiceInput>((ref) => SpeechVoiceInput());
final speakerProvider = Provider<Speaker>((ref) => TtsSpeaker());
