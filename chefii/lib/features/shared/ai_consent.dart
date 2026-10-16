import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/design/design.dart';
import '../../domain/models/profile.dart';
import '../../l10n/l10n.dart';

/// Asks for AI-processing consent the first time a feature needs it.
/// Returns true if the feature may proceed. Demo mode needs no consent
/// because nothing leaves the device. [feature] is shown in the dialog
/// title, so pass it already translated.
Future<bool> ensureAiConsent(BuildContext context, WidgetRef ref, {required String feature}) async {
  if (ref.read(aiGatewayProvider).isDemo) return true;
  final uid = ref.read(uidProvider);
  if (uid == null) return false;
  final settings = ref.read(settingsProvider).value ?? const AppSettings();
  if (settings.aiProcessingConsent) return true;
  final l = context.l10n;
  final ok = await showConfirmActionSheet(
    context,
    title: l.sharedAiConsentTitle(feature),
    message: l.sharedAiConsentMessage,
    confirmLabel: l.sharedAiConsentAllow,
    cancelLabel: l.sharedAiConsentNotNow,
  );
  if (!ok) return false;
  await ref.read(profileRepoProvider).saveSettings(uid, settings.copyWith(aiProcessingConsent: true));
  await ref.read(profileRepoProvider).recordConsent(uid, purpose: 'ai_processing', granted: true);
  return true;
}
