import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// ماسح QR/Barcode عام يعمل على Android وiOS والويب عند منح إذن الكاميرا.
class WaslQrScannerPage extends StatefulWidget {
  const WaslQrScannerPage({
    super.key,
    this.title = 'مسح الباركود',
    this.instruction = 'وجّه الكاميرا نحو الباركود حتى تتم قراءته تلقائيًا.',
    this.qrOnly = false,
    this.cameraPreviewBuilder,
  });

  final String title;
  final String instruction;
  final bool qrOnly;
  final WidgetBuilder? cameraPreviewBuilder;

  @override
  State<WaslQrScannerPage> createState() => _WaslQrScannerPageState();
}

class _WaslQrScannerPageState extends State<WaslQrScannerPage> {
  MobileScannerController? _controller;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    if (widget.cameraPreviewBuilder == null) {
      _controller = MobileScannerController(
        formats: widget.qrOnly
            ? const [BarcodeFormat.qrCode]
            : const [
                BarcodeFormat.qrCode,
                BarcodeFormat.code128,
                BarcodeFormat.code39,
                BarcodeFormat.ean13,
                BarcodeFormat.ean8,
                BarcodeFormat.upcA,
                BarcodeFormat.upcE,
              ],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  Future<void> _detected(BarcodeCapture capture) async {
    if (_accepted) return;
    String? value;
    for (final barcode in capture.barcodes) {
      final candidate = barcode.rawValue?.trim() ?? '';
      if (candidate.isNotEmpty) {
        value = candidate;
        break;
      }
    }
    if (value == null || !mounted) return;
    _accepted = true;
    await _controller!.stop();
    if (mounted) Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: const Color(0xFF08294D),
      foregroundColor: Colors.white,
      title: Text(widget.title),
      actions: [
        IconButton(
          onPressed: _controller?.toggleTorch,
          tooltip: 'تشغيل الإضاءة',
          icon: const Icon(Icons.flashlight_on_outlined),
        ),
        IconButton(
          onPressed: _controller?.switchCamera,
          tooltip: 'تبديل الكاميرا',
          icon: const Icon(Icons.cameraswitch_outlined),
        ),
      ],
    ),
    body: Stack(
      fit: StackFit.expand,
      children: [
        if (widget.cameraPreviewBuilder != null)
          widget.cameraPreviewBuilder!(context)
        else
          MobileScanner(
            controller: _controller!,
            onDetect: _detected,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'تعذر تشغيل الكاميرا. تأكد من منح إذن الكاميرا ثم أعد المحاولة.\n$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        Center(
          child: Container(
            width: 245,
            height: 245,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF10C5A7), width: 4),
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Color(0x6610C5A7), blurRadius: 22),
              ],
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 38,
          child: Card(
            color: const Color(0xEE08294D),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFF10C5A7)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                widget.instruction,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
