import 'package:flutter/material.dart';

import '../theme.dart';

/// Layout padrão das telas de configuração da TV: marca, título, subtítulo
/// e conteúdo, com margens seguras para TVs que cortam as bordas
/// (*overscan*).
class TvPage extends StatelessWidget {
  const TvPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.tv, color: brandAccent, size: 32),
                  SizedBox(width: 12),
                  Text('Beyond TV', style: TextStyle(fontSize: 24)),
                ],
              ),
              const SizedBox(height: 24),
              Text(title, style: textTheme.displaySmall),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: textTheme.titleMedium?.copyWith(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 32),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
