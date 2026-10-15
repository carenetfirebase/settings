import 'codec.dart';

/// Whether the user has told us something. "Not provided" is never treated
/// as "no allergies".
enum DisclosureStatus {
  notAsked('Not provided'),
  provided('Provided'),
  noneKnown('None known'),
  preferNotToSay('Prefer not to say');

  const DisclosureStatus(this.label);
  final String label;
}

enum CookingConfidence {
  beginner('Just starting'),
  comfortable('Comfortable'),
  confident('Confident'),
  accomplished('Accomplished');

  const CookingConfidence(this.label);
  final String label;
}

enum HouseholdType {
  single('Just me'),
  couple('Two of us'),
  family('Family');

  const HouseholdType(this.label);
  final String label;
}

class DietaryProfile {
  const DietaryProfile({
    this.allergyStatus = DisclosureStatus.notAsked,
    this.allergies = const [],
    this.intolerances = const [],
    this.restrictions = const [],
    this.dislikes = const [],
    this.avoidCrossContact = false,
    this.updatedAt,
  });

  final DisclosureStatus allergyStatus;

  /// Allergen keys from AllergenGuard (e.g. 'peanut', 'milk').
  final List<String> allergies;

  /// Intolerance keys (e.g. 'lactose', 'gluten').
  final List<String> intolerances;

  /// Restriction keys (e.g. 'vegetarian', 'halal').
  final List<String> restrictions;

  /// Free-text dislikes (e.g. 'cilantro').
  final List<String> dislikes;

  /// Warn about may-contain / shared-equipment risks.
  final bool avoidCrossContact;
  final DateTime? updatedAt;

  bool get allergiesKnown =>
      allergyStatus == DisclosureStatus.provided || allergyStatus == DisclosureStatus.noneKnown;

  DietaryProfile copyWith({
    DisclosureStatus? allergyStatus,
    List<String>? allergies,
    List<String>? intolerances,
    List<String>? restrictions,
    List<String>? dislikes,
    bool? avoidCrossContact,
    DateTime? updatedAt,
  }) =>
      DietaryProfile(
        allergyStatus: allergyStatus ?? this.allergyStatus,
        allergies: allergies ?? this.allergies,
        intolerances: intolerances ?? this.intolerances,
        restrictions: restrictions ?? this.restrictions,
        dislikes: dislikes ?? this.dislikes,
        avoidCrossContact: avoidCrossContact ?? this.avoidCrossContact,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Combine several people's profiles (household cooking): strictest wins.
  DietaryProfile merge(DietaryProfile o) => DietaryProfile(
        allergyStatus: allergiesKnown && o.allergiesKnown
            ? (allergies.isEmpty && o.allergies.isEmpty ? DisclosureStatus.noneKnown : DisclosureStatus.provided)
            : DisclosureStatus.notAsked,
        allergies: {...allergies, ...o.allergies}.toList(),
        intolerances: {...intolerances, ...o.intolerances}.toList(),
        restrictions: {...restrictions, ...o.restrictions}.toList(),
        dislikes: {...dislikes, ...o.dislikes}.toList(),
        avoidCrossContact: avoidCrossContact || o.avoidCrossContact,
      );

  Map<String, dynamic> toMap() => {
        'allergyStatus': allergyStatus.name,
        'allergies': allergies,
        'intolerances': intolerances,
        'restrictions': restrictions,
        'dislikes': dislikes,
        'avoidCrossContact': avoidCrossContact,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

  static DietaryProfile fromMap(Map<String, dynamic>? m) {
    if (m == null) return const DietaryProfile();
    return DietaryProfile(
      allergyStatus: readEnum(DisclosureStatus.values, m['allergyStatus'], DisclosureStatus.notAsked),
      allergies: readStrings(m['allergies']),
      intolerances: readStrings(m['intolerances']),
      restrictions: readStrings(m['restrictions']),
      dislikes: readStrings(m['dislikes']),
      avoidCrossContact: m['avoidCrossContact'] as bool? ?? false,
      updatedAt: readDateOrNull(m['updatedAt']),
    );
  }
}

class CulinaryPreferences {
  const CulinaryPreferences({
    this.cuisines = const [],
    this.favouriteFoods = const [],
    this.confidence = CookingConfidence.comfortable,
    this.spiceLevel = 2,
    this.favouriteMeals = const [],
    this.equipment = const ['Oven', 'Stovetop'],
    this.weeknightMinutes = 30,
  });

  final List<String> cuisines;
  final List<String> favouriteFoods;
  final CookingConfidence confidence;

  /// 0 (none) .. 4 (very hot).
  final int spiceLevel;
  final List<String> favouriteMeals;
  final List<String> equipment;
  final int weeknightMinutes;

  CulinaryPreferences copyWith({
    List<String>? cuisines,
    List<String>? favouriteFoods,
    CookingConfidence? confidence,
    int? spiceLevel,
    List<String>? favouriteMeals,
    List<String>? equipment,
    int? weeknightMinutes,
  }) =>
      CulinaryPreferences(
        cuisines: cuisines ?? this.cuisines,
        favouriteFoods: favouriteFoods ?? this.favouriteFoods,
        confidence: confidence ?? this.confidence,
        spiceLevel: spiceLevel ?? this.spiceLevel,
        favouriteMeals: favouriteMeals ?? this.favouriteMeals,
        equipment: equipment ?? this.equipment,
        weeknightMinutes: weeknightMinutes ?? this.weeknightMinutes,
      );

  Map<String, dynamic> toMap() => {
        'cuisines': cuisines,
        'favouriteFoods': favouriteFoods,
        'confidence': confidence.name,
        'spiceLevel': spiceLevel,
        'favouriteMeals': favouriteMeals,
        'equipment': equipment,
        'weeknightMinutes': weeknightMinutes,
      };

  static CulinaryPreferences fromMap(Map<String, dynamic>? m) {
    if (m == null) return const CulinaryPreferences();
    return CulinaryPreferences(
      cuisines: readStrings(m['cuisines']),
      favouriteFoods: readStrings(m['favouriteFoods']),
      confidence: readEnum(CookingConfidence.values, m['confidence'], CookingConfidence.comfortable),
      spiceLevel: readInt(m, 'spiceLevel', 2),
      favouriteMeals: readStrings(m['favouriteMeals']),
      equipment: m['equipment'] == null ? const ['Oven', 'Stovetop'] : readStrings(m['equipment']),
      weeknightMinutes: readInt(m, 'weeknightMinutes', 30),
    );
  }
}

class WellnessPreferences {
  const WellnessPreferences({
    this.interests = const [],
    this.calorieTracking = false,
    this.showNutritionOnRecipes = true,
    this.smileAndFood = false,
    this.diabetesFeatures = false,
  });

  /// e.g. 'balanced', 'protein', 'variety', 'education'.
  final List<String> interests;

  /// Off by default; never forced.
  final bool calorieTracking;
  final bool showNutritionOnRecipes;
  final bool smileAndFood;

  /// Gated: requires explicit consent record as well.
  final bool diabetesFeatures;

  WellnessPreferences copyWith({
    List<String>? interests,
    bool? calorieTracking,
    bool? showNutritionOnRecipes,
    bool? smileAndFood,
    bool? diabetesFeatures,
  }) =>
      WellnessPreferences(
        interests: interests ?? this.interests,
        calorieTracking: calorieTracking ?? this.calorieTracking,
        showNutritionOnRecipes: showNutritionOnRecipes ?? this.showNutritionOnRecipes,
        smileAndFood: smileAndFood ?? this.smileAndFood,
        diabetesFeatures: diabetesFeatures ?? this.diabetesFeatures,
      );

  Map<String, dynamic> toMap() => {
        'interests': interests,
        'calorieTracking': calorieTracking,
        'showNutritionOnRecipes': showNutritionOnRecipes,
        'smileAndFood': smileAndFood,
        'diabetesFeatures': diabetesFeatures,
      };

  static WellnessPreferences fromMap(Map<String, dynamic>? m) {
    if (m == null) return const WellnessPreferences();
    return WellnessPreferences(
      interests: readStrings(m['interests']),
      calorieTracking: m['calorieTracking'] as bool? ?? false,
      showNutritionOnRecipes: m['showNutritionOnRecipes'] as bool? ?? true,
      smileAndFood: m['smileAndFood'] as bool? ?? false,
      diabetesFeatures: m['diabetesFeatures'] as bool? ?? false,
    );
  }
}

class AppSettings {
  const AppSettings({
    this.reduceMotion = false,
    this.textScale = 1.0,
    this.voiceGuidance = true,
    this.language = 'en-CA',
    this.aiProcessingConsent = false,
    this.allowOptionalAiProvider = true,
    this.analyticsConsent = false,
    this.quietHoursStart = 22,
    this.quietHoursEnd = 7,
    this.mealReminders = const {},
  });

  final bool reduceMotion;
  final double textScale;
  final bool voiceGuidance;
  final String language;

  /// Consent to send images/text to third-party AI processors.
  final bool aiProcessingConsent;

  /// Allow use of the optional secondary AI provider.
  final bool allowOptionalAiProvider;
  final bool analyticsConsent;
  final int quietHoursStart;
  final int quietHoursEnd;

  /// meal name -> "HH:mm" local time.
  final Map<String, String> mealReminders;

  AppSettings copyWith({
    bool? reduceMotion,
    double? textScale,
    bool? voiceGuidance,
    String? language,
    bool? aiProcessingConsent,
    bool? allowOptionalAiProvider,
    bool? analyticsConsent,
    int? quietHoursStart,
    int? quietHoursEnd,
    Map<String, String>? mealReminders,
  }) =>
      AppSettings(
        reduceMotion: reduceMotion ?? this.reduceMotion,
        textScale: textScale ?? this.textScale,
        voiceGuidance: voiceGuidance ?? this.voiceGuidance,
        language: language ?? this.language,
        aiProcessingConsent: aiProcessingConsent ?? this.aiProcessingConsent,
        allowOptionalAiProvider: allowOptionalAiProvider ?? this.allowOptionalAiProvider,
        analyticsConsent: analyticsConsent ?? this.analyticsConsent,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
        mealReminders: mealReminders ?? this.mealReminders,
      );

  Map<String, dynamic> toMap() => {
        'reduceMotion': reduceMotion,
        'textScale': textScale,
        'voiceGuidance': voiceGuidance,
        'language': language,
        'aiProcessingConsent': aiProcessingConsent,
        'allowOptionalAiProvider': allowOptionalAiProvider,
        'analyticsConsent': analyticsConsent,
        'quietHoursStart': quietHoursStart,
        'quietHoursEnd': quietHoursEnd,
        'mealReminders': mealReminders,
      };

  static AppSettings fromMap(Map<String, dynamic>? m) {
    if (m == null) return const AppSettings();
    return AppSettings(
      reduceMotion: m['reduceMotion'] as bool? ?? false,
      textScale: (m['textScale'] as num?)?.toDouble() ?? 1.0,
      voiceGuidance: m['voiceGuidance'] as bool? ?? true,
      language: m['language'] as String? ?? 'en-CA',
      aiProcessingConsent: m['aiProcessingConsent'] as bool? ?? false,
      allowOptionalAiProvider: m['allowOptionalAiProvider'] as bool? ?? true,
      analyticsConsent: m['analyticsConsent'] as bool? ?? false,
      quietHoursStart: readInt(m, 'quietHoursStart', 22),
      quietHoursEnd: readInt(m, 'quietHoursEnd', 7),
      mealReminders: readMap(m['mealReminders']).map((k, v) => MapEntry(k, v as String)),
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.createdAt,
    this.email,
    this.householdId,
    this.onboardingComplete = false,
    this.onboardingStep = 0,
    this.culinary = const CulinaryPreferences(),
    this.isProfessional = false,
    this.termsAcceptedVersion,
  });

  final String uid;
  final String displayName;
  final String? email;
  final String? householdId;
  final bool onboardingComplete;
  final int onboardingStep;
  final CulinaryPreferences culinary;
  final bool isProfessional;
  final String? termsAcceptedVersion;
  final DateTime createdAt;

  String get firstName => displayName.trim().split(RegExp(r'\s+')).first;

  UserProfile copyWith({
    String? displayName,
    String? householdId,
    bool? onboardingComplete,
    int? onboardingStep,
    CulinaryPreferences? culinary,
    String? termsAcceptedVersion,
  }) =>
      UserProfile(
        uid: uid,
        displayName: displayName ?? this.displayName,
        email: email,
        householdId: householdId ?? this.householdId,
        onboardingComplete: onboardingComplete ?? this.onboardingComplete,
        onboardingStep: onboardingStep ?? this.onboardingStep,
        culinary: culinary ?? this.culinary,
        isProfessional: isProfessional,
        termsAcceptedVersion: termsAcceptedVersion ?? this.termsAcceptedVersion,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        if (email != null) 'email': email,
        if (householdId != null) 'householdId': householdId,
        'onboardingComplete': onboardingComplete,
        'onboardingStep': onboardingStep,
        'culinary': culinary.toMap(),
        'isProfessional': isProfessional,
        if (termsAcceptedVersion != null) 'termsAcceptedVersion': termsAcceptedVersion,
        'createdAt': createdAt,
      };

  static UserProfile fromMap(String uid, Map<String, dynamic> m) => UserProfile(
        uid: uid,
        displayName: readString(m, 'displayName', ''),
        email: m['email'] as String?,
        householdId: m['householdId'] as String?,
        onboardingComplete: m['onboardingComplete'] as bool? ?? false,
        onboardingStep: readInt(m, 'onboardingStep', 0),
        culinary: CulinaryPreferences.fromMap(m['culinary'] == null ? null : readMap(m['culinary'])),
        isProfessional: m['isProfessional'] as bool? ?? false,
        termsAcceptedVersion: m['termsAcceptedVersion'] as String?,
        createdAt: readDate(m['createdAt']),
      );
}

enum HouseholdRole { owner, adult, member }

class HouseholdMember {
  const HouseholdMember({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.sharedAllergens = const [],
  });

  final String uid;
  final String displayName;
  final HouseholdRole role;
  final DateTime joinedAt;

  /// Allergens this member chose to share with the household for cooking
  /// safety. Nothing else about their health is visible to others.
  final List<String> sharedAllergens;

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'role': role.name,
        'joinedAt': joinedAt,
        'sharedAllergens': sharedAllergens,
      };

  static HouseholdMember fromMap(String uid, Map<String, dynamic> m) => HouseholdMember(
        uid: uid,
        displayName: readString(m, 'displayName', ''),
        role: readEnum(HouseholdRole.values, m['role'], HouseholdRole.member),
        joinedAt: readDate(m['joinedAt']),
        sharedAllergens: readStrings(m['sharedAllergens']),
      );
}

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.type,
    required this.portions,
    required this.ownerUid,
    required this.memberUids,
    required this.createdAt,
  });

  final String id;
  final String name;
  final HouseholdType type;
  final int portions;
  final String ownerUid;

  /// Mirrors the members subcollection for security-rule lookups.
  final List<String> memberUids;
  final DateTime createdAt;

  Household copyWith({String? name, HouseholdType? type, int? portions, List<String>? memberUids}) => Household(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        portions: portions ?? this.portions,
        ownerUid: ownerUid,
        memberUids: memberUids ?? this.memberUids,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'type': type.name,
        'portions': portions,
        'ownerUid': ownerUid,
        'memberUids': memberUids,
        'createdAt': createdAt,
      };

  static Household fromMap(String id, Map<String, dynamic> m) => Household(
        id: id,
        name: readString(m, 'name', 'Our kitchen'),
        type: readEnum(HouseholdType.values, m['type'], HouseholdType.single),
        portions: readInt(m, 'portions', 2),
        ownerUid: readString(m, 'ownerUid'),
        memberUids: readStrings(m['memberUids']),
        createdAt: readDate(m['createdAt']),
      );
}

class ConsentRecord {
  const ConsentRecord({
    required this.id,
    required this.purpose,
    required this.granted,
    required this.version,
    required this.recordedAt,
    this.text,
  });

  final String id;

  /// e.g. 'terms', 'privacy', 'ai_processing', 'diabetes_features', `share:{grantId}`.
  final String purpose;
  final bool granted;
  final String version;
  final DateTime recordedAt;
  final String? text;

  Map<String, dynamic> toMap() => {
        'purpose': purpose,
        'granted': granted,
        'version': version,
        'recordedAt': recordedAt,
        if (text != null) 'text': text,
      };

  static ConsentRecord fromMap(String id, Map<String, dynamic> m) => ConsentRecord(
        id: id,
        purpose: readString(m, 'purpose'),
        granted: m['granted'] as bool? ?? false,
        version: readString(m, 'version', '1'),
        recordedAt: readDate(m['recordedAt']),
        text: m['text'] as String?,
      );
}
