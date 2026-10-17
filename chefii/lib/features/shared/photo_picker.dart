import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/actions.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../l10n/l10n.dart';

class PhotoPermissionDenied implements Exception {}

/// Picks one photo, downscaled for upload. Returns null if cancelled.
/// Throws [PhotoPermissionDenied] when camera/photo access is refused.
Future<ReceiptPage?> pickPhoto({required bool camera, double maxWidth = 2200}) async {
  try {
    final file = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxWidth,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final mime = ReceiptImageRules.sniffMime(bytes) ?? file.mimeType ?? 'image/jpeg';
    return ReceiptPage(bytes, mime);
  } on PlatformException catch (e) {
    if (e.code.contains('access_denied') || e.code.contains('permission')) throw PhotoPermissionDenied();
    rethrow;
  }
}

/// Bottom sheet: camera or library.
Future<bool?> chooseCameraOrLibrary(BuildContext context) => showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(ctx.l10n.sharedTakePhoto), onTap: () => Navigator.pop(ctx, true)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(ctx.l10n.sharedChooseFromLibrary), onTap: () => Navigator.pop(ctx, false)),
          const SizedBox(height: 8),
        ]),
      ),
    );
