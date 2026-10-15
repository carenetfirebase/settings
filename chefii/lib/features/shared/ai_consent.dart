import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../domain/models/profile.dart';

/// Asks for AI-processing consent the first time a feature needs it.
/// Returns true if the feature may proceed. Demo mode needs no consent
/// because nothing leaves the device.
Future<bool> ensureAiConsent(BuildContext context, WidgetRef ref, {required String feature}) async {
  if (ref.read(aiGatewayProvider).isDemo) return true;
  final uid = ref.read(uidProvider);
  if (uid == null) return false;
  final settings = ref.read(settingsProvider).value ?? const AppSettings();
  if (settings.aiProcessingConsent) return true;
  final ok = await showConfirmActionSheet(
    context,
    title: 'Use AI for $feature?',
    message: 'To do this, Chefii sends the photo or text to its AI provider (Google Gemini) through our secure servers in Canada. '
        'It isn\'t used to train their models under our agreements, and you can turn this off any time in Privacy & data.',
    confirmLabel: 'Allow',
    cancelLabel: 'Not now',
  );
  if (!ok) return false;
  await ref.read(profileRepoProvider).saveSettings(uid, settings.copyWith(aiProcessingConsent: true));
  await ref.read(profileRepoProvider).recordConsent(uid, purpose: 'ai_processing', granted: true);
  return true;
}
