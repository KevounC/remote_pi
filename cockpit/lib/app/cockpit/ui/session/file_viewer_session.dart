import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';

/// Uma aba de viewer read-only de arquivo (texto/markdown/imagem). O conteúdo
/// ([view]) já vem classificado/lido pela VM (binário/vídeo nem chega aqui).
class FileViewerSession extends PaneItem {
  FileViewerSession({
    required this.id,
    required this.projectId,
    required this.path,
    required this.view,
  }) : title = path.split('/').where((p) => p.isNotEmpty).last,
       workingDirectory = path.contains('/')
           ? path.substring(0, path.lastIndexOf('/'))
           : path;

  @override
  final String id;
  @override
  final String projectId;
  @override
  final String title;
  @override
  final String workingDirectory;

  final String path;

  /// Conteúdo atual. **Mutável**: a VM reatribui ao detectar mudança no disco
  /// (file watcher — plan/42 follow-up), e o `notifyListeners` reconstrói a aba.
  FileView view;

  /// `true` quando o editor tem alterações não gravadas. Dirige o indicador da
  /// aba (bolinha no lugar do X) e o dialog de "fechar sem salvar". O `FileViewer`
  /// atualiza via [setDirty]; a aba escuta esta sessão (ChangeNotifier).
  bool dirty = false;

  void setDirty(bool value) {
    if (value == dirty) return;
    dirty = value;
    notifyListeners();
  }

  /// Grava o buffer atual do editor em disco. Registrado pelo `FileViewer`
  /// enquanto montado (e limpo ao desmontar); `null` quando não há editor ativo.
  /// Usado pelo "Salvar e fechar". Retorna `true` no sucesso.
  Future<bool> Function()? saveDraft;
}
