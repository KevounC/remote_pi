import 'package:xterm/xterm.dart';

/// Um link detectado no buffer do terminal: a URL e o range de colunas (numa
/// linha) que ela ocupa, pra desenhar o realce e abrir no clique.
class TerminalLink {
  const TerminalLink({
    required this.url,
    required this.row,
    required this.startCol,
    required this.endCol, // exclusivo
  });

  final String url;
  final int row;
  final int startCol;
  final int endCol;

  bool contains(int col) => col >= startCol && col < endCol;
}

/// Acha a URL sob uma célula. Hoje por **regex** sobre o texto que o terminal
/// renderizou (território legítimo do terminal — todo emulador faz isso). O
/// gancho de OSC 8 (hyperlink explícito da app) entra no Slice 2: quando a
/// célula tiver um id de hyperlink, ele tem precedência sobre o regex.
class TerminalLinkDetector {
  // http(s):// e file://, mais www. — para em espaço e em fechamentos comuns
  // que não fazem parte de URL (aspas, parênteses, colchetes).
  static final _urlRegex = RegExp(
    r'''(?:https?://|file://|www\.)[^\s<>()\[\]{}"'`]+''',
    caseSensitive: false,
  );

  // Pontuação de fim de frase que costuma grudar na URL mas não faz parte dela.
  static const _trailingTrim = '.,;:!?';

  TerminalLink? linkAt(Terminal terminal, CellOffset pos) {
    final lines = terminal.buffer.lines;
    if (pos.y < 0 || pos.y >= lines.length) return null;
    final line = lines[pos.y];
    final cols = line.length;
    if (cols <= 0 || pos.x < 0 || pos.x >= cols) return null;

    // OSC 8 (hyperlink explícito da app) tem precedência sobre o regex: é a URL
    // que a própria app marcou, não um palpite. O range é o trecho contíguo de
    // células com a mesma URL.
    if (line.getCodePoint(pos.x) != 0) {
      final url = terminal.hyperlinkUrl(line.getAttributes(pos.x));
      if (url != null && url.isNotEmpty) {
        var start = pos.x;
        var end = pos.x + 1;
        while (start > 0 &&
            terminal.hyperlinkUrl(line.getAttributes(start - 1)) == url) {
          start--;
        }
        while (end < cols &&
            terminal.hyperlinkUrl(line.getAttributes(end)) == url) {
          end++;
        }
        return TerminalLink(url: url, row: pos.y, startCol: start, endCol: end);
      }
    }

    // String indexada por COLUNA: célula vazia/spacer vira espaço (quebra a
    // URL), char real fica na sua coluna. URLs são ASCII (largura 1), então
    // coluna == índice no texto — match.start/end são colunas direto.
    final units = List<int>.filled(cols, 0x20);
    for (var c = 0; c < cols; c++) {
      final code = line.getCodePoint(c);
      if (code != 0) units[c] = code;
    }
    final text = String.fromCharCodes(units);

    for (final m in _urlRegex.allMatches(text)) {
      if (pos.x < m.start || pos.x >= m.end) continue;
      var end = m.end;
      // tira pontuação final que não é da URL (mas mantém se o ponteiro estiver
      // exatamente sobre ela)
      while (end - 1 > m.start &&
          end - 1 > pos.x &&
          _trailingTrim.contains(text[end - 1])) {
        end--;
      }
      return TerminalLink(
        url: text.substring(m.start, end),
        row: pos.y,
        startCol: m.start,
        endCol: end,
      );
    }
    return null;
  }
}
