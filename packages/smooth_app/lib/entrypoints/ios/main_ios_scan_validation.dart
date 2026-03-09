import 'package:app_store_apple_store/app_store_apple.dart';
import 'package:scanner_zxing/scanner_zxing.dart';
import 'package:smooth_app/helpers/entry_points_helper.dart';
import 'package:smooth_app/main.dart';

/// Entrypoint that runs scan span validation (4a.5 error, 4a.6 timeout)
/// on startup, then launches the app normally.
///
/// Usage:
///   flutter run -t lib/entrypoints/ios/main_ios_scan_validation.dart
void main() {
  launchSmoothApp(
    barcodeScanner: const ScannerZXing(),
    appStore: AppleAppStore('588797948'),
    storeLabel: StoreLabel.AppleAppStore,
    scannerLabel: ScannerLabel.ZXing,
    onPostInit: validateScanSpanPaths,
  );
}
