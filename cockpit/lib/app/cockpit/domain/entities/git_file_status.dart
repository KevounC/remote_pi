/// Estado git de **um** caminho (arquivo ou pasta agregada) na árvore.
///
/// A ordem da declaração é a **precedência** de severidade (do mais fraco ao
/// mais forte): ao agregar uma pasta, vence o estado de maior `index`
/// ([strongest]). Ex.: uma pasta com um untracked e um modified mostra
/// `modified`; com um conflito, mostra `conflict`.
enum GitFileStatus {
  /// Arquivo novo, ainda não rastreado (`??`).
  untracked,

  /// Mudança no index (staged) sem mudança pendente no working tree.
  staged,

  /// Mudança no working tree ainda não comitada (modificado/typechange).
  modified,

  /// Removido (no index ou no working tree).
  deleted,

  /// Conflito de merge (ambos os lados mexeram — `UU`, `AA`, `DD`, …).
  conflict;

  /// O mais severo entre dois estados (maior `index` vence). `null` é o vazio.
  static GitFileStatus? strongest(GitFileStatus? a, GitFileStatus? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
  }
}
