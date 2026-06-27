import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:flutter/foundation.dart';

/// Self-update nativo via [autoUpdater] (Sparkle no macOS, WinSparkle no
/// Windows). Implementa [SelfUpdater] e ouve os eventos do motor via
/// [UpdaterListener], traduzindo-os pra [SelfUpdateState].
///
/// UX híbrida (decisão B do plano 47): a checagem de boot e a agendada rodam
/// `inBackground: true` (silenciosas). Com `SUEnableAutomaticChecks`/
/// `SUAutomaticallyUpdate` no Info.plist (macOS) o Sparkle baixa em background e
/// instala no próximo quit; o card reflete [changes]. [applyDownloadedUpdate]
/// re-checa em foreground pra o motor instalar+relançar o update já baixado.
///
/// Limite conhecido (risco do plano): o plugin usa `SPUStandardUserDriver`, então
/// o passo final de install pode mostrar UI nativa mínima — não dá pra suprimir
/// 100% pela fachada. Aceitável; a checagem de boot continua silenciosa.
class AutoUpdaterSelfUpdater with UpdaterListener implements SelfUpdater {
  AutoUpdaterSelfUpdater({
    required this.feedUrl,
    this.checkInterval = const Duration(hours: 24),
  });

  /// Appcast da plataforma (`appcast-macos.xml` / `appcast-windows.xml`).
  final String feedUrl;

  /// Intervalo da checagem periódica do motor nativo (mín. 1h; 0 desliga).
  final Duration checkInterval;

  final StreamController<SelfUpdateState> _controller =
      StreamController<SelfUpdateState>.broadcast();
  SelfUpdateState _state = const SelfUpdateState.idle();
  bool _initialized = false;

  @override
  bool get isSupported => true;

  @override
  SelfUpdateState get state => _state;

  @override
  Stream<SelfUpdateState> get changes => _controller.stream;

  void _emit(SelfUpdateState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    autoUpdater.addListener(this);
    await autoUpdater.setFeedURL(feedUrl);
    await autoUpdater.setScheduledCheckInterval(checkInterval.inSeconds);
  }

  @override
  Future<void> checkForUpdates({bool inBackground = true}) async {
    if (!_initialized) await initialize();
    await autoUpdater.checkForUpdates(inBackground: inBackground);
  }

  @override
  Future<void> applyDownloadedUpdate() async {
    if (_state.phase != SelfUpdatePhase.downloaded) return;
    // Re-checar em foreground faz o Sparkle/WinSparkle instalar o update já
    // baixado e relançar o app (o motor conduz o restart).
    await autoUpdater.checkForUpdates(inBackground: false);
  }

  // ---- UpdaterListener: eventos do motor nativo → SelfUpdateState ----

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    _emit(const SelfUpdateState(SelfUpdatePhase.checking));
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? item) {
    // Disponível → o motor baixa em background (modo auto-update).
    _emit(
      SelfUpdateState(SelfUpdatePhase.downloading, version: _versionOf(item)),
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    _emit(const SelfUpdateState.idle());
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? item) {
    _emit(
      SelfUpdateState(SelfUpdatePhase.downloaded, version: _versionOf(item)),
    );
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? item) {
    // Reinício silencioso (decisão C): a fachada NÃO aguarda este callback —
    // não dá pra bloquear o quit nem matar agentes graciosamente aqui. Os
    // agentes `pi` filhos viram órfãos e são reapeados no próximo boot por
    // `PiProcessRegistry.cleanOrphans` (SIGKILL dos PIDs do registry); o
    // workspace (panes/abas) reabre pelo estado no Hive.
    debugPrint(
      '[self-update] before quit for update — agents reaped on next boot',
    );
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    _emit(SelfUpdateState(SelfUpdatePhase.error, message: error?.message));
  }

  String? _versionOf(AppcastItem? item) =>
      item?.displayVersionString ?? item?.versionString;

  @override
  void dispose() {
    autoUpdater.removeListener(this);
    if (!_controller.isClosed) _controller.close();
  }
}
