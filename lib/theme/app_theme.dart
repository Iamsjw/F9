import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ─── Core Colors ───────────────────────────────────────────────
  static const Color background = Color(0xFF090B10); // Deep minimalist onyx black
  static const Color backgroundVariant = Color(0xFF0F131E); // Slate dark container background
  static const Color surface = Color(0x12FFFFFF); // Subtle glass (7% white)
  static const Color surfaceVariant = Color(0xFF141A28); // Bespoke dark slate container for menus & cards
  static const Color surfaceRaised = Color(0xFF1B2234); // Elevated slate surface

  // ─── Primary & Accent Colors ────────────────────────────────────
  static const Color primary = primaryBlue; // Refined Indigo
  static const Color primaryBlue = Color(0xFF6366F1); // Indigo Accent
  static const Color primaryCyan = Color(0xFF38BDF8); // Sky Teal Accent
  static const Color primaryGreen = Color(0xFF10B981); // Emerald Accent
  static const Color softGlow = Color(0x1F6366F1); // Soft indigo glow

  // ─── Text Colors ─────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF8FAFC); // High contrast slate white
  static const Color textSecondary = Color(0xFFCBD5E1); // Muted slate gray
  static const Color textMuted = Color(0xFF94A3B8); // Slate subtext
  static const Color textDisabled = Color(0xFF64748B); // Slate hint/placeholder

  // ─── Status Colors ────────────────────────────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color successSoft = Color(0xFF064E3B); // Opaque emerald for high contrast banners
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFF78350F); // Opaque amber for high contrast banners
  static const Color error = Color(0xFFEF4444);
  static const Color errorSoft = Color(0xFF7F1D1D); // Opaque crimson for high contrast error banners

  // ─── Glass & Shadows ──────────────────────────────────────────
  static const Color shadowDark = Color(0x66000000); // Dark elevation shadow
  static const Color shadowLight = Color(0x1AFFFFFF); // Hairline glass border

  // ─── Gradients ──────────────────────────────────────────────
  static const Gradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient surfaceGradient = RadialGradient(
    center: Alignment(-0.6, -0.5),
    radius: 1.4,
    colors: [Color(0x156366F1), Colors.transparent],
  );

  // ─── Neumorphic Decorations (Rebranded internally to Glassmorphism)
  static BoxDecoration neumorphic({
    BorderRadiusGeometry? borderRadius,
    bool isRaised = false,
  }) {
    return BoxDecoration(
      color: isRaised ? surfaceRaised : surface,
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      border: Border.all(
        color: const Color(0x18FFFFFF),
        width: 1.0,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x59000000),
          offset: Offset(0, 8),
          blurRadius: 24,
          spreadRadius: -4,
        ),
      ],
    );
  }

  static BoxDecoration neumorphicGlow({
    BorderRadiusGeometry? borderRadius,
    Color glowColor = primaryCyan,
  }) {
    return BoxDecoration(
      color: surface,
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      border: Border.all(
        color: glowColor.withAlpha(70),
        width: 1.0,
      ),
      boxShadow: [
        const BoxShadow(
          color: Color(0x59000000),
          offset: Offset(0, 8),
          blurRadius: 24,
          spreadRadius: -4,
        ),
        BoxShadow(
          color: glowColor.withAlpha(45),
          blurRadius: 24,
          spreadRadius: 2,
        ),
      ],
    );
  }

  // ─── Theme Data ──────────────────────────────────────────────
  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: primaryCyan,
      secondary: primaryBlue,
      surface: surface,
      error: error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textPrimary,
      outline: shadowLight,
    ),
    scaffoldBackgroundColor: background,
    canvasColor: background,
    dialogTheme: const DialogThemeData(
      backgroundColor: surfaceVariant,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shadowColor: Colors.black,
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: surfaceVariant,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: surfaceVariant,
      dividerColor: const Color(0x33FFFFFF),
    ),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(
      TextTheme(
        displayLarge: _buildTextStyle(32, FontWeight.w700, textPrimary, -0.5),
        displayMedium: _buildTextStyle(28, FontWeight.w700, textPrimary, -0.3),
        headlineLarge: _buildTextStyle(24, FontWeight.w700, textPrimary, -0.2),
        headlineMedium: _buildTextStyle(20, FontWeight.w600, textPrimary),
        headlineSmall: _buildTextStyle(18, FontWeight.w600, textPrimary),
        titleLarge: _buildTextStyle(16, FontWeight.w600, textPrimary),
        titleMedium: _buildTextStyle(14, FontWeight.w600, textPrimary),
        titleSmall: _buildTextStyle(13, FontWeight.w600, textSecondary),
        bodyLarge: _buildTextStyle(15, FontWeight.w400, textPrimary),
        bodyMedium: _buildTextStyle(14, FontWeight.w400, textSecondary),
        bodySmall: _buildTextStyle(12, FontWeight.w400, textMuted),
        labelLarge: _buildTextStyle(14, FontWeight.w600, textPrimary, 0.2),
        labelMedium: _buildTextStyle(12, FontWeight.w600, textSecondary, 0.3),
        labelSmall: _buildTextStyle(11, FontWeight.w600, textMuted, 0.4),
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      iconTheme: const IconThemeData(color: textPrimary),
      titleTextStyle: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: const Color(0xFF130E26).withAlpha(165),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0x28FFFFFF), width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0x28FFFFFF), width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryCyan, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: error, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: error, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textMuted, fontSize: 14),
      hintStyle: const TextStyle(color: textDisabled, fontSize: 14),
      errorStyle: const TextStyle(color: error, fontSize: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: primaryBlue.withAlpha(80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: GoogleFonts.plusJakartaSans(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      shadowColor: shadowDark,
    ),
    dividerTheme: const DividerThemeData(
      color: shadowLight,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariant,
      selectedColor: primaryBlue.withAlpha(60),
      labelStyle: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E1B2E),
      contentTextStyle: GoogleFonts.plusJakartaSans(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0x33FFFFFF), width: 1),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    iconTheme: const IconThemeData(color: textPrimary, size: 24),
  );

  // lightTheme required by contract - redirect to dark
  static ThemeData get lightTheme => darkTheme;

  // ─── Helper Methods ────────────────────────────────────────────
  static TextStyle _buildTextStyle(
    double fontSize,
    FontWeight fontWeight,
    Color color, [
    double letterSpacing = 0,
  ]) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  static BoxDecoration glassMorphism({
    BorderRadiusGeometry? borderRadius,
    double opacity = 0.08,
    Color borderColor = const Color(0x1AFFFFFF),
  }) {
    return BoxDecoration(
      color: Colors.white.withAlpha((opacity * 255).round()),
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: const [
        BoxShadow(
          color: Color(0x59000000),
          offset: Offset(0, 8),
          blurRadius: 24,
          spreadRadius: -4,
        ),
      ],
    );
  }

  // ─── Glow Effect ──────────────────────────────────────────────
  static BoxDecoration glowEffect({
    required Color glowColor,
    BorderRadiusGeometry? borderRadius,
    double intensity = 0.3,
  }) {
    return BoxDecoration(
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: glowColor.withAlpha((intensity * 255).round()),
          blurRadius: 24,
          spreadRadius: 4,
        ),
      ],
    );
  }
}
