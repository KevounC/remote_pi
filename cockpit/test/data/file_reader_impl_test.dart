import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/file_reader_impl.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reader = FileReaderImpl();

  group('FileReaderImpl — detecção de A/V (plano 46)', () {
    test('vídeo → FileViewVideo (só o caminho, sem tocar o disco)', () async {
      const exts = ['mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'wmv', 'flv'];
      for (final ext in exts) {
        // Caminho inexistente de propósito: A/V resolve por extensão ANTES de
        // qualquer leitura, então não pode depender do arquivo existir.
        final path = '/tmp/does-not-exist-46/clip.$ext';
        final view = await reader.read(path);
        expect(view, isA<FileViewVideo>(), reason: '.$ext deveria ser vídeo');
        expect((view as FileViewVideo).path, path);
      }
    });

    test('áudio → FileViewAudio (só o caminho, sem tocar o disco)', () async {
      const exts = ['mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg', 'opus'];
      for (final ext in exts) {
        final path = '/tmp/does-not-exist-46/track.$ext';
        final view = await reader.read(path);
        expect(view, isA<FileViewAudio>(), reason: '.$ext deveria ser áudio');
        expect((view as FileViewAudio).path, path);
      }
    });

    test('imagem continua FileViewImage (sem regressão)', () async {
      final view = await reader.read('/tmp/does-not-exist-46/pic.png');
      expect(view, isA<FileViewImage>());
    });

    test('extensão desconhecida segue o caminho atual: inexistente → '
        'FileViewUnsupported', () async {
      final view = await reader.read('/tmp/does-not-exist-46/file.xyz');
      expect(view, isA<FileViewUnsupported>());
    });

    test('extensão desconhecida com texto real → FileViewText', () async {
      final dir = await Directory.systemTemp.createTemp('ck_fr_test');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/notes.log')..writeAsStringSync('hello world');
      final view = await reader.read(f.path);
      expect(view, isA<FileViewText>());
      expect((view as FileViewText).text, 'hello world');
    });

    test('write grava em disco e read devolve o novo conteúdo', () async {
      final dir = await Directory.systemTemp.createTemp('ck_fr_write');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/main.dart')..writeAsStringSync('old');
      final ok = await reader.write(f.path, 'void main() {}');
      expect(ok, isTrue);
      expect(f.readAsStringSync(), 'void main() {}');
      final view = await reader.read(f.path);
      expect((view as FileViewText).text, 'void main() {}');
    });

    test('svg → FileViewSvg (fonte + caminho, editável)', () async {
      final dir = await Directory.systemTemp.createTemp('ck_fr_svg');
      addTearDown(() => dir.delete(recursive: true));
      const svg = '<svg xmlns="http://www.w3.org/2000/svg"></svg>';
      final f = File('${dir.path}/icon.svg')..writeAsStringSync(svg);
      final view = await reader.read(f.path);
      expect(view, isA<FileViewSvg>());
      expect((view as FileViewSvg).text, svg);
      expect(view.path, f.path);
    });

    test('write em caminho inválido (dir inexistente) → false', () async {
      final ok = await reader.write('/tmp/no-such-dir-99/x.txt', 'data');
      expect(ok, isFalse);
    });
  });
}
