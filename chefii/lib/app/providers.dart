import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/services/analytics.dart';
import '../core/services/notification_service.dart';
import '../data/ai/ai_gateway.dart';
import '../data/auth/auth_service.dart';
import '../data/paths.dart';
import '../data/repositories/health_repositories.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/kitchen_repositories.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/receipt_repository.dart';
import '../data/store/doc_store.dart';
import '../domain/models/codec.dart';
import '../domain/models/health.dart';
import '../domain/models/inventory.dart';
import '../domain/models/meals.dart';
import '../domain/models/planning.dart';
import '../domain/models/professional.dart';
import '../domain/models/profile.dart';
import '../domain/models/receipt.dart';
import '../domain/models/recipe.dart';
import '../domain/recipes/curated_recipes.dart';
import '../domain/recipes/curated_recipes_fr.dart';
import '../domain/recipes/recipe_french.dart';
import 'config.dart';

// ---------------------------------------------------------------- platform
// Overridden in main() (and in tests).

final appConfigProvider = Provider<AppConfig>((ref) => const AppConfig(backend: BackendMode.demo));
final docStoreProvider = Provider<DocStore>((ref) => throw UnimplementedError('docStoreProvider must be overridden'));
final authServiceProvider = Provider<AuthService>((ref) => throw UnimplementedError('authServiceProvider must be overridden'));
final aiGatewayProvider = Provider<AiGateway>((ref) => throw UnimplementedError('aiGatewayProvider must be overridden'));
final imageUploaderProvider = Provider<ImageUploader>((ref) => throw UnimplementedError('imageUploaderProvider must be overridden'));
final notificationServiceProvider = Provider<NotificationService>((ref) => RecordingNotificationService());
final analyticsProvider = Provider<Analytics>((ref) => DebugAnalytics());
final clockProvider = Provider<DateTime Function()>((ref) => () => DateTime.now().toUtc());

// ---------------------------------------------------------------- repositories

final inventoryRepoProvider = Provider((ref) => InventoryRepository(ref.watch(docStoreProvider), clock: ref.watch(clockProvider)));
final profileRepoProvider = Provider((ref) => ProfileRepository(ref.watch(docStoreProvider), clock: ref.watch(clockProvider)));
final householdRepoProvider = Provider((ref) => HouseholdRepository(ref.watch(docStoreProvider), clock: ref.watch(clockProvider)));
final receiptRepoProvider = Provider((ref) => ReceiptRepository(ref.watch(docStoreProvider), clock: ref.watch(clockProvider)));
final receiptImportProvider = Provider(
  (ref) => ReceiptImportService(ref.watch(docStoreProvider), ref.watch(inventoryRepoProvider), clock: ref.watch(clockProvider)),
);
final recipeRepoProvider = Provider((ref) => RecipeRepository(ref.watch(docStoreProvider), clock: ref.watch(clockProvider)));
final cookingRepoProvider = Provider(
  (ref) => CookingRepository(ref.watch(docStoreProvider), ref.watch(inventoryRepoProvider), clock: ref.watch(clockProvider)),
);
final planningRepoProvider = Provider((ref) => PlanningRepository(ref.watch(docStoreProvider), clock: ref.watch(clockProvider)));
final journalRepoProvider = Provider((ref) => JournalRepository(ref.watch(docStoreProvider), clock: ref.watch(clockProvider)));
final healthRepoProvider = Provider((ref) => HealthRepository(ref.watch(docStoreProvider), clock: ref.watch(clockProvider)));
final sharingRepoProvider = Provider((ref) => SharingRepository(ref.watch(docStoreProvider), clock: ref.watch(clockProvider)));

// ---------------------------------------------------------------- session

final authUserProvider = StreamProvider<AppUser?>((ref) => ref.watch(authServiceProvider).userChanges);

final uidProvider = Provider<String?>((ref) => ref.watch(authUserProvider).value?.uid);

final profileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(profileRepoProvider).watchProfile(uid);
});

final householdIdProvider = Provider<String?>((ref) => ref.watch(profileProvider).value?.householdId);

final householdProvider = StreamProvider<Household?>((ref) {
  final id = ref.watch(householdIdProvider);
  if (id == null) return Stream.value(null);
  return ref.watch(householdRepoProvider).watchHousehold(id);
});

final membersProvider = StreamProvider<List<HouseholdMember>>((ref) {
  final id = ref.watch(householdIdProvider);
  if (id == null) return Stream.value(const []);
  return ref.watch(householdRepoProvider).watchMembers(id);
});

Stream<T> _userStream<T>(Ref ref, T empty, Stream<T> Function(String uid) f) {
  final uid = ref.watch(uidProvider);
  return uid == null ? Stream.value(empty) : f(uid);
}

Stream<T> _householdStream<T>(Ref ref, T empty, Stream<T> Function(String hid) f) {
  final hid = ref.watch(householdIdProvider);
  return hid == null ? Stream.value(empty) : f(hid);
}

final dietaryProvider = StreamProvider<DietaryProfile>(
  (ref) => _userStream(ref, const DietaryProfile(), (uid) => ref.watch(profileRepoProvider).watchDietary(uid)),
);

/// What a household meal must respect: my profile + allergens others chose
/// to share for cooking safety.
final householdDietaryProvider = Provider<DietaryProfile>((ref) {
  final mine = ref.watch(dietaryProvider).value ?? const DietaryProfile();
  final uid = ref.watch(uidProvider);
  final shared = <String>{
    for (final m in ref.watch(membersProvider).value ?? const <HouseholdMember>[])
      if (m.uid != uid) ...m.sharedAllergens,
  };
  return mine.copyWith(allergies: {...mine.allergies, ...shared}.toList());
});

final wellnessProvider = StreamProvider<WellnessPreferences>(
  (ref) => _userStream(ref, const WellnessPreferences(), (uid) => ref.watch(profileRepoProvider).watchWellness(uid)),
);

final settingsProvider = StreamProvider<AppSettings>(
  (ref) => _userStream(ref, const AppSettings(), (uid) => ref.watch(profileRepoProvider).watchSettings(uid)),
);

final consentsProvider = StreamProvider<List<ConsentRecord>>(
  (ref) => _userStream(ref, const <ConsentRecord>[], (uid) => ref.watch(profileRepoProvider).watchConsents(uid)),
);

final morningRoutineProvider = StreamProvider<MorningRoutine>(
  (ref) => _userStream(ref, const MorningRoutine(), (uid) => ref.watch(profileRepoProvider).watchMorningRoutine(uid)),
);

final notificationsProvider = StreamProvider<List<AppNotification>>(
  (ref) => _userStream(ref, const <AppNotification>[], (uid) => ref.watch(profileRepoProvider).watchNotifications(uid)),
);

final favouritesProvider = StreamProvider<Set<String>>(
  (ref) => _userStream(ref, const <String>{}, (uid) => ref.watch(profileRepoProvider).watchFavourites(uid)),
);

final auditProvider = StreamProvider<List<AuditEvent>>(
  (ref) => _userStream(ref, const <AuditEvent>[], (uid) => ref.watch(profileRepoProvider).watchAudit(uid)),
);

// ---------------------------------------------------------------- kitchen

final todayProvider = Provider<CalendarDate>((ref) => CalendarDate.fromDateTime(ref.watch(clockProvider)().toLocal()));

final lotsProvider = StreamProvider<List<InventoryLot>>(
  (ref) => _householdStream(ref, const <InventoryLot>[], (hid) => ref.watch(inventoryRepoProvider).watchLots(hid)),
);

final productsProvider = StreamProvider<List<FoodProduct>>(
  (ref) => _householdStream(ref, const <FoodProduct>[], (hid) => ref.watch(inventoryRepoProvider).watchProducts(hid)),
);

final recentOperationsProvider = StreamProvider<List<InventoryOperation>>(
  (ref) => _householdStream(ref, const <InventoryOperation>[], (hid) => ref.watch(inventoryRepoProvider).watchRecentOperations(hid)),
);

final _locationsStreamProvider = StreamProvider<List<StorageLocation>>(
  (ref) => _householdStream(ref, StorageLocation.defaults, (hid) => ref.watch(inventoryRepoProvider).watchLocations(hid)),
);

/// Built-in places plus the household's own; never empty.
final storageLocationsProvider = Provider<List<StorageLocation>>(
  (ref) => ref.watch(_locationsStreamProvider).value ?? StorageLocation.defaults,
);

final receiptsProvider = StreamProvider<List<PurchaseReceipt>>(
  (ref) => _householdStream(ref, const <PurchaseReceipt>[], (hid) => ref.watch(receiptRepoProvider).watchRecent(hid)),
);

final receiptProvider = StreamProvider.family<PurchaseReceipt?, String>((ref, id) {
  final hid = ref.watch(householdIdProvider);
  if (hid == null) return Stream.value(null);
  return ref.watch(receiptRepoProvider).watch(hid, id);
});

final lotProvider = StreamProvider.family<InventoryLot?, String>((ref, id) {
  final hid = ref.watch(householdIdProvider);
  if (hid == null) return Stream.value(null);
  return ref.watch(inventoryRepoProvider).watchLot(hid, id);
});

final productHistoryProvider = StreamProvider.family<List<InventoryAdjustment>, String>((ref, productId) {
  final hid = ref.watch(householdIdProvider);
  if (hid == null) return Stream.value(const []);
  return ref.watch(inventoryRepoProvider).watchAdjustmentsForProduct(hid, productId);
});

final savedRecipesProvider = StreamProvider<List<Recipe>>(
  (ref) => _householdStream(ref, const <Recipe>[], (hid) => ref.watch(recipeRepoProvider).watchSaved(hid)),
);

/// Recipes generated this session (AI results not yet saved), by id.
class RecipeCache extends Notifier<Map<String, Recipe>> {
  @override
  Map<String, Recipe> build() => const {};

  void putAll(Iterable<Recipe> rs) => state = {...state, for (final r in rs) r.id: r};
}

final recipeCacheProvider = NotifierProvider<RecipeCache, Map<String, Recipe>>(RecipeCache.new);

/// True when content (recipes, evidence) should be shown in French: the
/// language setting, or the device language when set to 'system'.
final frenchContentProvider = Provider<bool>((ref) {
  final language = ref.watch(settingsProvider).value?.language ?? 'system';
  if (language == 'fr-CA') return true;
  if (language == 'en-CA') return false;
  return WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'fr';
});

/// The curated library in the current content language.
final localizedCuratedProvider = Provider<Map<String, Recipe>>((ref) {
  final french = ref.watch(frenchContentProvider);
  return {for (final r in curatedRecipes) r.id: french ? applyFrench(r, curatedFrench[r.id]) : r};
});

final allRecipesProvider = Provider<List<Recipe>>((ref) {
  final saved = ref.watch(savedRecipesProvider).value ?? const <Recipe>[];
  final curated = ref.watch(localizedCuratedProvider);
  return [...curated.values, ...saved.where((r) => !curated.containsKey(r.id))];
});

/// Looks a recipe up across curated, saved and this session's AI results.
final recipeByIdProvider = Provider.family<Recipe?, String>((ref, id) {
  return ref.watch(localizedCuratedProvider)[id] ??
      ref.watch(recipeCacheProvider)[id] ??
      (ref.watch(savedRecipesProvider).value ?? const <Recipe>[]).where((r) => r.id == id).firstOrNull;
});

final cookingSessionProvider = StreamProvider.family<CookingSession?, String>((ref, id) {
  final hid = ref.watch(householdIdProvider);
  if (hid == null) return Stream.value(null);
  return ref.watch(cookingRepoProvider).watch(hid, id);
});

final shoppingProvider = StreamProvider<List<ShoppingItem>>(
  (ref) => _householdStream(ref, const <ShoppingItem>[], (hid) => ref.watch(planningRepoProvider).watchShopping(hid)),
);

/// Meal plan for the 7 days starting at [weekStart].
final mealPlanProvider = StreamProvider.family<List<MealPlanEntry>, CalendarDate>((ref, weekStart) {
  final hid = ref.watch(householdIdProvider);
  if (hid == null) return Stream.value(const []);
  return ref.watch(planningRepoProvider).watchRange(hid, weekStart, weekStart.addDays(7));
});

/// Journal entries in [from, to) (UTC instants), newest first.
final journalProvider = StreamProvider.family<List<MealConsumption>, ({DateTime from, DateTime to})>((ref, range) {
  final uid = ref.watch(uidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(journalRepoProvider).watchRange(uid, range.from, range.to);
});

final glucoseProvider = StreamProvider<List<GlucoseEntry>>(
  (ref) => _userStream(ref, const <GlucoseEntry>[], (uid) => ref.watch(healthRepoProvider).watchGlucose(uid)),
);

final oralProvider = StreamProvider<List<OralExposureEvent>>(
  (ref) => _userStream(ref, const <OralExposureEvent>[], (uid) => ref.watch(healthRepoProvider).watchOral(uid)),
);

final concernsProvider = StreamProvider<List<UserConcern>>(
  (ref) => _userStream(ref, const <UserConcern>[], (uid) => ref.watch(healthRepoProvider).watchConcerns(uid)),
);

final myGrantsProvider = StreamProvider<List<ShareGrant>>(
  (ref) => _userStream(ref, const <ShareGrant>[], (uid) => ref.watch(sharingRepoProvider).watchMyGrants(uid)),
);

final myAssessmentsProvider = StreamProvider<List<ProfessionalAssessment>>(
  (ref) => _userStream(ref, const <ProfessionalAssessment>[], (uid) => ref.watch(sharingRepoProvider).watchAssessmentsForClient(uid)),
);

final myProfessionalProfileProvider = StreamProvider<ProfessionalProfile?>(
  (ref) => _userStream<ProfessionalProfile?>(ref, null, (uid) => ref.watch(sharingRepoProvider).watchProfessional(uid)),
);

final proGrantsProvider = StreamProvider<List<ShareGrant>>(
  (ref) => _userStream(ref, const <ShareGrant>[], (uid) => ref.watch(sharingRepoProvider).watchGrantsForProfessional(uid)),
);

final proAssessmentsProvider = StreamProvider<List<ProfessionalAssessment>>(
  (ref) => _userStream(ref, const <ProfessionalAssessment>[], (uid) => ref.watch(sharingRepoProvider).watchAssessmentsByProfessional(uid)),
);

final shareGrantProvider = StreamProvider.family<ShareGrant?, String>((ref, id) => ref.watch(sharingRepoProvider).watchGrant(id));

/// Firestore path of the current user's root, for convenience.
final userPathsProvider = Provider<UserPaths?>((ref) {
  final uid = ref.watch(uidProvider);
  return uid == null ? null : UserPaths(uid);
});
