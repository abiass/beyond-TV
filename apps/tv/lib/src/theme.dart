import 'package:flutter/material.dart';

/// Cores da marca (as mesmas dos ícones e do banner).
const brandBackground = Color(0xFF0F172A);
const brandAccent = Color(0xFF38BDF8);

/// Tema escuro, com textos grandes para leitura a distância.
ThemeData buildTvTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandAccent,
        brightness: Brightness.dark,
        surface: brandBackground,
      ),
      scaffoldBackgroundColor: brandBackground,
    );
