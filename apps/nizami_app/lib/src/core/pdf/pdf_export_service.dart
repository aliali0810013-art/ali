import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

/// Unified PDF export for web, Android and desktop.
class PdfExportService {
  const PdfExportService._();

  static bool get _desktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  static Future<void> save({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (_desktop) {
      final location = await getSaveLocation(
        suggestedName: filename,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF', extensions: ['pdf']),
        ],
      );
      if (location == null) return;
      await XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: filename,
      ).saveTo(location.path);
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static Future<void> share({
    required Uint8List bytes,
    required String filename,
  }) => Printing.sharePdf(bytes: bytes, filename: filename);

  static Future<void> print({
    required Uint8List bytes,
    required String filename,
  }) => Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
}
