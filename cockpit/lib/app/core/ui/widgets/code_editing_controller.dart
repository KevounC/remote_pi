import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:flutter/widgets.dart';

/// `TextEditingController` que pinta o texto editável com o **mesmo** syntax
/// highlight do viewer read-only. O Flutter desenha o conteúdo de um campo via
/// [buildTextSpan]; sobrescrevê-lo para devolver os spans do highlight.js
/// (`buildCodeSpan`) dá highlight ao vivo enquanto se digita — sem reimplementar
/// pintura, seleção ou cursor.
class CodeEditingController extends TextEditingController {
  CodeEditingController({super.text, required this.language});

  /// Linguagem (extensão) pro highlight; `null`/desconhecida cai em texto puro.
  final String? language;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final span = buildCodeSpan(
      context,
      source: text,
      language: language,
      baseStyle: style ?? const TextStyle(),
    );
    return span ?? TextSpan(text: text, style: style);
  }
}
