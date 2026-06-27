import 'package:auto_updater/auto_updater.dart';
import 'package:cockpit/app/cockpit/data/update/auto_updater_self_updater.dart';
import 'package:cockpit/app/cockpit/data/update/noop_self_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // O dispose() remove o listener do singleton `autoUpdater` (toca o canal de
  // plataforma via EventChannel) — o binding de teste trata isso sem crashar.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoUpdaterSelfUpdater traduz eventos nativos → SelfUpdateState', () {
    late AutoUpdaterSelfUpdater updater;

    setUp(() {
      updater = AutoUpdaterSelfUpdater(feedUrl: 'https://example.test/appcast.xml');
    });
    tearDown(() => updater.dispose());

    test('isSupported é true', () {
      expect(updater.isSupported, isTrue);
    });

    test('checking-for-update → phase checking', () {
      updater.onUpdaterCheckingForUpdate(null);
      expect(updater.state.phase, SelfUpdatePhase.checking);
    });

    test('update-available → downloading com versão', () {
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
      expect(updater.state.phase, SelfUpdatePhase.downloading);
      expect(updater.state.version, '1.6.0');
      expect(updater.state.hasPendingUpdate, isTrue);
      expect(updater.state.isReadyToInstall, isFalse);
    });

    test('update-downloaded → pronto pra instalar', () {
      updater.onUpdaterUpdateDownloaded(
        const AppcastItem(displayVersionString: '1.6.0', versionString: '9'),
      );
      expect(updater.state.phase, SelfUpdatePhase.downloaded);
      expect(updater.state.isReadyToInstall, isTrue);
      expect(updater.state.version, '1.6.0');
    });

    test('versão cai pra versionString quando displayVersionString é null', () {
      updater.onUpdaterUpdateDownloaded(const AppcastItem(versionString: '9'));
      expect(updater.state.version, '9');
    });

    test('update-not-available → idle (sem pendência)', () {
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
      updater.onUpdaterUpdateNotAvailable(null);
      expect(updater.state.phase, SelfUpdatePhase.idle);
      expect(updater.state.hasPendingUpdate, isFalse);
    });

    test('error carrega a mensagem', () {
      updater.onUpdaterError(UpdaterError('boom'));
      expect(updater.state.phase, SelfUpdatePhase.error);
      expect(updater.state.message, 'boom');
    });

    test('changes emite as transições na ordem', () {
      expectLater(
        updater.changes.map((s) => s.phase),
        emitsInOrder([
          SelfUpdatePhase.checking,
          SelfUpdatePhase.downloading,
          SelfUpdatePhase.downloaded,
        ]),
      );
      updater.onUpdaterCheckingForUpdate(null);
      updater.onUpdaterUpdateAvailable(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
      updater.onUpdaterUpdateDownloaded(
        const AppcastItem(displayVersionString: '1.6.0'),
      );
    });
  });

  group('NoopSelfUpdater (Linux)', () {
    test('não suportado e inerte', () async {
      const updater = NoopSelfUpdater();
      expect(updater.isSupported, isFalse);
      expect(updater.state.phase, SelfUpdatePhase.idle);
      // Métodos são no-op e não lançam.
      await updater.initialize();
      await updater.checkForUpdates();
      await updater.applyDownloadedUpdate();
      expect(updater.state.isReadyToInstall, isFalse);
    });
  });
}
