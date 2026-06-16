import 'dart:convert';
import 'dart:io';

import 'package:cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/domain/entities/file_view.dart';

/// Classifica o arquivo por extensão + conteúdo:
/// - vídeo → [FileViewVideo] (só o caminho);
/// - áudio → [FileViewAudio] (só o caminho);
/// - imagem → [FileViewImage] (só o caminho);
/// - markdown → [FileViewMarkdown];
/// - texto legível (utf8, sem null byte, ≤ 2MB) → [FileViewText];
/// - resto (binário, grande demais, não-utf8) → [FileViewUnsupported].
class FileReaderImpl implements FileReader {
  const FileReaderImpl();

  static const int _maxTextBytes = 2 * 1024 * 1024;
  static const Set<String> _markdown = {'md', 'mdx', 'markdown'};
  static const Set<String> _image = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'svg',
    'ico',
  };
  static const Set<String> _video = {
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    'wmv',
    'flv',
  };
  static const Set<String> _audio = {
    'mp3',
    'wav',
    'aac',
    'm4a',
    'flac',
    'ogg',
    'opus',
  };

  @override
  Future<FileView> read(String path) async {
    final ext = _ext(path);
    // A/V e imagem só passam o caminho — o player/widget carrega (sem ler bytes,
    // sem limite de tamanho). Decisão cedo, antes de qualquer leitura de disco.
    if (_video.contains(ext)) return FileViewVideo(path);
    if (_audio.contains(ext)) return FileViewAudio(path);
    if (_image.contains(ext)) return FileViewImage(path);

    final file = File(path);
    if (!await file.exists()) return const FileViewUnsupported();
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file || stat.size > _maxTextBytes) {
      return const FileViewUnsupported();
    }

    final bytes = await file.readAsBytes();
    if (_looksBinary(bytes)) return const FileViewUnsupported();
    final String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      return const FileViewUnsupported();
    }

    if (_markdown.contains(ext)) return FileViewMarkdown(text);
    return FileViewText(text, language: ext.isEmpty ? null : ext);
  }

  @override
  Stream<void> watch(String path) {
    try {
      // FSEvents no macOS. Erros do stream (arquivo trocado por rename, etc.)
      // viram fim silencioso — o consumidor (VM) trata via onError.
      return File(path)
          .watch(events: FileSystemEvent.modify | FileSystemEvent.delete)
          .map((_) {});
    } catch (_) {
      return const Stream<void>.empty();
    }
  }

  /// Heurística de binário: null byte nos primeiros ~8KB.
  bool _looksBinary(List<int> bytes) {
    final n = bytes.length < 8000 ? bytes.length : 8000;
    for (var i = 0; i < n; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  String _ext(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}
