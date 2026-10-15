/// Build-time configuration via `--dart-define`.
///
///   flutter run                                   # demo mode (default)
///   flutter run --dart-define=CHEFII_BACKEND=firebase
///   flutter run --dart-define=CHEFII_BACKEND=firebase --dart-define=CHEFII_EMULATORS=true
///
/// Demo mode runs fully offline with a local store and clearly labelled
/// sample AI output, so the product can be evaluated without credentials.
enum BackendMode { demo, firebase }

class AppConfig {
  const AppConfig({
    required this.backend,
    this.useEmulators = false,
    this.emulatorHost = 'localhost',
    this.googleServerClientId,
    this.appCheckDebug = false,
  });

  final BackendMode backend;
  final bool useEmulators;
  final String emulatorHost;
  final String? googleServerClientId;
  final bool appCheckDebug;

  bool get isDemo => backend == BackendMode.demo;

  static AppConfig fromEnvironment() {
    const backend = String.fromEnvironment('CHEFII_BACKEND', defaultValue: 'demo');
    const emulators = bool.fromEnvironment('CHEFII_EMULATORS');
    const host = String.fromEnvironment('CHEFII_EMULATOR_HOST', defaultValue: 'localhost');
    const clientId = String.fromEnvironment('CHEFII_GOOGLE_SERVER_CLIENT_ID');
    const appCheckDebug = bool.fromEnvironment('CHEFII_APPCHECK_DEBUG');
    return AppConfig(
      backend: backend == 'firebase' ? BackendMode.firebase : BackendMode.demo,
      useEmulators: emulators,
      emulatorHost: host,
      googleServerClientId: clientId.isEmpty ? null : clientId,
      appCheckDebug: appCheckDebug,
    );
  }
}
