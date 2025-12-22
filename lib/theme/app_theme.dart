import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryGreen = Color(0xFF2E7D32); // Deep Green
  static const Color secondaryGreen = Color(0xFF81C784); // Light Green
  static const Color backgroundWhite = Color(
    0xFFF5F7F5,
  ); // Very light grey-green tint
  static const Color cardColor = Colors.white;
  static const Color textDark = Color(0xFF1B1B1B);
  static const Color textGrey = Color(0xFF757575);

  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primaryGreen,
      scaffoldBackgroundColor: backgroundWhite,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGreen,
        primary: primaryGreen,
        secondary: secondaryGreen,
        surface: cardColor,
        background: backgroundWhite,
      ),
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: textDark,
        displayColor: textDark,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(8),
      ),
      useMaterial3: true,
    );
  }
}
