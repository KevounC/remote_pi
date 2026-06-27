import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/dismissed_update_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/update_checker.dart';
import 'package:cockpit/app/cockpit/domain/contracts/url_opener.dart';
import 'package:cockpit/app/cockpit/domain/entities/update_info.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/semver.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/update_target.dart';
import 'package:flutter/foundation.dart';

/// Dono do mini card de atualização do rail. Tem **dois modos**, decididos pela
/// plataforma:
///
/// - **macOS/Windows (self-update, plano 47):** [check] liga o [SelfUpdater]
///   nativo (Sparkle/WinSparkle) — checa/baixa em background; o card reflete o
///   [SelfUpdateState] (baixando → pronto). O toque instala+relança o já baixado.
/// - **Linux (notify, plano 43):** [check] lê o `latest.json` via [UpdateChecker];
///   se houver versão **maior** e **não dispensada**, o card aparece e o toque
///   abre a URL do artefato no navegador (download manual).
///
/// Tudo best-effort: falhas são silenciosas, nunca derrubam o boot.
class UpdateViewModel extends ChangeNotifier {
  UpdateViewModel(
    this._checker,
    this._dismissed,
    this._opener,
    this._target,
    this._selfUpdater, {
    this.fallbackUrl = _kFallbackUrl,
  });

  final UpdateChecker _checker;
  final DismissedUpdateStore _dismissed;
  final UrlOpener _opener;
  final UpdateTarget _target;
  final SelfUpdater _selfUpdater;

  /// Versão do app rodando (de package_info, resolvida no boot).
  String get currentVersion => _target.version;

  /// Plataforma/arch correntes pra escolher o artefato (caminho Linux/notify).
  String get platform => _target.platform;
  String get format => _target.format;
  String get arch => _target.arch;

  /// Página de download do site — fallback quando não há artefato da plataforma.
  final String fallbackUrl;

  static const String _kFallbackUrl =
      'https://remote-pi.jacobmoura.work/download';

  UpdateInfo? _available; // caminho Linux/notify
  StreamSubscription<SelfUpdateState>? _selfSub;
  bool _selfDismissed = false; // dispensa transiente no modo self-update
  bool _disposed = false;

  /// `true` em macOS/Windows (há motor de self-update); `false` no Linux.
  bool get isSelfUpdate => _selfUpdater.isSupported;

  // ---- Estado unificado consumido pelo card ----

  /// O card deve aparecer?
  bool get hasUpdate {
    if (isSelfUpdate) {
      return !_selfDismissed && _selfUpdater.state.hasPendingUpdate;
    }
    return _available != null;
  }

  /// Artefato baixado e pronto pra instalar (só self-update).
  bool get isReadyToInstall =>
      isSelfUpdate && _selfUpdater.state.isReadyToInstall;

  /// Versão a anunciar no card (`null` se ainda desconhecida).
  String? get updateVersion =>
      isSelfUpdate ? _selfUpdater.state.version : _available?.version;

  /// Título do card.
  String get cardTitle => isReadyToInstall ? 'Update ready' : 'Update available';

  /// Subtítulo do card (varia por modo/fase).
  String get cardSubtitle {
    final v = updateVersion ?? '';
    if (isSelfUpdate) {
      return isReadyToInstall ? 'v$v — restart to install' : 'Downloading v$v…';
    }
    return 'v$v — click to download';
  }

  // ---- Boot ----

  /// Consulta updates e decide se o card aparece. Silencioso em falha.
  Future<void> check() async {
    if (isSelfUpdate) {
      _selfSub ??= _selfUpdater.changes.listen((_) => _safeNotify());
      await _selfUpdater.initialize();
      await _selfUpdater.checkForUpdates(inBackground: true);
      return;
    }
    // Linux: notify + download manual.
    final latest = await _checker.fetchLatest();
    if (latest == null) return; // sem rede/manifest/inválido → nada.
    if (!isNewerVersion(latest.version, currentVersion)) return; // igual/menor.
    if (_dismissed.dismissedVersion() == latest.version) return; // dispensada.
    _available = latest;
    _safeNotify();
  }

  // ---- Ações do card ----

  /// Toque no card: self-update → instala+relança o update já baixado; Linux →
  /// baixa o artefato (abre a URL no navegador).
  Future<void> primaryAction() async {
    if (isSelfUpdate) {
      await _selfUpdater.applyDownloadedUpdate();
      return;
    }
    await _download();
  }

  /// Fecha o card. Self-update → dispensa só pela sessão (reaparece se baixar
  /// outra versão). Linux → persiste a versão como dispensada (não reaparece).
  Future<void> dismiss() async {
    if (isSelfUpdate) {
      _selfDismissed = true;
      _safeNotify();
      return;
    }
    final v = _available?.version;
    _available = null;
    _safeNotify();
    if (v != null) await _dismissed.dismiss(v);
  }

  /// Abre a URL do artefato da plataforma corrente; sem artefato compatível →
  /// abre a página de download do site (caminho Linux/notify).
  Future<void> _download() async {
    final info = _available;
    if (info == null) return;
    final artifact = info.artifactFor(
      platform: platform,
      format: format,
      arch: arch,
    );
    await _opener.open(artifact?.url ?? fallbackUrl);
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _selfSub?.cancel();
    super.dispose();
  }
}
