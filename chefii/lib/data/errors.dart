// Stable codes for user-facing errors raised below the UI.
//
// The data layer has no BuildContext, so its exceptions carry an
// [AppErrorCode] plus parameters. The UI translates them with
// `ErrorState.describeIn(context, error)` (lib/core/design/components/
// states.dart). The exceptions' `message` stays in English for logs and for
// code that has not moved to `describeIn` yet.

/// Every user-facing error the data and app layers can raise.
///
/// Parameters (in `CodedError.args`) are noted per value.
enum AppErrorCode {
  // Inventory
  inventoryPlaceNameLength,
  inventoryPlaceNameTaken, // name: String
  inventoryPlaceLimit,
  inventoryBuiltInRename,
  inventoryBuiltInRemove,
  inventoryPlaceNotEmpty,
  inventoryNothingToAdd,
  inventoryQuantityNotPositive, // product: String
  inventoryNothingToDeduct,
  inventoryNothingToCorrect,
  inventoryNegativeCount,
  inventoryItemGone,
  inventoryWrongUnit, // product: String, unit: Unit
  inventoryNothingToUndo,
  inventoryAlreadyUndone,
  inventoryUndoOfUndo,
  inventoryProductNotRecorded, // product: String

  // Receipts
  receiptNotFound,
  receiptNotEditable,
  receiptNotReady,
  receiptLinesIncomplete, // count: int
  receiptNoFoodItems,
  receiptNoPhotos,
  receiptTooManyPages, // max: int
  receiptImageEmpty,
  receiptImageTooLarge,
  receiptImageFormat,
  receiptDuplicate,

  // AI
  aiUnavailable, // detail: String? (server message, English)

  // Auth
  notSignedIn,
  authCredentialMismatch,
  authEmailInUse,
  authWeakPassword,
  authInvalidEmail,
  authOffline,
  authTooManyRequests,
  authRecentLoginRequired,
  authCancelled,
  authFailed, // detail: String? (provider message, English)
  authFailedRetry,
  authNoGoogleToken,
  authSignInAgain,
  authPasswordRequired,
  authAppleNeedsFirebase,
  authGoogleNeedsFirebase,

  // Household and sharing
  householdOwnerNotRemovable,
  sharingProfessionalNotVerified,
  sharingNoCategories,
  sharingNoActivePermission, // category: ShareCategory
}

/// An error the UI can translate from [code] and [args].
abstract interface class CodedError {
  AppErrorCode? get code;
  Map<String, Object?> get args;
}

/// A [StateError] with a translatable [code].
class CodedStateError extends StateError implements CodedError {
  CodedStateError(super.message, this.code, [this.args = const {}]);
  @override
  final AppErrorCode code;
  @override
  final Map<String, Object?> args;
}

/// An [ArgumentError] with a translatable [code].
class CodedArgumentError extends ArgumentError implements CodedError {
  CodedArgumentError(String super.message, this.code, [this.args = const {}]);
  @override
  final AppErrorCode code;
  @override
  final Map<String, Object?> args;
}
