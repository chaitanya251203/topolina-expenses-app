import 'package:flutter/material.dart';

abstract final class TopolinaTheme {
  static const forest = Color(0xFF193F34),
      cream = Color(0xFFF7F4EC),
      gold = Color(0xFFAD8956);
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: forest,
      primary: forest,
      secondary: gold,
      surface: cream,
    ),
    scaffoldBackgroundColor: cream,
    appBarTheme: const AppBarTheme(backgroundColor: cream, centerTitle: false),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFDDDCD3)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        textStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    ),
  );
}
