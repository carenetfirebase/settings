import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/design/design.dart';
import '../domain/models/nutrition.dart';
import '../l10n/l10n.dart';
import '../features/account/account_screens.dart';
import '../features/chef/chef_screens.dart';
import '../features/cooking/cooking_screens.dart';
import '../features/discover/discover_screen.dart';
import '../features/health/nutrition_screens.dart';
import '../features/health/smile_diabetes_screens.dart';
import '../features/journal/journal_screens.dart';
import '../features/kitchen/kitchen_screens.dart';
import '../features/morning/morning_screens.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/planning/planning_screens.dart';
import '../features/professionals/circle_screens.dart';
import '../features/receipts/receipt_screens.dart';
import '../features/today/today_screens.dart';
import 'providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Where a session should be, given auth and onboarding state.
/// Returns null to stay. Pure so it can be unit-tested.
String? sessionRedirect({required String location, required bool authLoading, required bool signedIn, required bool profileLoading, required bool onboarded}) {
  const public = ['/welcome', '/onboarding/meet', '/onboarding/account', '/you/legal'];
  final isPublic = public.any(location.startsWith);
  final isOnboarding = location.startsWith('/onboarding');
  if (authLoading) return null;
  if (!signedIn) return isPublic ? null : '/welcome';
  if (profileLoading) return null;
  if (!onboarded) {
    if (isOnboarding || location == '/you/legal') return null;
    return '/onboarding/household';
  }
  if (location == '/' || location == '/welcome' || isOnboarding) return '/today';
  return null;
}

/// Bridges Riverpod session state to go_router's refreshListenable.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authUserProvider, (_, _) => notifyListeners());
    ref.listen(profileProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  GoRoute r(String path, Widget Function(GoRouterState s) build, {List<RouteBase> routes = const []}) =>
      GoRoute(path: path, builder: (_, s) => build(s), routes: routes);
  // Full-screen flows sit above the tab bar.
  GoRoute top(String path, Widget Function(GoRouterState s) build) =>
      GoRoute(path: path, parentNavigatorKey: rootNavigatorKey, builder: (_, s) => build(s));

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    restorationScopeId: 'router',
    redirect: (context, state) {
      final auth = ref.read(authUserProvider);
      final profile = ref.read(profileProvider);
      return sessionRedirect(
        location: state.uri.path,
        authLoading: auth.isLoading && !auth.hasValue,
        signedIn: auth.value != null,
        profileLoading: profile.isLoading && !profile.hasValue,
        onboarded: profile.value?.onboardingComplete ?? false,
      );
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        icon: Icons.explore_off_outlined,
        title: context.l10n.corePageNotFound,
        message: context.l10n.corePageNotFoundMessage,
        actionLabel: context.l10n.coreGoToToday,
        onAction: () => context.go('/today'),
      ),
    ),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _Splash()),
      // ---- Onboarding 01–08
      r('/welcome', (_) => const WelcomeScreen()),
      r('/onboarding/meet', (_) => const MeetChefScreen()),
      r('/onboarding/account', (s) => AccountScreen(signInMode: s.uri.queryParameters['mode'] == 'signin')),
      r('/onboarding/household', (_) => const HouseholdSetupScreen()),
      r('/onboarding/dietary', (_) => const DietarySafetyScreen()),
      r('/onboarding/culinary', (_) => const CulinaryPreferencesScreen()),
      r('/onboarding/wellness', (_) => const WellnessPreferencesScreen()),
      r('/onboarding/kitchen', (_) => const BuildKitchenScreen()),

      // ---- Tabs: Today | Kitchen | Discover | Journal | You
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => BottomNavigationShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            r('/today', (_) => const TodayScreen(), routes: [
              r('briefing', (_) => const DailyBriefingScreen()),
              r('notifications', (_) => const NotificationCentreScreen()),
            ]),
          ]),
          StatefulShellBranch(routes: [
            r('/kitchen', (_) => const KitchenScreen(), routes: [
              r('location/:id', (s) => StorageLocationScreen(locationId: s.pathParameters['id']!)),
              r('item/:id', (s) => IngredientDetailScreen(lotId: s.pathParameters['id']!)),
              r('add', (s) => AddProductScreen(initialLocation: s.uri.queryParameters['location'])),
              r('scan', (_) => const FridgeScanScreen()),
              r('freshness', (_) => const FreshnessCentreScreen()),
              r('reconcile', (s) => ReconciliationScreen(locationId: s.uri.queryParameters['location'])),
              r('shopping', (_) => const ShoppingListScreen(), routes: [
                r(':id', (s) => ShoppingItemScreen(itemId: s.pathParameters['id']!)),
              ]),
              r('spending', (_) => const SpendingWasteScreen()),
              r('receipts', (_) => const ReceiptsListScreen()),
            ]),
          ]),
          StatefulShellBranch(routes: [
            r('/discover', (s) => DiscoverScreen(initialFilter: s.uri.queryParameters['filter'], ingredient: s.uri.queryParameters['ingredient'])),
          ]),
          StatefulShellBranch(routes: [
            r('/journal', (_) => const JournalScreen(), routes: [
              r('add', (s) => QuickMealEntryScreen(day: s.uri.queryParameters['day'])),
              r('history', (_) => const FoodJournalScreen()),
              r('entry/:id', (s) => JournalEntryScreen(entryId: s.pathParameters['id']!)),
              r('reminders', (_) => const EatingRemindersScreen()),
              r('patterns', (_) => const EatingPatternsScreen()),
            ]),
          ]),
          StatefulShellBranch(routes: [
            r('/you', (_) => const YouScreen(), routes: [
              r('dietary', (_) => const DietarySafetyScreen(editing: true)),
              r('culinary', (_) => const CulinaryPreferencesScreen(editing: true)),
              r('wellness', (_) => const WellnessPreferencesScreen(editing: true)),
              r('nutrition', (_) => const NutritionDashboardScreen(), routes: [
                r('intelligence', (_) => const NutritionIntelligenceScreen()),
                r('hair-skin-nails', (_) => const HairSkinNailsScreen()),
                r('evidence', (s) => EvidenceScreen(claimId: s.uri.queryParameters['claim'])),
                r('nutrient/:name', (s) => NutrientDetailScreen(nutrient: Nutrient.values.byName(s.pathParameters['name']!))),
              ]),
              r('smile', (_) => const SmileAndFoodScreen(), routes: [r('history', (_) => const DentalHistoryScreen())]),
              r('diabetes', (_) => const DiabetesSetupScreen()),
              r('glucose', (s) => GlucoseJournalScreen(unit: s.uri.queryParameters['unit']), routes: [r('timeline', (_) => const GlucoseTimelineScreen())]),
              r('circle', (_) => const NutritionCircleScreen(), routes: [
                r('share/:pro', (s) => SharingPermissionsScreen(professionalUid: s.pathParameters['pro']!)),
                r('review/:id', (s) => AssessmentDetailScreen(assessmentId: s.pathParameters['id']!)),
              ]),
              r('household', (_) => const HouseholdMembersScreen()),
              r('privacy', (_) => const PrivacyScreen()),
              r('connected', (_) => const ConnectedServicesScreen()),
              r('membership', (_) => const MembershipScreen()),
              r('accessibility', (_) => const AccessibilityScreen()),
              r('security', (_) => const SecurityScreen()),
              r('help', (_) => const HelpScreen()),
              r('legal', (_) => const LegalScreen()),
              r('data', (_) => const DataControlsScreen()),
            ]),
          ]),
        ],
      ),

      // ---- Full-screen flows
      top('/receipt/capture', (_) => const ReceiptCaptureScreen()),
      top('/receipt/preview', (_) => const ReceiptPreviewScreen()),
      top('/receipt/:id/processing', (s) => ReceiptProcessingScreen(receiptId: s.pathParameters['id']!)),
      top('/receipt/:id/review', (s) => ReceiptReviewScreen(receiptId: s.pathParameters['id']!)),
      top('/receipt/:id/unknown', (s) => UnknownItemsScreen(receiptId: s.pathParameters['id']!)),
      top('/receipt/:id/storage', (s) => StorageAssignmentScreen(receiptId: s.pathParameters['id']!)),
      top('/receipt/:id/error', (s) => ReceiptErrorScreen(receiptId: s.pathParameters['id']!, reason: s.uri.queryParameters['reason'])),
      top('/receipt/:id/done', (s) => ReceiptDoneScreen(receiptId: s.pathParameters['id']!)),
      top('/chef', (_) => const ChefHomeScreen()),
      top('/chef/preferences', (_) => const ChefPreferencesScreen()),
      top('/chef/results', (_) => const RecipeResultsScreen()),
      top('/recipe/:id', (s) => RecipeDetailScreen(recipeId: s.pathParameters['id']!, planEntryId: s.uri.queryParameters['plan'])),
      top('/cook/timers', (_) => const CookingTimersScreen()),
      top('/cook/:id/prep', (s) => PrepChecklistScreen(sessionId: s.pathParameters['id']!)),
      top('/cook/:id', (s) => GuidedCookingScreen(sessionId: s.pathParameters['id']!)),
      top('/cook/:id/confirm', (s) => ConfirmIngredientsScreen(sessionId: s.pathParameters['id']!)),
      top('/cook/:id/done', (s) => MealCompleteScreen(sessionId: s.pathParameters['id']!)),
      top('/morning/setup', (_) => const MorningSetupScreen()),
      top('/morning/alarm', (_) => const AlarmSettingsScreen()),
      top('/morning/evening', (_) => const EveningPreviewScreen()),
      top('/morning/wake', (_) => const MorningAlarmScreen()),
      top('/morning/checklist', (_) => const MorningChecklistScreen()),
      top('/morning/late', (_) => const RunningLateScreen()),
      top('/plan', (_) => const WeeklyPlannerScreen()),
      top('/plan/assign', (s) => AssignMealScreen(recipeId: s.uri.queryParameters['recipe'], date: s.uri.queryParameters['date'], meal: s.uri.queryParameters['meal'])),
      top('/plan/leftovers', (_) => const LeftoversScreen()),
      top('/pro', (_) => const ProfessionalDashboardScreen()),
      top('/pro/client/:grant', (s) => ClientRecordsScreen(grantId: s.pathParameters['grant']!)),
      top('/pro/assess/:grant', (s) => ProfessionalAssessmentScreen(grantId: s.pathParameters['grant']!)),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Semantics(
            label: context.l10n.coreAppLoading,
            child: Text('CHEFII', // l10n-ignore: brand wordmark
                style: context.text.labelSmall?.copyWith(color: context.palette.accent, letterSpacing: 6, fontSize: 14)),
          ),
        ),
      );
}
