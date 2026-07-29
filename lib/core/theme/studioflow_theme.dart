import 'package:flutter/material.dart';

enum StudioFlowTheme { elegante, barbearia, delicado, infantil, clinica }

extension StudioFlowThemeData on StudioFlowTheme {
  String get nome {
    switch (this) {
      case StudioFlowTheme.elegante:
        return 'Elegante';
      case StudioFlowTheme.barbearia:
        return 'Barbearia Premium';
      case StudioFlowTheme.delicado:
        return 'Beauty Delicado';
      case StudioFlowTheme.infantil:
        return 'Infantil';
      case StudioFlowTheme.clinica:
        return 'Clínica Clean';
    }
  }

  String get chave {
    return name;
  }

  String get emoji {
    switch (this) {
      case StudioFlowTheme.elegante:
        return '✨';
      case StudioFlowTheme.barbearia:
        return '💈';
      case StudioFlowTheme.delicado:
        return '🌸';
      case StudioFlowTheme.infantil:
        return '🌈';
      case StudioFlowTheme.clinica:
        return '🌿';
    }
  }

  IconData get icone {
    switch (this) {
      case StudioFlowTheme.elegante:
        return Icons.auto_awesome;
      case StudioFlowTheme.barbearia:
        return Icons.content_cut;
      case StudioFlowTheme.delicado:
        return Icons.spa_outlined;
      case StudioFlowTheme.infantil:
        return Icons.child_care;
      case StudioFlowTheme.clinica:
        return Icons.health_and_safety_outlined;
    }
  }

  Color get corPrincipal {
    switch (this) {
      case StudioFlowTheme.elegante:
        return const Color(0xFF70569A);
      case StudioFlowTheme.barbearia:
        return const Color(0xFF222222);
      case StudioFlowTheme.delicado:
        return const Color(0xFFE17DA8);
      case StudioFlowTheme.infantil:
        return const Color(0xFF378ED1);
      case StudioFlowTheme.clinica:
        return const Color(0xFF258C85);
    }
  }

  Color get corSecundaria {
    switch (this) {
      case StudioFlowTheme.elegante:
        return const Color(0xFF8B5CF6);
      case StudioFlowTheme.barbearia:
        return const Color(0xFFC49A50);
      case StudioFlowTheme.delicado:
        return const Color(0xFFF2AAC8);
      case StudioFlowTheme.infantil:
        return const Color(0xFFFFB648);
      case StudioFlowTheme.clinica:
        return const Color(0xFF69C5BD);
    }
  }

  Color get fundo {
    switch (this) {
      case StudioFlowTheme.elegante:
        return const Color(0xFFF9F6FC);
      case StudioFlowTheme.barbearia:
        return const Color(0xFFF3F3F3);
      case StudioFlowTheme.delicado:
        return const Color(0xFFFFF7FA);
      case StudioFlowTheme.infantil:
        return const Color(0xFFF5FBFF);
      case StudioFlowTheme.clinica:
        return const Color(0xFFF3FAF9);
    }
  }

  static StudioFlowTheme pelaChave(String? chave) {
    return StudioFlowTheme.values.firstWhere(
      (tema) => tema.name == chave,
      orElse: () => StudioFlowTheme.elegante,
    );
  }

  static StudioFlowTheme sugeridoParaCategoria(String categoria) {
    final categoriaNormalizada = categoria.toLowerCase();

    if (categoriaNormalizada.contains('barbearia')) {
      return StudioFlowTheme.barbearia;
    }

    if (categoriaNormalizada.contains('infantil')) {
      return StudioFlowTheme.infantil;
    }

    if (categoriaNormalizada.contains('clínica') ||
        categoriaNormalizada.contains('clinica') ||
        categoriaNormalizada.contains('estética') ||
        categoriaNormalizada.contains('estetica')) {
      return StudioFlowTheme.clinica;
    }

    if (categoriaNormalizada.contains('nail') ||
        categoriaNormalizada.contains('manicure') ||
        categoriaNormalizada.contains('cílios') ||
        categoriaNormalizada.contains('cilios') ||
        categoriaNormalizada.contains('sobrancelha')) {
      return StudioFlowTheme.delicado;
    }

    return StudioFlowTheme.elegante;
  }
}
