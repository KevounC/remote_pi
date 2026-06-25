import 'dart:io' show Platform;

import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Painel direito (~300px): árvore **read-only** da pasta do **workspace**.
/// Pastas começam **colapsadas** e expandem ao clicar (lazy-load). O botão do
/// header é um **Refresh** (re-lê as pastas abertas pra pegar arquivos novos);
/// ocultar o painel é pelo toggle do topbar.
class FileTreePanel extends StatefulWidget {
  const FileTreePanel({
    super.key,
    required this.rootPath,
    required this.listChildren,
    required this.gitStatusOf,
    required this.onOpenFile,
    required this.onOpenWith,
    required this.onCreateInFolder,
    this.width = 300,
  });

  final String rootPath;
  final Future<List<FileNode>> Function(String path) listChildren;

  /// Status git (cor) de um caminho absoluto — arquivo ou pasta agregada. `null`
  /// = limpo / fora de repo. Recriado a cada build do shell → árvore reativa.
  final GitFileStatus? Function(String absolutePath) gitStatusOf;

  /// Duplo-clique num arquivo → abre no pane.
  final ValueChanged<String> onOpenFile;

  /// "Open with" do menu de contexto → abre o arquivo no app padrão do SO.
  final ValueChanged<String> onOpenWith;

  /// Menu de contexto de uma **pasta**: cria uma aba (agente/terminal) nela. O
  /// 1º arg é o caminho relativo à raiz do workspace; o 2º, `true` = terminal.
  final void Function(String relativeSub, bool terminal) onCreateInFolder;

  /// Largura do painel (arrastável pela página — não persistido).
  final double width;

  @override
  State<FileTreePanel> createState() => _FileTreePanelState();
}

class _FileTreePanelState extends State<FileTreePanel> {
  int _refresh = 0;
  String? _selectedPath;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(left: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.only(left: 14, right: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined, size: 15, color: colors.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Files',
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.title.copyWith(
                      fontSize: 13,
                      color: colors.text,
                    ),
                  ),
                ),
                Tooltip(
                  tooltip: (context) =>
                      const TooltipContainer(child: Text('Refresh')),
                  child: HoverTap(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () => setState(() => _refresh++),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(Icons.refresh, size: 16, color: colors.text3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.rootPath.isEmpty
                ? Center(
                    child: Text(
                      'No folder — open a workspace.',
                      textAlign: TextAlign.center,
                      style: context.typo.label.copyWith(color: colors.text3),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 6,
                    ),
                    child: _DirView(
                      path: widget.rootPath,
                      rootPath: widget.rootPath,
                      depth: 0,
                      refreshToken: _refresh,
                      selectedPath: _selectedPath,
                      onSelect: (p) => setState(() => _selectedPath = p),
                      onOpenFile: widget.onOpenFile,
                      onOpenWith: widget.onOpenWith,
                      onCreateInFolder: widget.onCreateInFolder,
                      listChildren: widget.listChildren,
                      gitStatusOf: widget.gitStatusOf,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Carrega os filhos de uma pasta e os renderiza. Re-lê quando [refreshToken]
/// muda (o Refresh do header).
class _DirView extends StatefulWidget {
  const _DirView({
    required this.path,
    required this.rootPath,
    required this.depth,
    required this.refreshToken,
    required this.selectedPath,
    required this.onSelect,
    required this.onOpenFile,
    required this.onOpenWith,
    required this.onCreateInFolder,
    required this.listChildren,
    required this.gitStatusOf,
  });

  final String path;
  final String rootPath;
  final int depth;
  final int refreshToken;
  final String? selectedPath;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String> onOpenWith;
  final void Function(String relativeSub, bool terminal) onCreateInFolder;
  final Future<List<FileNode>> Function(String path) listChildren;
  final GitFileStatus? Function(String absolutePath) gitStatusOf;

  @override
  State<_DirView> createState() => _DirViewState();
}

class _DirViewState extends State<_DirView> {
  List<FileNode>? _children;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DirView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    final children = await widget.listChildren(widget.path);
    if (mounted) setState(() => _children = children);
  }

  @override
  Widget build(BuildContext context) {
    final children = _children;
    if (children == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final node in children)
          if (node.isDirectory)
            _Folder(
              node: node,
              rootPath: widget.rootPath,
              depth: widget.depth,
              refreshToken: widget.refreshToken,
              selectedPath: widget.selectedPath,
              onSelect: widget.onSelect,
              onOpenFile: widget.onOpenFile,
              onOpenWith: widget.onOpenWith,
              onCreateInFolder: widget.onCreateInFolder,
              listChildren: widget.listChildren,
              gitStatusOf: widget.gitStatusOf,
            )
          else
            // Arrasta o arquivo até o input (vira `@<rel>`). Clique-arraste
            // direto — no desktop a árvore rola pela roda/trackpad, não por
            // arraste na linha, então não há conflito.
            Draggable<String>(
              data: node.path,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: _FileChip(name: node.name),
              child: _Row(
                depth: widget.depth,
                isFolder: false,
                name: node.name,
                path: node.path,
                rootPath: widget.rootPath,
                selected: node.path == widget.selectedPath,
                gitStatus: widget.gitStatusOf(node.path),
                onTap: () => widget.onSelect(node.path),
                onDoubleTap: () => widget.onOpenFile(node.path),
                onOpenWith: () => widget.onOpenWith(node.path),
              ),
            ),
      ],
    );
  }
}

class _Folder extends StatefulWidget {
  const _Folder({
    required this.node,
    required this.rootPath,
    required this.depth,
    required this.refreshToken,
    required this.selectedPath,
    required this.onSelect,
    required this.onOpenFile,
    required this.onOpenWith,
    required this.onCreateInFolder,
    required this.listChildren,
    required this.gitStatusOf,
  });

  final FileNode node;
  final String rootPath;
  final int depth;
  final int refreshToken;
  final String? selectedPath;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String> onOpenWith;
  final void Function(String relativeSub, bool terminal) onCreateInFolder;
  final Future<List<FileNode>> Function(String path) listChildren;
  final GitFileStatus? Function(String absolutePath) gitStatusOf;

  @override
  State<_Folder> createState() => _FolderState();
}

class _FolderState extends State<_Folder> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          depth: widget.depth,
          isFolder: true,
          expanded: _expanded,
          name: widget.node.name,
          path: widget.node.path,
          rootPath: widget.rootPath,
          selected: widget.node.path == widget.selectedPath,
          gitStatus: widget.gitStatusOf(widget.node.path),
          onCreateInFolder: widget.onCreateInFolder,
          // "Abrir no explorador do SO" (Finder/Explorer/Nautilus) — abre a
          // pasta no gerenciador de arquivos padrão.
          onOpenWith: () => widget.onOpenWith(widget.node.path),
          // Clicar numa pasta seleciona E expande/recolhe.
          onTap: () {
            widget.onSelect(widget.node.path);
            setState(() => _expanded = !_expanded);
          },
        ),
        if (_expanded)
          _DirView(
            path: widget.node.path,
            rootPath: widget.rootPath,
            depth: widget.depth + 1,
            refreshToken: widget.refreshToken,
            selectedPath: widget.selectedPath,
            onSelect: widget.onSelect,
            onOpenFile: widget.onOpenFile,
            onOpenWith: widget.onOpenWith,
            onCreateInFolder: widget.onCreateInFolder,
            listChildren: widget.listChildren,
            gitStatusOf: widget.gitStatusOf,
          ),
      ],
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.depth,
    required this.isFolder,
    required this.name,
    required this.path,
    required this.rootPath,
    this.gitStatus,
    this.expanded = false,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onOpenWith,
    this.onCreateInFolder,
  });

  final int depth;
  final bool isFolder;
  final String name;
  final String path;
  final String rootPath;

  /// Status git desta linha (cor). `null` = limpo / fora de repo.
  final GitFileStatus? gitStatus;

  final bool expanded;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Só em arquivos: "Open with" → abre no app padrão do SO.
  final VoidCallback? onOpenWith;

  /// Só em pastas: cria agente/terminal nela (relativo, terminal?).
  final void Function(String relativeSub, bool terminal)? onCreateInFolder;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  DateTime? _lastTap;

  /// Caminho relativo à raiz do workspace.
  String get _relative {
    final root = widget.rootPath.endsWith('/')
        ? widget.rootPath
        : '${widget.rootPath}/';
    return widget.path.startsWith(root)
        ? widget.path.substring(root.length)
        : widget.path;
  }

  /// Detecção manual de duplo-clique: o primeiro clique seleciona na hora (sem
  /// o atraso do recognizer de double-tap); o segundo, dentro da janela, abre.
  void _handleTap() {
    if (widget.onDoubleTap == null) {
      widget.onTap?.call();
      return;
    }
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!).inMilliseconds < 350) {
      _lastTap = null;
      widget.onDoubleTap!();
    } else {
      _lastTap = now;
      widget.onTap?.call();
    }
  }

  /// Rótulo do "abrir no explorador do SO" (a ação `open`/`xdg-open`/`start`
  /// abre a pasta no gerenciador de arquivos padrão).
  String get _fileExplorerLabel {
    if (Platform.isMacOS) return 'Open in Finder';
    if (Platform.isWindows) return 'Open in Explorer';
    return 'Open in file manager';
  }

  void _showMenu(BuildContext context, Offset globalPosition) {
    final canCreate = widget.isFolder && widget.onCreateInFolder != null;
    final isFile = !widget.isFolder;
    showAppMenu<String>(
      context,
      minWidth: 220,
      globalPosition: globalPosition,
      items: [
        if (isFile) ...const [
          AppMenuItem(value: 'open', label: 'Open', icon: Icons.open_in_new),
          AppMenuItem(
            value: 'openwith',
            label: 'Open with',
            icon: Icons.launch_outlined,
          ),
        ],
        if (canCreate) ...const [
          AppMenuItem(
            value: 'agent',
            label: 'Create agent',
            icon: Icons.auto_awesome,
          ),
          AppMenuItem(
            value: 'terminal',
            label: 'Create terminal',
            icon: Icons.terminal_outlined,
          ),
        ],
        if (widget.isFolder)
          AppMenuItem(
            value: 'reveal',
            label: _fileExplorerLabel,
            icon: Icons.folder_open_outlined,
          ),
        const AppMenuItem(
          value: 'rel',
          label: 'Copy relative path',
          icon: Icons.content_copy_outlined,
        ),
        const AppMenuItem(
          value: 'abs',
          label: 'Copy absolute path',
          icon: Icons.content_copy,
        ),
      ],
    ).then((value) {
      switch (value) {
        case 'open':
          // "Open" = abrir no pane (mesma ação do duplo-clique no arquivo).
          widget.onDoubleTap?.call();
        case 'openwith':
        case 'reveal':
          widget.onOpenWith?.call();
        case 'agent':
          widget.onCreateInFolder?.call(_relative, false);
        case 'terminal':
          widget.onCreateInFolder?.call(_relative, true);
        case 'rel':
          Clipboard.setData(ClipboardData(text: _relative));
        case 'abs':
          Clipboard.setData(ClipboardData(text: widget.path));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onSecondaryTapUp: (d) => _showMenu(context, d.globalPosition),
      child: HoverTap(
        color: widget.selected ? colors.panel2 : Colors.transparent,
        hoverColor: colors.panel,
        borderRadius: BorderRadius.circular(5),
        onTap: _handleTap,
        padding: EdgeInsets.only(left: 6 + widget.depth * 14.0, right: 6),
        child: SizedBox(
          height: 26,
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: widget.isFolder
                    ? Icon(
                        widget.expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.chevron_right,
                        size: 15,
                        color: colors.text4,
                      )
                    : null,
              ),
              const SizedBox(width: 2),
              // Ícone colorido por tipo (material-icon-theme). Pastas variam
              // entre aberta/fechada; sem tint (a seleção vem do fundo/texto).
              widget.isFolder
                  ? FileTypeIcon.folder(
                      widget.name,
                      open: widget.expanded,
                      size: 16,
                    )
                  : FileTypeIcon.file(widget.name, size: 16),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  widget.name,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.body.copyWith(
                    fontSize: 13,
                    color: _gitColor(colors, widget.gitStatus) ??
                        (widget.selected ? colors.text : colors.text2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cor do nome conforme o status git da linha (`null` = sem tint git → a linha
/// usa a cor neutra de seleção). Modificado reusa `warn` (âmbar, mesma da
/// branch); os demais têm tokens próprios.
Color? _gitColor(AppColors colors, GitFileStatus? status) {
  switch (status) {
    case null:
      return null;
    case GitFileStatus.modified:
      return colors.warn;
    case GitFileStatus.staged:
      return colors.gitStaged;
    case GitFileStatus.untracked:
      return colors.gitUntracked;
    case GitFileStatus.deleted:
      return colors.gitDeleted;
    case GitFileStatus.conflict:
      return colors.gitConflict;
  }
}

/// Chip que segue o cursor ao arrastar um arquivo do painel pro input.
class _FileChip extends StatelessWidget {
  const _FileChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.accent),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alternate_email, size: 13, color: colors.accentText),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: context.typo.body.copyWith(
                fontSize: 12.5,
                color: colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
