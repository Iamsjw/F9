import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/ble_service.dart';

class SystemSetupDisclaimer extends StatefulWidget {
  final bool permissionsGranted;
  final bool bluetoothOn;
  final bool locationServicesEnabled;
  final VoidCallback onRefresh;

  const SystemSetupDisclaimer({
    super.key,
    required this.permissionsGranted,
    required this.bluetoothOn,
    required this.locationServicesEnabled,
    required this.onRefresh,
  });

  @override
  State<SystemSetupDisclaimer> createState() => _SystemSetupDisclaimerState();
}

class _SystemSetupDisclaimerState extends State<SystemSetupDisclaimer> {
  bool _isFixingPermissions = false;
  bool _isFixingBluetooth = false;
  bool _isFixingLocation = false;
  Timer? _autoCheckTimer;

  @override
  void initState() {
    super.initState();
    _startAutoCheck();
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  void _startAutoCheck() {
    // Periodically run check in the background to dismiss immediately when enabled
    _autoCheckTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (mounted) {
        widget.onRefresh();
      }
    });
  }

  Future<void> _handlePermissionsFix() async {
    setState(() => _isFixingPermissions = true);
    try {
      await BleService.requestPermissions();
    } finally {
      if (mounted) {
        setState(() => _isFixingPermissions = false);
        widget.onRefresh();
      }
    }
  }

  Future<void> _handleBluetoothFix() async {
    setState(() => _isFixingBluetooth = true);
    try {
      await BleService.enableBluetooth();
    } finally {
      if (mounted) {
        setState(() => _isFixingBluetooth = false);
        widget.onRefresh();
      }
    }
  }

  Future<void> _handleLocationFix() async {
    setState(() => _isFixingLocation = true);
    try {
      await BleService.openLocationSettings();
    } finally {
      if (mounted) {
        setState(() => _isFixingLocation = false);
        widget.onRefresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allOk = widget.permissionsGranted &&
        widget.bluetoothOn &&
        widget.locationServicesEnabled;

    if (allOk) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E193F).withOpacity(0.6), // deep premium glass color
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sleek, minimal header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.sensors_rounded,
                  color: AppTheme.warning,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verification Status Required',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Tap items marked with a bolt to enable attendance scanning.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Horizontal Wrap of setup chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSetupChip(
                label: 'Permissions',
                icon: Icons.shield_outlined,
                isOk: widget.permissionsGranted,
                isLoading: _isFixingPermissions,
                onTap: _handlePermissionsFix,
              ),
              _buildSetupChip(
                label: 'Bluetooth',
                icon: Icons.bluetooth_disabled_rounded,
                isOk: widget.bluetoothOn,
                isLoading: _isFixingBluetooth,
                onTap: _handleBluetoothFix,
              ),
              // Location services (GPS) is only required for BLE scanning on Android
              if (kIsWeb || Platform.isAndroid)
                _buildSetupChip(
                  label: 'GPS/Location',
                  icon: Icons.location_off_rounded,
                  isOk: widget.locationServicesEnabled,
                  isLoading: _isFixingLocation,
                  onTap: _handleLocationFix,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSetupChip({
    required String label,
    required IconData icon,
    required bool isOk,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    final color = isOk ? AppTheme.success : AppTheme.warning;
    final bgColor = isOk 
        ? AppTheme.success.withAlpha(20) 
        : AppTheme.warning.withAlpha(25);
    final borderColor = isOk 
        ? AppTheme.success.withAlpha(40) 
        : AppTheme.warning.withAlpha(55);

    return InkWell(
      onTap: isOk ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            if (!isOk)
              BoxShadow(
                color: AppTheme.warning.withAlpha(15),
                blurRadius: 8,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryCyan,
                ),
              )
            else
              Icon(
                isOk ? Icons.check_circle_rounded : icon,
                color: color,
                size: 15,
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isOk ? AppTheme.textPrimary : color,
              ),
            ),
            if (!isOk) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.bolt_rounded,
                color: color.withAlpha(180),
                size: 12,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
