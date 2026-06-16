/// O conteúdo de um arquivo aberto no viewer, já classificado.
sealed class FileView {
  const FileView();
}

/// Markdown (.md/.mdx) — renderizado com gpt_markdown.
final class FileViewMarkdown extends FileView {
  const FileViewMarkdown(this.text);
  final String text;
}

/// Texto legível (.js/.json/…) — texto puro por enquanto (highlight depois).
final class FileViewText extends FileView {
  const FileViewText(this.text, {this.language});
  final String text;

  /// Dica de linguagem (extensão), para highlight futuro.
  final String? language;
}

/// Imagem (PNG/JPEG/SVG/…) — só o caminho; o widget carrega.
final class FileViewImage extends FileView {
  const FileViewImage(this.path);
  final String path;
}

/// Áudio (mp3/wav/flac/…) — só o caminho; o player (media_kit) carrega. Plano 46.
final class FileViewAudio extends FileView {
  const FileViewAudio(this.path);
  final String path;
}

/// Vídeo (mp4/mov/mkv/…) — só o caminho; o player (media_kit) carrega. Plano 46.
final class FileViewVideo extends FileView {
  const FileViewVideo(this.path);
  final String path;
}

/// Binário/grande demais — **não abre**.
final class FileViewUnsupported extends FileView {
  const FileViewUnsupported();
}
