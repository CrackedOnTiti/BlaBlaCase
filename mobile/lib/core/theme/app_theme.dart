import 'package:flutter/material.dart';

const kBackground = Color(0xFF0F1117);
const kSurface    = Color(0xFF1C1F2E);
const kSurface2   = Color(0xFF252837);
const kBorder     = Color(0xFF2E3250);
const kPrimary    = Color(0xFF0EA5E9);
const kAccent     = Color(0xFF38BDF8);

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: Brightness.dark,
  ).copyWith(
    surface: kSurface,
    onSurface: Colors.white,
    primary: kPrimary,
    secondary: kAccent,
  ),
  scaffoldBackgroundColor: kBackground,
  cardTheme: const CardThemeData(
    color: kSurface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      side: BorderSide(color: kBorder),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kBackground,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: kPrimary,
      side: const BorderSide(color: kPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    filled: true,
    fillColor: kSurface2,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: kBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: kBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: kPrimary, width: 1.5),
    ),
    hintStyle: TextStyle(color: Colors.white38),
  ),
  listTileTheme: const ListTileThemeData(
    tileColor: Colors.transparent,
  ),
  dividerTheme: const DividerThemeData(
    color: kBorder,
  ),
  chipTheme: const ChipThemeData(
    backgroundColor: kSurface2,
    side: BorderSide(color: kBorder),
  ),
);
