import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

/// `context.l10n.kitchenTitle` — the current language's strings.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// Locales Chefii ships. English (Canada) is the fallback.
const supportedAppLocales = [Locale('en', 'CA'), Locale('fr', 'CA')];

/// Maps the stored language setting ('en-CA', 'fr-CA', or 'system') to a locale;
/// null follows the device.
Locale? localeForSetting(String language) => switch (language) {
      'fr-CA' => const Locale('fr', 'CA'),
      'en-CA' => const Locale('en', 'CA'),
      _ => null,
    };

/// The language the app is currently showing, for code without a
/// BuildContext (AI requests, speech). Updated by ChefiiApp on every build.
abstract final class ActiveLanguage {
  static Locale locale = const Locale('en', 'CA');

  static bool get isFrench => locale.languageCode == 'fr';

  /// 'fr-CA' / 'en-CA' (BCP 47) for servers and text-to-speech.
  static String get tag => isFrench ? 'fr-CA' : 'en-CA';

  /// 'fr_CA' / 'en_CA' for speech recognition.
  static String get speechLocaleId => isFrench ? 'fr_CA' : 'en_CA';
}
