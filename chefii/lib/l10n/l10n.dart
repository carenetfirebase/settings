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
