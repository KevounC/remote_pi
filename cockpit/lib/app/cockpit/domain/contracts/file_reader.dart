import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';

/// Lê e classifica um arquivo para o viewer (markdown / texto / imagem /
/// não-suportado). Contrato no domínio; impl (dart:io) em `data/filesystem/`.
abstract class FileReader {
  Future<FileView> read(String path);

  /// Grava [content] (utf8) em [path], sobrescrevendo. Retorna `true` no sucesso,
  /// `false` se o IO falhar (sem permissão, disco cheio, path sumiu). Não há
  /// merge nem trava: escrita simultânea do agente é last-write-wins (escopo MVP).
  Future<bool> write(String path, String content);

  /// Emite (`void`) sempre que [path] muda no disco (modify/delete), pra o viewer
  /// reler o conteúdo ao vivo. Stream de longa duração — o consumidor cancela ao
  /// fechar a aba. Se o watch falhar, devolve um stream vazio (sem live-reload,
  /// sem crash).
  Stream<void> watch(String path);
}
