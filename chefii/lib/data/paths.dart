/// Canonical Firestore paths. Keep in sync with firestore.rules and
/// docs/DATA_MODELS.md.
///
/// Ownership rule: anything under `households/{hid}` is shared with household
/// members (inventory, plans, shopping). Anything under `users/{uid}` is
/// private to that person (health, journal, glucose, professional sharing)
/// and is never readable by other household members.
library;

class HouseholdPaths {
  const HouseholdPaths(this.householdId);
  final String householdId;

  String get root => 'households/$householdId';
  String get members => '$root/members';
  String member(String uid) => '$members/$uid';
  String get products => '$root/products';
  String product(String id) => '$products/$id';
  String get lots => '$root/lots';
  String lot(String id) => '$lots/$id';
  String get adjustments => '$root/adjustments';
  String adjustment(String id) => '$adjustments/$id';
  String get operations => '$root/operations';
  String operation(String id) => '$operations/$id';
  String get locations => '$root/storageLocations';
  String get receipts => '$root/receipts';
  String receipt(String id) => '$receipts/$id';
  String receiptFingerprint(String fp) => '$root/receiptFingerprints/$fp';
  String get recipes => '$root/recipes';
  String recipe(String id) => '$recipes/$id';
  String get cookingSessions => '$root/cookingSessions';
  String cookingSession(String id) => '$cookingSessions/$id';
  String get mealPlan => '$root/mealPlan';
  String mealPlanEntry(String id) => '$mealPlan/$id';
  String get shoppingItems => '$root/shoppingItems';
  String shoppingItem(String id) => '$shoppingItems/$id';
  String get invites => '$root/invites';
}

class UserPaths {
  const UserPaths(this.uid);
  final String uid;

  String get root => 'users/$uid';
  String get dietary => '$root/private/dietary';
  String get wellness => '$root/private/wellness';
  String get settings => '$root/private/settings';
  String get journal => '$root/journal';
  String journalEntry(String id) => '$journal/$id';
  String get glucose => '$root/glucose';
  String get oralExposures => '$root/oralExposures';
  String get concerns => '$root/concerns';
  String get consents => '$root/consents';
  String get notifications => '$root/notifications';
  String get reminders => '$root/reminders';
  String get morningRoutine => '$root/private/morningRoutine';
  String get audit => '$root/audit';
  String get favourites => '$root/favourites';
  String get feedback => '$root/feedback';
}

const shareGrantsCollection = 'shareGrants';
String shareGrantId(String ownerUid, String professionalUid) => '${ownerUid}__$professionalUid';
const professionalsCollection = 'professionals';
const assessmentsCollection = 'assessments';
