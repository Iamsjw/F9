import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class BleAdvertisementData {
  final String sessionId;
  final int rssi;
  final String deviceId;

  const BleAdvertisementData({
    required this.sessionId,
    required this.rssi,
    required this.deviceId,
  });
}

class BleService {
  static const MethodChannel _settingsChannel =
      MethodChannel('com.example.upasthitix/settings');

  static StreamSubscription<List<ScanResult>>? _scanSubscription;
  static Timer? _scanTimer;
  static final List<int> _rssiSamples = [];
  static bool _isAdvertising = false;

  // Common service UUID for cross-platform BLE advertising/scanning.
  static const String upasthitixServiceUuid =
      "19B10000-E8F2-537E-4F6C-D104768A1214";

  static Future<bool> enableBluetooth() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) {
        await FlutterBluePlus.turnOn();
        return await isBluetoothOn();
      } else {
        await openAppSettings();
        return await isBluetoothOn();
      }
    } catch (e) {
      debugPrint('[BLE] Failed to turn on Bluetooth: $e');
      return false;
    }
  }

  static Future<void> openLocationSettings() async {
    try {
      if (Platform.isAndroid) {
        await _settingsChannel.invokeMethod('openLocationSettings');
      } else {
        await openAppSettings();
      }
    } catch (e) {
      debugPrint('[BLE] Failed to open location settings: $e');
      await openAppSettings();
    }
  }

  // ---- Permissions ------------------------------------------------

  /// Checks if system-level location services (GPS) are enabled.
  /// Required for BLE scanning on Android 6-11 even when permission is granted.
  static Future<bool> isLocationEnabled() async {
    if (kIsWeb || Platform.isIOS) return true;
    try {
      return await Permission.locationWhenInUse.serviceStatus.isEnabled;
    } catch (_) {
      return true; // assume OK if check fails
    }
  }

  /// Request a single permission safely — returns its status.
  static Future<PermissionStatus> _requestOne(Permission p) async {
    try {
      return await p.request();
    } catch (e) {
      debugPrint('[BLE] Failed to request ${p.toString()}: $e');
      return PermissionStatus.denied;
    }
  }

  /// Check a single permission status safely.
  static Future<PermissionStatus> _checkOne(Permission p) async {
    try {
      return await p.status;
    } catch (e) {
      debugPrint('[BLE] Failed to check ${p.toString()}: $e');
      return PermissionStatus.denied;
    }
  }

  static Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 31) {
          try {
            await _requestOne(Permission.bluetoothScan);
          } catch (_) {}
          try {
            await _requestOne(Permission.bluetoothConnect);
          } catch (_) {}
          try {
            await _requestOne(Permission.bluetoothAdvertise);
          } catch (_) {}

          final btScan = await _checkOne(Permission.bluetoothScan);
          final btConnect = await _checkOne(Permission.bluetoothConnect);
          final btAdvertise = await _checkOne(Permission.bluetoothAdvertise);

          final allGranted = btScan.isGranted && btConnect.isGranted && btAdvertise.isGranted;
          debugPrint('[BLE] Android 12+ permissions: btScan=$btScan btConnect=$btConnect btAdvertise=$btAdvertise -> $allGranted');
          return allGranted;
        } else {
          await _requestOne(Permission.locationWhenInUse);
          try {
            await _requestOne(Permission.location);
          } catch (_) {}

          final locStatus = await _checkOne(Permission.locationWhenInUse);
          debugPrint('[BLE] Android <12 permissions: loc=$locStatus -> ${locStatus.isGranted}');
          return locStatus.isGranted;
        }
      }

      // iOS / others
      final results = await Future.wait([
        _requestOne(Permission.bluetoothScan),
        _requestOne(Permission.bluetoothConnect),
        _requestOne(Permission.locationWhenInUse),
      ]);
      final allGranted = results.every((s) => s.isGranted);
      debugPrint('[BLE] iOS/other permissions: $results -> granted=$allGranted');
      return allGranted;
    } catch (e) {
      debugPrint('[BLE] Permission request failed: $e');
      return false;
    }
  }

  static Future<bool> hasPermissions() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 31) {
          final btScan = await _checkOne(Permission.bluetoothScan);
          final btConnect = await _checkOne(Permission.bluetoothConnect);
          final btAdvertise = await _checkOne(Permission.bluetoothAdvertise);
          return btScan.isGranted && btConnect.isGranted && btAdvertise.isGranted;
        } else {
          final loc = await _checkOne(Permission.locationWhenInUse);
          return loc.isGranted;
        }
      }
      final results = await Future.wait([
        _checkOne(Permission.bluetoothScan),
        _checkOne(Permission.bluetoothConnect),
        _checkOne(Permission.locationWhenInUse),
      ]);
      return results.every((s) => s.isGranted);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isBluetoothOn() async {
    if (kIsWeb) return false;
    try {
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  // ---- Teacher: BLE Advertising ----------------------------------------

  static bool get isAdvertising => _isAdvertising;

  static Future<bool> isPeripheralSupported() async {
    if (kIsWeb) return false;
    try {
      return await FlutterBlePeripheral().isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Start advertising using manufacturerData + serviceUuid for maximum device compatibility.
  /// The serviceUuid is used as a scan filter target for reliable discovery.
  static Future<bool> startAdvertising(String sessionId) async {
    if (kIsWeb) {
      debugPrint('[BLE] Web not supported');
      return false;
    }

    // Stop any ongoing scan that might conflict
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    // Step 1: Check Bluetooth
    debugPrint('[BLE] Checking Bluetooth state...');
    final isOn = await isBluetoothOn();
    debugPrint('[BLE] Bluetooth isOn=$isOn');
    if (!isOn) {
      debugPrint('[BLE] Cannot advertise: Bluetooth is off');
      return false;
    }

    // Step 2: Check peripheral support
    debugPrint('[BLE] Checking peripheral support...');
    try {
      final supported = await isPeripheralSupported();
      debugPrint('[BLE] Peripheral supported=$supported');
      if (!supported) {
        debugPrint('[BLE] Peripheral mode not supported on this device');
        return false;
      }
    } catch (e) {
      debugPrint('[BLE] Error checking peripheral support: $e');
      return false;
    }

    // Step 3: Build advertising data with serviceUuid for reliable scanning
    try {
      final prefix = sessionId.length >= 8
          ? sessionId.substring(0, 8)
          : sessionId;
      debugPrint('[BLE] Advertising prefix: $prefix');
      final prefixBytes = utf8.encode(prefix);

      // Android: use manufacturerData + serviceUuid for reliable scanning on all devices.
      // The serviceUuid serves as a scan filter target for devices like Vivo/iQOO.
      // iOS: use serviceData with the serviceUuid.
      final advertiseData = Platform.isIOS
          ? AdvertiseData(
              serviceUuid: upasthitixServiceUuid,
              serviceData: Uint8List.fromList(prefixBytes),
              includeDeviceName: false,
            )
          : AdvertiseData(
              manufacturerId: 0x1234,
              manufacturerData: Uint8List.fromList(prefixBytes),
              serviceUuid: upasthitixServiceUuid,
              includeDeviceName: false,
            );

      final settings = AdvertiseSettings(
        // advertiseSet: false → legacy advertising mode for OEM compatibility.
        advertiseSet: false,
        advertiseMode: AdvertiseMode.advertiseModeLowLatency,
        txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
        connectable: false,
        timeout: 0,
      );

      debugPrint('[BLE] Calling FlutterBlePeripheral().start()...');
      await FlutterBlePeripheral().start(
        advertiseData: advertiseData,
        advertiseSettings: settings,
      );
      debugPrint('[BLE] FlutterBlePeripheral().start() returned');

      // Give it a moment, then verify
      await Future.delayed(const Duration(milliseconds: 800));
      final advertising = await FlutterBlePeripheral().isAdvertising;
      debugPrint('[BLE] isAdvertising after start: $advertising');

      if (!advertising) {
        debugPrint('[BLE] Warning: isAdvertising is false after start()');
        await Future.delayed(const Duration(seconds: 1));
        final retry = await FlutterBlePeripheral().isAdvertising;
        debugPrint('[BLE] Retry isAdvertising: $retry');
        if (!retry) {
          _isAdvertising = false;
          return false;
        }
      }

      _isAdvertising = true;
      debugPrint(
        '[BLE] Started advertising session: $sessionId (prefix: $prefix)',
      );
      return true;
    } catch (e, stackTrace) {
      debugPrint('[BLE] Failed to start advertising: $e');
      debugPrint('[BLE] Stack trace: $stackTrace');
      return false;
    }
  }

  static Future<void> stopAdvertising() async {
    try {
      await FlutterBlePeripheral().stop();
      debugPrint('[BLE] FlutterBlePeripheral().stop() succeeded');
    } catch (e) {
      debugPrint('[BLE] Error stopping advertising: $e');
    }
    _isAdvertising = false;
    debugPrint('[BLE] Stopped advertising');
  }

  // ---- Student: BLE Scanning -------------------------------------------

  static Future<BleAdvertisementData?> scanForSession({
    required String sessionId,
    required int timeoutSeconds,
    required int rssiThreshold,
    void Function(int rssi)? onRssiUpdate,
  }) async {
    if (kIsWeb) return null;

    final isOn = await isBluetoothOn();
    if (!isOn) return null;

    // Check & request permissions if needed
    if (!await hasPermissions()) {
      debugPrint('[BLE] Permissions not granted, requesting...');
      if (!await requestPermissions()) {
        debugPrint('[BLE] Permission request failed or denied');
        return null;
      }
    }

    // On Android, verify location services are ON (required for BLE scan on API < 31)
    if (Platform.isAndroid) {
      final locEnabled = await isLocationEnabled();
      if (!locEnabled) {
        debugPrint('[BLE] Location services are OFF — BLE scan will not work');
        return null;
      }
    }

    _rssiSamples.clear();
    final completer = Completer<BleAdvertisementData?>();

    // ─── Dual-phase scan strategy (4-second Phase 1 window) ──────────────────
    //
    // Phase 1 — Hardware Filtered scan (4 seconds):
    //   Passes a service-UUID filter to the OS. On Android, this routes to the
    //   HCI hardware scanner, providing reliable scan callbacks for Vivo, Oppo,
    //   Realme, and Xiaomi devices without OS software throttling.
    //
    // Phase 2 — Unfiltered fallback (remaining timeout):
    //   If hardware filtering didn't return a packet within 4 seconds, Phase 2
    //   takes over so students never wait 8-10+ seconds.
    // ─────────────────────────────────────────────────────────────────────────
    final filteredSecs = 4;
    final fallbackSecs = timeoutSeconds - filteredSecs;
    Timer? phase2Timer;

    void processResults(List<ScanResult> results) {
      for (final result in results) {
        final matched = _isTargetSession(result, sessionId);
        if (matched) {
          final rssi = result.rssi;
          _rssiSamples.add(rssi);
          onRssiUpdate?.call(rssi);

          if (_rssiSamples.length >= 2) {
            final avgRssi =
                _rssiSamples.reduce((a, b) => a + b) ~/ _rssiSamples.length;
            if (!completer.isCompleted) {
              completer.complete(
                BleAdvertisementData(
                  sessionId: sessionId,
                  rssi: avgRssi,
                  deviceId: result.device.remoteId.str,
                ),
              );
            }
          }
        }
      }
    }

    try {
      // ── Phase 1: filtered ──────────────────────────────────────────────────
      debugPrint('[BLE] Phase 1: filtered scan for session: $sessionId '
          '(${filteredSecs}s)');
      final serviceFilter = Platform.isAndroid
          ? [Guid(upasthitixServiceUuid)]
          : <Guid>[];
      await FlutterBluePlus.startScan(
        timeout: Duration(seconds: filteredSecs),
        androidScanMode: AndroidScanMode.lowLatency,
        withServices: serviceFilter,
      );

      _scanSubscription =
          FlutterBluePlus.scanResults.listen(processResults);

      // ── Phase 2: unfiltered fallback ───────────────────────────────────────
      phase2Timer = Timer(Duration(seconds: filteredSecs), () async {
        if (completer.isCompleted) return;
        debugPrint('[BLE] Phase 2: switching to unfiltered fallback '
            '(${fallbackSecs}s)...');
        try {
          await FlutterBluePlus.stopScan();
          await Future.delayed(const Duration(milliseconds: 150));
          // Re-use the same _scanSubscription — scanResults stream
          // continues to emit during the new scan automatically.
          await FlutterBluePlus.startScan(
            timeout: Duration(seconds: fallbackSecs),
            androidScanMode: AndroidScanMode.lowLatency,
            // No withServices filter — catches everything
          );
        } catch (e) {
          debugPrint('[BLE] Phase 2 start error: $e');
        }
      });

      // Overall hard timeout (phase durations + small buffer)
      _scanTimer = Timer(Duration(seconds: timeoutSeconds + 2), () {
        if (!completer.isCompleted) {
          debugPrint('[BLE] Scan timed out after $timeoutSeconds seconds');
          completer.complete(null);
        }
      });

      final result = await completer.future;
      phase2Timer.cancel();
      await _stopScan();
      return result;
    } catch (e) {
      debugPrint('[BLE] Scan error: $e');
      phase2Timer?.cancel();
      await _stopScan();
      return null;
    }
  }

  /// Checks whether a scan result matches the target session.
  /// Uses multiple strategies for maximum reliability:
  /// (1) raw byte comparison, (2) UTF-8 string matching,
  /// (3) serviceData matching, (4) device name matching.
  static bool _isTargetSession(ScanResult result, String sessionId) {
    try {
      final prefix = sessionId.length >= 8
          ? sessionId.substring(0, 8)
          : sessionId;
      final prefixBytes = utf8.encode(prefix);

      // Check manufacturerData (primary method with flutter_ble_peripheral on Android)
      final mfgData = result.advertisementData.manufacturerData;
      for (final entry in mfgData.entries) {
        final value = entry.value;
        // Try raw byte comparison first (most reliable across devices)
        if (value.length >= prefixBytes.length) {
          bool match = true;
          for (int i = 0; i < prefixBytes.length; i++) {
            if (value[i] != prefixBytes[i]) {
              match = false;
              break;
            }
          }
          if (match) {
            debugPrint('[BLE] Matched via manufacturerData raw bytes: $prefix');
            return true;
          }
        }
        // Fallback to UTF-8 decode
        final decoded = utf8.decode(value, allowMalformed: true);
        if (decoded.contains(prefix)) {
          debugPrint('[BLE] Matched via manufacturerData UTF-8: $prefix');
          return true;
        }
      }

      // Check serviceData (used on iOS, and now also on Android)
      final svcData = result.advertisementData.serviceData;
      for (final entry in svcData.entries) {
        final value = entry.value;
        if (value.length >= prefixBytes.length) {
          bool match = true;
          for (int i = 0; i < prefixBytes.length; i++) {
            if (value[i] != prefixBytes[i]) {
              match = false;
              break;
            }
          }
          if (match) {
            debugPrint('[BLE] Matched via serviceData raw bytes: $prefix');
            return true;
          }
        }
        final decoded = utf8.decode(value, allowMalformed: true);
        if (decoded.contains(prefix)) {
          debugPrint('[BLE] Matched via serviceData UTF-8: $prefix');
          return true;
        }
      }

      // Fallback: match by device name
      final name = result.device.platformName;
      final advName = result.advertisementData.advName;
      final targetName = 'UX_$prefix';

      if (name.contains(targetName) ||
          advName.contains(targetName) ||
          name.contains('Upasthitix') ||
          advName.contains('Upasthitix')) {
        debugPrint('[BLE] Matched via device name: $targetName');
        return true;
      }

      // Extra debug: log nearby devices for troubleshooting
      if (result.rssi > -90) {
        debugPrint(
          '[BLE] Nearby device not matched - '
          'name: ${result.device.platformName}, '
          'rssi: ${result.rssi}, '
          'mfgIds: ${result.advertisementData.manufacturerData.keys.toList()}, '
          'svcUuids: ${result.advertisementData.serviceUuids}',
        );
      }
    } catch (e) {
      debugPrint('[BLE] Error matching session: $e');
    }
    return false;
  }

  static Future<void> _stopScan() async {
    try {
      _scanTimer?.cancel();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  static Future<void> dispose() async {
    await _stopScan();
    await stopAdvertising();
  }

  // ---- RSSI signal quality -------------------------------------------

  static String rssiQualityLabel(int rssi) {
    if (rssi >= -65) return 'Excellent';
    if (rssi >= -78) return 'Good';
    if (rssi >= -88) return 'Fair';
    if (rssi >= -95) return 'Weak';
    return 'Very Weak';
  }

  static double rssiQualityPercent(int rssi) {
    return ((rssi + 100) / 50).clamp(0.0, 1.0);
  }
}
