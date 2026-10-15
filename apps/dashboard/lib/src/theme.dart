import 'package:flutter/material.dart';

/// Cor de destaque da marca Beyond TV (a mesma dos ícones).
const brandAccent = Color(0xFF38BDF8);

ThemeData buildTheme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandAccent,
        brightness: brightness,
      ),
    );
