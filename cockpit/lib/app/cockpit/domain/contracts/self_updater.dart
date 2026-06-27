import 'dart:async';

/// Fase corrente do self-update nativo (Sparkle/WinSparkle). Best-effort: toda
/// falha vira [error] e o card cai pro caminho de notify (nunca derruba o boot).
enum SelfUpdatePhase {
  /// Sem update pendente (nunca checou, ou já está na última versão).
  idle,

  /// Checando o appcast.
  checking,

  /// Há versão nova; download em curso (modo auto-download silencioso).
  downloading,

  /// Artefato baixado e verificado — pronto pra instalar no próximo restart.
  downloaded,

  /// Falha (rede, assinatura, parsing). Silenciosa pra UI; só loga.
  error,
}

/// Estado observável do [SelfUpdater]. [version] preenchido quando há update
/// disponível/baixado; [message] no erro.
class SelfUpdateState {
  const SelfUpdateState(this.phase, {this.version, this.message});

  const SelfUpdateState.idle() : this(SelfUpdatePhase.idle);

  final SelfUpdatePhase phase;
  final String? version;
  final String? message;

  /// `true` quando o artefato já está baixado e só falta reiniciar pra aplicar.
  bool get isReadyToInstall => phase == SelfUpdatePhase.downloaded;

  /// `true` enquanto há um update em andamento ou pronto (a UI mostra o card).
  bool get hasPendingUpdate =>
      phase == SelfUpdatePhase.downloading ||
      phase == SelfUpdatePhase.downloaded;
}

/// Self-update nativo: **Sparkle no macOS, WinSparkle no Windows** (via o plugin
/// `auto_updater`). Em plataformas sem suporte (Linux) [isSupported] é `false` e
/// os métodos são no-op — aí o caminho de notify + download manual
/// (`UpdateChecker`/`UpdateCard`) assume.
///
/// UX híbrida (decisão B do plano 47): a checagem/baixa roda **em background**
/// (sem diálogo nativo); a UI visível é só o nosso card, que reflete [state]/
/// [changes]. Reinício **silencioso** (decisão C): ao aplicar o update o app é
/// encerrado e relançado pelo motor nativo; os agentes `pi` filhos são reapeados
/// no próximo boot por `PiProcessRegistry.cleanOrphans` e respawnados pelo estado
/// no Hive.
abstract class SelfUpdater {
  /// `true` só onde há motor nativo (macOS/Windows).
  bool get isSupported;

  /// Estado corrente (snapshot síncrono pra primeira pintura do card).
  SelfUpdateState get state;

  /// Stream de transições de [state] — a UI escuta pra re-renderizar.
  Stream<SelfUpdateState> get changes;

  /// Liga o motor nativo: feed URL + listener + agenda a checagem periódica.
  /// Idempotente; no-op se [isSupported] é `false`.
  Future<void> initialize();

  /// Dispara uma checagem. [inBackground] = silenciosa (sem UI nativa).
  Future<void> checkForUpdates({bool inBackground = true});

  /// Aplica o update já baixado: instala e relança. No-op se nada foi baixado.
  Future<void> applyDownloadedUpdate();

  /// Libera o listener nativo e a stream.
  void dispose();
}
