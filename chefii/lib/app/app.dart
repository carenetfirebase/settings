import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/design/theme.dart';
import '../core/services/notification_service.dart';
import '../l10n/l10n.dart';
import '../domain/models/profile.dart';
import 'providers.dart';
import 'router.dart';

class ChefiiApp extends ConsumerStatefulWidget {
  const ChefiiApp({super.key});

  @override
  ConsumerState<ChefiiApp> createState() => _ChefiiAppState();
}

class _ChefiiAppState extends ConsumerState<ChefiiApp> {
  @override
  void initState() {
    super.initState();
    // Notification taps deep-link into the app (alarm, timers, receipts).
    ref.read(notificationServiceProvider).init(onTap: (payload) {
      if (payload != null && payload.startsWith('/')) ref.read(routerProvider).push(payload);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    ref.listen(settingsProvider, (_, next) => ref.read(analyticsProvider).enabled = next.value?.analyticsConsent ?? false);
    notificationLocale = localeForSetting(settings.language);
    return MaterialApp.router(
      title: 'Chefii', // l10n-ignore: brand name
      debugShowCheckedModeBanner: false,
      theme: ChefiiTheme.light,
      darkTheme: ChefiiTheme.dark,
      // Premium light mode is the launch design; dark follows the system.
      themeMode: ThemeMode.system,
      restorationScopeId: 'chefii',
      routerConfig: router,
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: supportedAppLocales,
      locale: localeForSetting(settings.language),
      // Any French variant gets Canadian French; everything else English (Canada).
      localeResolutionCallback: (device, supported) =>
          device?.languageCode == 'fr' ? const Locale('fr', 'CA') : const Locale('en', 'CA'),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // Respect the device setting and multiply by the in-app preference,
        // capped so layouts remain usable.
        final scaler = TextScaler.linear((mq.textScaler.scale(1) * settings.textScale).clamp(0.85, 2.0));
        return MediaQuery(
          data: mq.copyWith(textScaler: scaler, disableAnimations: mq.disableAnimations || settings.reduceMotion),
          child: child!,
        );
      },
    );
  }
}
