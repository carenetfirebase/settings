import '../units/units.dart';
import 'codec.dart';
import 'inventory.dart';
import 'recipe.dart';

class MealPlanEntry {
  const MealPlanEntry({
    required this.id,
    required this.householdId,
    required this.date,
    required this.mealType,
    required this.recipeId,
    required this.recipeTitle,
    required this.portions,
    required this.createdBy,
    this.recipeSnapshot,
    this.cooked = false,
    this.fromLeftoverLotId,
  });

  final String id;
  final String householdId;
  final CalendarDate date;
  final MealType mealType;
  final String recipeId;
  final String recipeTitle;
  final int portions;
  final String createdBy;

  /// Copy of the recipe at planning time, so plans survive catalogue edits.
  final Recipe? recipeSnapshot;
  final bool cooked;
  final String? fromLeftoverLotId;

  MealPlanEntry copyWith({CalendarDate? date, MealType? mealType, int? portions, bool? cooked}) => MealPlanEntry(
        id: id,
        householdId: householdId,
        date: date ?? this.date,
        mealType: mealType ?? this.mealType,
        recipeId: recipeId,
        recipeTitle: recipeTitle,
        portions: portions ?? this.portions,
        createdBy: createdBy,
        recipeSnapshot: recipeSnapshot,
        cooked: cooked ?? this.cooked,
        fromLeftoverLotId: fromLeftoverLotId,
      );

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'date': date.toIso(),
        'mealType': mealType.name,
        'recipeId': recipeId,
        'recipeTitle': recipeTitle,
        'portions': portions,
        'createdBy': createdBy,
        if (recipeSnapshot != null) 'recipeSnapshot': recipeSnapshot!.toMap(),
        'cooked': cooked,
        if (fromLeftoverLotId != null) 'fromLeftoverLotId': fromLeftoverLotId,
      };

  static MealPlanEntry fromMap(String id, Map<String, dynamic> m) => MealPlanEntry(
        id: id,
        householdId: readString(m, 'householdId'),
        date: CalendarDate.parse(readString(m, 'date')),
        mealType: readEnum(MealType.values, m['mealType'], MealType.dinner),
        recipeId: readString(m, 'recipeId'),
        recipeTitle: readString(m, 'recipeTitle'),
        portions: readInt(m, 'portions', 2),
        createdBy: readString(m, 'createdBy', ''),
        recipeSnapshot: m['recipeSnapshot'] == null ? null : Recipe.fromMap(readString(m, 'recipeId'), readMap(m['recipeSnapshot'])),
        cooked: m['cooked'] as bool? ?? false,
        fromLeftoverLotId: m['fromLeftoverLotId'] as String?,
      );
}

enum ShoppingReason { manual, missingForPlan, lowStock, missingForRecipe }

class ShoppingItem {
  const ShoppingItem({
    required this.id,
    required this.householdId,
    required this.name,
    required this.category,
    required this.reason,
    required this.createdAt,
    this.productId,
    this.quantity,
    this.preferredProduct,
    this.note,
    this.checked = false,
    this.forRecipeTitles = const [],
    this.estimatedPrice,
  });

  final String id;
  final String householdId;
  final String name;
  final FoodCategory category;
  final ShoppingReason reason;
  final DateTime createdAt;
  final String? productId;
  final Quantity? quantity;
  final String? preferredProduct;
  final String? note;
  final bool checked;
  final List<String> forRecipeTitles;
  final Money? estimatedPrice;

  ShoppingItem copyWith({
    String? name,
    FoodCategory? category,
    Quantity? quantity,
    String? preferredProduct,
    String? note,
    bool? checked,
    Money? estimatedPrice,
  }) =>
      ShoppingItem(
        id: id,
        householdId: householdId,
        name: name ?? this.name,
        category: category ?? this.category,
        reason: reason,
        createdAt: createdAt,
        productId: productId,
        quantity: quantity ?? this.quantity,
        preferredProduct: preferredProduct ?? this.preferredProduct,
        note: note ?? this.note,
        checked: checked ?? this.checked,
        forRecipeTitles: forRecipeTitles,
        estimatedPrice: estimatedPrice ?? this.estimatedPrice,
      );

  Map<String, dynamic> toMap() => {
        'householdId': householdId,
        'name': name,
        'nameLower': name.toLowerCase(),
        'category': category.name,
        'reason': reason.name,
        'createdAt': createdAt,
        if (productId != null) 'productId': productId,
        if (quantity != null) 'quantity': quantity!.toMap(),
        if (preferredProduct != null) 'preferredProduct': preferredProduct,
        if (note != null) 'note': note,
        'checked': checked,
        'forRecipeTitles': forRecipeTitles,
        if (estimatedPrice != null) 'estimatedPrice': estimatedPrice!.toMap(),
      };

  static ShoppingItem fromMap(String id, Map<String, dynamic> m) => ShoppingItem(
        id: id,
        householdId: readString(m, 'householdId'),
        name: readString(m, 'name'),
        category: readEnum(FoodCategory.values, m['category'], FoodCategory.other),
        reason: readEnum(ShoppingReason.values, m['reason'], ShoppingReason.manual),
        createdAt: readDate(m['createdAt']),
        productId: m['productId'] as String?,
        quantity: m['quantity'] == null ? null : Quantity.fromMap(readMap(m['quantity'])),
        preferredProduct: m['preferredProduct'] as String?,
        note: m['note'] as String?,
        checked: m['checked'] as bool? ?? false,
        forRecipeTitles: readStrings(m['forRecipeTitles']),
        estimatedPrice: Money.fromMap(m['estimatedPrice']),
      );
}

/// Weekday-based morning routine with explicit local times.
class MorningRoutine {
  const MorningRoutine({
    this.enabled = false,
    this.weekdays = const [1, 2, 3, 4, 5],
    this.wakeTime = '06:45',
    this.departureTime = '08:15',
    this.bufferMinutes = 10,
    this.breakfastStyle = 'quick',
    this.preferredRecipeIds = const [],
    this.alarmEnabled = false,
    this.eveningPreviewTime = '20:30',
    this.tomorrowRecipeId,
  });

  final bool enabled;

  /// ISO weekdays (1 = Monday).
  final List<int> weekdays;
  final String wakeTime;
  final String departureTime;
  final int bufferMinutes;

  /// 'quick', 'cooked', 'no_cook', 'grab_and_go'.
  final String breakfastStyle;
  final List<String> preferredRecipeIds;
  final bool alarmEnabled;
  final String eveningPreviewTime;
  final String? tomorrowRecipeId;

  int get availableMinutes {
    final w = _minutes(wakeTime);
    final d = _minutes(departureTime);
    final diff = d - w - bufferMinutes;
    return diff < 0 ? 0 : diff;
  }

  static int _minutes(String hhmm) {
    final p = hhmm.split(':').map(int.parse).toList();
    return p[0] * 60 + p[1];
  }

  MorningRoutine copyWith({
    bool? enabled,
    List<int>? weekdays,
    String? wakeTime,
    String? departureTime,
    int? bufferMinutes,
    String? breakfastStyle,
    bool? alarmEnabled,
    String? eveningPreviewTime,
    String? tomorrowRecipeId,
  }) =>
      MorningRoutine(
        enabled: enabled ?? this.enabled,
        weekdays: weekdays ?? this.weekdays,
        wakeTime: wakeTime ?? this.wakeTime,
        departureTime: departureTime ?? this.departureTime,
        bufferMinutes: bufferMinutes ?? this.bufferMinutes,
        breakfastStyle: breakfastStyle ?? this.breakfastStyle,
        preferredRecipeIds: preferredRecipeIds,
        alarmEnabled: alarmEnabled ?? this.alarmEnabled,
        eveningPreviewTime: eveningPreviewTime ?? this.eveningPreviewTime,
        tomorrowRecipeId: tomorrowRecipeId ?? this.tomorrowRecipeId,
      );

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'weekdays': weekdays,
        'wakeTime': wakeTime,
        'departureTime': departureTime,
        'bufferMinutes': bufferMinutes,
        'breakfastStyle': breakfastStyle,
        'preferredRecipeIds': preferredRecipeIds,
        'alarmEnabled': alarmEnabled,
        'eveningPreviewTime': eveningPreviewTime,
        if (tomorrowRecipeId != null) 'tomorrowRecipeId': tomorrowRecipeId,
      };

  static MorningRoutine fromMap(Map<String, dynamic>? m) {
    if (m == null) return const MorningRoutine();
    return MorningRoutine(
      enabled: m['enabled'] as bool? ?? false,
      weekdays: (m['weekdays'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [1, 2, 3, 4, 5],
      wakeTime: m['wakeTime'] as String? ?? '06:45',
      departureTime: m['departureTime'] as String? ?? '08:15',
      bufferMinutes: readInt(m, 'bufferMinutes', 10),
      breakfastStyle: m['breakfastStyle'] as String? ?? 'quick',
      preferredRecipeIds: readStrings(m['preferredRecipeIds']),
      alarmEnabled: m['alarmEnabled'] as bool? ?? false,
      eveningPreviewTime: m['eveningPreviewTime'] as String? ?? '20:30',
      tomorrowRecipeId: m['tomorrowRecipeId'] as String?,
    );
  }
}

enum NotificationKind { receipt, mealReminder, inventory, sharing, review, routine, system }

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.route,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// In-app deep link, e.g. '/kitchen/receipts/abc/review'.
  final String? route;

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'title': title,
        'body': body,
        'createdAt': createdAt,
        'read': read,
        if (route != null) 'route': route,
      };

  static AppNotification fromMap(String id, Map<String, dynamic> m) => AppNotification(
        id: id,
        kind: readEnum(NotificationKind.values, m['kind'], NotificationKind.system),
        title: readString(m, 'title'),
        body: readString(m, 'body', ''),
        createdAt: readDate(m['createdAt']),
        read: m['read'] as bool? ?? false,
        route: m['route'] as String?,
      );
}
