import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';

/// Estado git de um projeto (workspace): branch atual, posição relativa ao
/// upstream (ahead/behind) e o status por arquivo sujo.
class GitInfo {
  const GitInfo({
    required this.branch,
    this.ahead = 0,
    this.behind = 0,
    this.files = const <String, GitFileStatus>{},
  });

  /// Branch atual (ou short SHA se detached HEAD).
  final String branch;

  /// Commits à **frente** do upstream (precisam de push). 0 se não há upstream.
  final int ahead;

  /// Commits **atrás** do upstream (precisam de pull). 0 se não há upstream.
  /// Reflete o último `fetch` conhecido — não buscamos do remoto sozinhos.
  final int behind;

  /// Status por arquivo sujo. Chave = caminho **relativo à raiz do projeto**,
  /// sempre com separador `/`. Vazio = árvore limpa.
  final Map<String, GitFileStatus> files;

  /// Nº de arquivos com mudança. 0 = árvore limpa.
  int get dirtyCount => files.length;

  bool get isDirty => files.isNotEmpty;

  /// `true` quando há divergência de commits com o upstream.
  bool get hasUpstreamDiff => ahead > 0 || behind > 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GitInfo &&
        other.branch == branch &&
        other.ahead == ahead &&
        other.behind == behind &&
        _sameFiles(other.files, files);
  }

  @override
  int get hashCode => Object.hash(branch, ahead, behind, files.length);

  static bool _sameFiles(
    Map<String, GitFileStatus> a,
    Map<String, GitFileStatus> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
