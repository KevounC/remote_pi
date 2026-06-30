import 'dart:async';
import 'dart:io' show Directory, FileSystemEvent;
import 'dart:math' show max;

import 'package:cockpit/app/cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_searcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_mutator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/folder_lister.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/launchable_app.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/session_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document_commands.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/workspace_projection.dart';
import 'package:flutter/foundation.dart';

/// Controlador do shell: projetos, árvore de splits **por projeto**, sessões de
/// agente, foco.
///
/// Cada projeto (workspace) tem o seu próprio documento ([WorkspaceDocument] em
/// [_documents]); trocar de projeto só troca qual árvore é exibida (o `IndexedStack`
/// na página mantém todas montadas → estado preservado). As abas/processos vivos
/// vivem em [_workspace] e seguem rodando independente da UI.
///
/// As operações de pane agem no **projeto ativo** ([_selectedProjectId]) — o
/// `IndexedStack` garante que só o projeto ativo é interativo.
class CockpitViewModel extends ChangeNotifier {
  CockpitViewModel(
    ProjectRepository projects,
    RpcGatewayFactory rpcFactory,
    FolderLister folders,
    SessionHistory history,
    Notifier notifier,
    FileSystemReader fileSystem,
    TerminalGatewayFactory terminalFactory,
    FileReader fileReader,
    WorkspaceLayoutStore layoutStore,
    GitStatusReader gitReader,
    FileSearcher fileSearcher,
    AppLauncherGateway launcher,
    WorktreeManager worktreeMgr,
    FileSystemMutator fileMutator,
    LspServerPool lsp,
  ) : _projects = projects,
      _folders = folders,
      _history = history,
      _fileSystem = fileSystem,
      _layoutStore = layoutStore,
      _gitReader = gitReader,
      _fileSearcher = fileSearcher,
      _launcher = launcher,
      _worktreeMgr = worktreeMgr,
      _fileMutator = fileMutator,
      _lsp = lsp {
    _workspace = WorkspaceProjection(
      rpcFactory: rpcFactory,
      terminalFactory: terminalFactory,
      fileReader: fileReader,
      history: history,
      notifier: notifier,
      lsp: lsp,
      onChanged: notifyListeners,
      onAgentTurnEnd: _onAgentTurnEnd,
      onDescriptorChanged: _scheduleSave,
    );
  }

  final ProjectRepository _projects;
  final FolderLister _folders;
  final SessionHistory _history;
  final FileSystemReader _fileSystem;
  final WorkspaceLayoutStore _layoutStore;
  final GitStatusReader _gitReader;
  final FileSearcher _fileSearcher;
  final AppLauncherGateway _launcher;
  final WorktreeManager _worktreeMgr;
  final FileSystemMutator _fileMutator;
  final LspServerPool _lsp;
  late final WorkspaceProjection _workspace;

  List<LaunchableApp> _availableApps = const [];

  final List<Project> _projectList = <Project>[];
  String? _selectedProjectId;

  /// Documento de workspace por projeto (pane tree + foco + descritores de abas).
  final Map<String, WorkspaceDocument> _documents =
      <String, WorkspaceDocument>{};

  /// Documentos de layout carregados do Hive no boot (lazy: o projeto só é
  /// reconstruído quando selecionado). `null` = projeto sem layout salvo.
  final Map<String, Map<String, dynamic>?> _savedLayouts =
      <String, Map<String, dynamic>?>{};

  /// Debounce de gravação por projeto (o resize é arrasto contínuo).
  final Map<String, Timer> _saveTimers = <String, Timer>{};

  /// `true` enquanto reconstruímos um projeto — evita gravar layout meio-feito.
  bool _restoring = false;

  /// Estado git por projeto (branch + sujos). `null` (ausente do mapa ou valor
  /// null) = não é repo git → a rail mostra só o título.
  final Map<String, GitInfo?> _gitInfo = <String, GitInfo?>{};

  /// Status git por **caminho relativo** (arquivos + pastas agregadas), por
  /// projeto. Derivado de [_gitInfo]; alimenta a coloração da árvore de
  /// arquivos. Pasta agrega o estado mais forte dos descendentes ([
  /// GitFileStatus.strongest]).
  final Map<String, Map<String, GitFileStatus>> _gitTree =
      <String, Map<String, GitFileStatus>>{};

  /// Watcher do working tree do projeto **selecionado** (filesystem ao vivo).
  /// Recriado ao trocar de projeto; debounce junta rajadas de eventos.
  StreamSubscription<FileSystemEvent>? _gitWatch;
  Timer? _gitWatchDebounce;
  String? _gitWatchPath;

  /// Worktrees (forks) por workspace raiz, na ordem do `git worktree list`
  /// (decisão 20). Reconciliado contra o git nos ganchos de refresh; a
  /// existência mora no git, não no Hive (decisões 4, 17). Os mesmos `Project`s
  /// também entram em [_projectList] (pro IndexedStack e o lookup).
  final Map<String, List<Project>> _worktrees = <String, List<Project>>{};

  /// Sobe a cada mutação na árvore (criar/renomear/deletar) — a `FileTreePanel`
  /// lê isso como token de refresh pra reler as pastas abertas (passo 3 da UI).
  int _fileTreeRevision = 0;
  int get fileTreeRevision => _fileTreeRevision;

  /// Caminho do arquivo atualmente selecionado no FileTreePanel (para highlight).
  String? _selectedFileInTree;
  String? get selectedFileInTree => _selectedFileInTree;

  bool _railVisible = true;
  bool _treeVisible = true;
  bool _ready = false;
  int _seq = 0;

  /// Espelha `AppSettings.notificationsEnabled` (app-scoped, fora do grafo desta
  /// VM page-scoped). A `CockpitPage` empurra o valor do `SettingsController`.
  /// Gateia o disparo de notificação de fim de turno.
  bool _notificationsEnabled = true;
  void setNotificationsEnabled(bool value) => _notificationsEnabled = value;

  /// Paleta dos avatares de projeto (cores do design).
  static const List<int> _palette = <int>[
    0xFF6E56CF,
    0xFFE5484D,
    0xFF1AA5A0,
    0xFF3FB868,
    0xFFE0A33A,
    0xFF2F6FF0,
  ];

  String _nid(String prefix) => '$prefix${_seq++}';

  // ---- getters --------------------------------------------------------------
  List<Project> get projects => List<Project>.unmodifiable(_projectList);

  /// Só os workspaces raiz (sem as worktrees) — o nível de topo do rail.
  List<Project> get rootProjects {
    final roots = _projectList.where((p) => p.parentId == null).toList();
    // Ordem manual do usuário (drag-drop); createdAt como desempate/fallback.
    roots.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return List<Project>.unmodifiable(roots);
  }

  /// Worktrees (forks) de um workspace raiz, na ordem do git (vazio se nenhuma).
  List<Project> worktreesOf(String rootId) =>
      _worktrees[rootId] ?? const <Project>[];

  String? get selectedProjectId => _selectedProjectId;
  Project? get selectedProject => _projectById(_selectedProjectId);

  /// Título pro topbar: `"<workspace> · <worktree>"` quando um fork está
  /// selecionado (separador middle-dot U+00B7); só o nome do workspace caso
  /// contrário. `null` quando nada está selecionado.
  String? get selectedDisplayTitle {
    final p = selectedProject;
    if (p == null) return null;
    final parentId = p.parentId;
    if (parentId == null) return p.name;
    final root = _projectById(parentId);
    return root == null ? p.name : '${root.name} · ${p.name}';
  }

  /// `false` até [init] terminar de carregar os projetos do Hive.
  bool get ready => _ready;
  bool get railVisible => _railVisible;
  bool get treeVisible => _treeVisible;
  List<LaunchableApp> get availableApps =>
      List<LaunchableApp>.unmodifiable(_availableApps);
  PaneItem? session(String id) => _workspace.item(id);

  /// Estado git do projeto (branch + sujos), ou `null` se não for repo git.
  GitInfo? gitInfo(String projectId) => _gitInfo[projectId];

  /// Status git (cor) de um caminho **absoluto** dentro do projeto selecionado —
  /// arquivo ou pasta (agregada). `null` = limpo/fora de repo. Usado pela árvore
  /// de arquivos pra colorir cada linha.
  GitFileStatus? gitStatusForPath(String absolutePath) {
    final pid = _selectedProjectId;
    if (pid == null) return null;
    final root = _projectById(pid)?.path;
    if (root == null) return null;
    final rel = _subOf(absolutePath, root);
    if (rel.isEmpty) return null;
    // Mudança real (mapa agregado) vence; senão herda da raiz colapsada que
    // cobre este caminho — pasta untracked nova vs. ignorado.
    final dirty = _gitTree[pid]?[rel];
    if (dirty != null) return dirty;
    final info = _gitInfo[pid];
    if (info == null) return null;
    if (info.isUntracked(rel)) return GitFileStatus.untracked;
    if (info.isIgnored(rel)) return GitFileStatus.ignored;
    return null;
  }

  /// Aba que o usuário está olhando.
  PaneItem? get focusedAgent {
    final id = _focusedAgentId;
    return id == null ? null : _workspace.item(id);
  }

  /// Filhos de uma pasta (lazy-load da árvore de arquivos).
  Future<List<FileNode>> listChildren(String path) =>
      _fileSystem.children(path);

  /// Arquivos de [cwd] que casam com [query] (autocomplete do `@`). Caminhos
  /// relativos a [cwd].
  Future<List<String>> searchFiles(String cwd, String query) =>
      _fileSearcher.search(cwd, query);

  /// Abre um arquivo num viewer. Sem [inPane], usa a pane focada (duplo-clique
  /// na árvore); com [inPane], abre naquela pane e a foca (arrastar arquivo →
  /// pane). Binário/vídeo/grande demais → não abre.
  ///
  /// Se [isPreview] for `true` (padrão), usa o comportamento VSCode:
  /// - Se já existe um preview aberto na pane, substitui o conteúdo
  /// - Se a aba ativa é um preview, substitui em vez de criar nova aba
  /// - Duplo-clique deve passar `isPreview: false` para criar aba normal
  Future<void> openFile(
    String path, {
    String? inPane,
    bool isPreview = true,
  }) async {
    final document = _activeDocument;
    final projectId = document?.projectId;
    final paneId =
        inPane ?? (projectId == null ? null : focusedPaneId(projectId));
    if (document == null || projectId == null || paneId == null) return;
    final leaf = findLeaf(document.root, paneId);
    if (leaf == null) return;

    // Se isPreview, tenta reutilizar a aba de preview existente ou substituir a ativa.
    // Se não é preview, cria uma aba normal (comportamento original).
    FileViewerSession? previewCandidate;
    for (final tabId in leaf.tabs) {
      final item = _workspace.item(tabId);
      if (item is FileViewerSession) {
        // Se já aberto, só seleciona (mas transforma preview em normal se não é preview).
        if (item.path == path) {
          if (!isPreview && item.isPreview) item.pin();
          _applyWorkspaceCommand(
            (doc) => WorkspaceDocumentCommands.selectTab(
              doc,
              paneId: paneId,
              tabId: tabId,
            ),
          );
          return;
        }
        // Guarda o primeiro preview encontrado para possível reutilização.
        if (isPreview && item.isPreview && previewCandidate == null) {
          previewCandidate = item;
        }
      }
    }

    // Se é preview e temos um candidato, reutiliza (substitui conteúdo).
    if (isPreview && previewCandidate != null) {
      final replaced = await _workspace.replaceViewerPath(
        previewCandidate.id,
        path,
      );
      if (!replaced) return;
      _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.replaceTab(
          doc,
          paneId: paneId,
          oldTabId: previewCandidate!.id,
          newTab: WorkspaceTab.viewer(id: previewCandidate.id, filePath: path),
          disposeOldTab: false,
        ),
      );
      return;
    }

    // Cria nova aba (preview ou normal).
    final viewer = await _workspace.createViewer(
      id: _nid('v'),
      projectId: projectId,
      path: path,
      isPreview: isPreview,
    );
    if (viewer == null) return; // binário/vídeo/grande demais: não abre
    final viewerTab = WorkspaceTab.viewer(id: viewer.id, filePath: path);

    // Se a pane só tem o placeholder vazio, substitui; senão adiciona aba.
    // Se é preview e a aba ativa é um FileViewer, substitui em vez de adicionar.
    final current = _activeDocument?.root ?? document.root;
    final lf = findLeaf(current, paneId);
    final activeTabId = lf?.active;
    final activeTab = activeTabId == null ? null : _workspace.item(activeTabId);
    final only = lf?.tabs.length == 1 ? _workspace.item(lf!.tabs.first) : null;

    late final bool applied;
    if (isPreview && activeTab is FileViewerSession && !activeTab.isPreview) {
      // Preview substituiria aba normal → adiciona ao lado.
      applied = _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.appendTab(
          doc,
          paneId: paneId,
          tab: viewerTab,
        ),
      );
    } else if (isPreview &&
        activeTab is FileViewerSession &&
        activeTab.isPreview) {
      // Preview substituir outro preview → substitui a aba ativa.
      applied = _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.replaceActiveTab(
          doc,
          paneId: paneId,
          newTab: viewerTab,
        ),
      );
    } else if (lf != null && only is AgentSession && only.isPlaceholder) {
      // Placeholder vazio → substitui.
      applied = _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.replaceTab(
          doc,
          paneId: paneId,
          oldTabId: lf.tabs.first,
          newTab: viewerTab,
        ),
      );
    } else {
      // Adiciona nova aba.
      applied = _applyWorkspaceCommand(
        (doc) => WorkspaceDocumentCommands.appendTab(
          doc,
          paneId: paneId,
          tab: viewerTab,
        ),
      );
    }
    if (!applied) _workspace.disposeTab(viewer.id);
  }

  /// Seleciona um arquivo no FileTreePanel (atualiza o highlight).
  void selectFileInTree(String path) {
    _selectedFileInTree = path;
    notifyListeners();
  }

  /// Grava o conteúdo editado de uma aba de viewer em disco e reclassifica o
  /// `view` (markdown/texto/linguagem) com o conteúdo salvo. Retorna `true` no
  /// sucesso. Sem trava: escrita concorrente do agente é last-write-wins (MVP).
  Future<bool> saveFile(String sessionId, String content) =>
      _workspace.saveViewer(sessionId, content);

  // ---- LSP (diagnostics + formatação) ---------------------------------------

  /// Diagnostics de todos os language servers (mesclados). O `FileViewer` filtra
  /// pelo `uri` do seu documento. Ver [LspServerPool].
  Stream<LspDiagnosticsBatch> get lspDiagnostics => _lsp.diagnostics;

  /// Abre [path] no LSP (didOpen). O fallback de raiz é o caminho do projeto —
  /// usado quando o walk-up de marcadores não acha raiz (ex.: arquivo solto).
  Future<void> lspOpenDocument(String path, String text, String projectId) =>
      _lsp.openDocument(
        path: path,
        text: text,
        fallbackRoot: _projectById(projectId)?.path,
      );

  /// Notifica edição (didChange, full sync).
  Future<void> lspChangeDocument(String path, String text) =>
      _lsp.changeDocument(path: path, text: text);

  /// Fecha o documento no LSP (didClose + refcount).
  Future<void> lspCloseDocument(String path) => _lsp.closeDocument(path);

  /// Aplica os overrides de comando do LSP (da tela "Language") no pool. Vale
  /// para os próximos servidores spawnados; os já vivos seguem com o comando
  /// anterior até reiniciarem.
  void applyLspCommands(Map<String, String> commands) {
    _lsp.commandOverrides = commands;
  }

  /// Pulsos de mudança de estado de servidores LSP (subiu/caiu/reiniciou). A
  /// barra de status escuta isto pra atualizar ao vivo.
  Stream<void> get lspStatusChanges => _lsp.statusChanges;

  /// Caminho do arquivo da aba focada, se for um viewer; senão `null` (a aba é
  /// agente/terminal). Usado pela barra de status do LSP.
  String? get focusedFilePath {
    final s = focusedAgent;
    return s is FileViewerSession ? s.path : null;
  }

  /// Estado do LSP do arquivo focado (linguagem + rodando), ou `null` se a aba
  /// não é um arquivo de código suportado → a barra fica vazia.
  LspDocStatus? get focusedLspStatus {
    final path = focusedFilePath;
    return path == null ? null : _lsp.statusForPath(path);
  }

  /// Reinicia o servidor LSP do arquivo focado.
  Future<void> restartFocusedLsp() async {
    final path = focusedFilePath;
    if (path == null) return;
    await _lsp.restartForPath(path);
    notifyListeners();
  }

  /// Reinicia os servidores de uma linguagem (após salvar novo comando na tela
  /// "Language") — aplica a mudança nos servidores já vivos.
  Future<void> restartLspLanguage(String languageId) async {
    await _lsp.restartLanguage(languageId);
    notifyListeners();
  }

  /// Formata [path] via LSP. Faz um `didChange` com [text] antes (flush do
  /// debounce) pra o servidor formatar o conteúdo mais recente, e devolve os
  /// edits a aplicar no buffer. Lista vazia = sem servidor / sem suporte / erro.
  Future<List<LspTextEdit>> lspFormat(String path, String text) async {
    await _lsp.changeDocument(path: path, text: text);
    return _lsp.formatDocument(path);
  }

  // ---- mutação de arquivos (criar / renomear / deletar) ---------------------

  /// Cria um arquivo vazio chamado [name] dentro de [dirPath] e o abre no pane
  /// (quando [open]). Valida o nome (não-vazio, sem `/`). Devolve a falha
  /// (mensagem) pra UI mostrar inline. Refaz a árvore no sucesso.
  Future<Result<void, String>> createFileIn(
    String dirPath,
    String name, {
    bool open = true,
  }) async {
    final invalid = _validateName(name);
    if (invalid != null) return Failure(invalid);
    final path = _join(dirPath, name.trim());
    final r = await _fileMutator.createFile(path);
    if (r.isSuccess) {
      _bumpFileTree();
      if (open) await openFile(path);
    }
    return r;
  }

  /// Cria uma pasta [name] dentro de [dirPath]. Refaz a árvore no sucesso.
  Future<Result<void, String>> createDirIn(String dirPath, String name) async {
    final invalid = _validateName(name);
    if (invalid != null) return Failure(invalid);
    final r = await _fileMutator.createDirectory(_join(dirPath, name.trim()));
    if (r.isSuccess) _bumpFileTree();
    return r;
  }

  /// Renomeia [path] para [newName] (mesma pasta). As abas abertas do arquivo
  /// (ou de descendentes, se for pasta) **seguem** o novo caminho.
  Future<Result<void, String>> renamePath(String path, String newName) async {
    final invalid = _validateName(newName);
    if (invalid != null) return Failure(invalid);
    final to = _join(_parentOf(path), newName.trim());
    final r = await _fileMutator.rename(path, to);
    if (r.isSuccess) {
      await _retargetSessions(path, to);
      _bumpFileTree();
    }
    return r;
  }

  /// Manda [path] pra lixeira. **Fecha antes** as abas do arquivo (ou de tudo
  /// dentro da pasta), sem prompt de salvar — a deleção sobrepõe.
  Future<Result<void, String>> deletePath(String path) async {
    _closeSessionsUnder(path);
    final r = await _fileMutator.moveToTrash(path);
    if (r.isSuccess) _bumpFileTree();
    return r;
  }

  void _bumpFileTree() {
    _fileTreeRevision++;
    notifyListeners();
  }

  /// `null` se válido; senão a mensagem do erro. Nesta fase: sem aninhar (`/`).
  String? _validateName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Name cannot be empty.';
    if (n.contains('/')) return 'Name cannot contain “/”.';
    if (n == '.' || n == '..') return 'Invalid name.';
    return null;
  }

  String _join(String dir, String name) {
    final base = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
    return '$base/$name';
  }

  String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? path : path.substring(0, i);
  }

  /// Um caminho é "sob" [root] se for ele mesmo ou um descendente (`root/...`).
  bool _isUnder(String path, String root) =>
      path == root || path.startsWith('$root/');

  /// Reaponta as abas de viewer afetadas por um rename de [from] → [to]: o
  /// próprio arquivo e, se [from] for pasta, todos os descendentes (troca de
  /// prefixo). Re-lê o conteúdo e re-arma o watcher no novo caminho.
  Future<void> _retargetSessions(String from, String to) =>
      _workspace.retargetViewersUnder(from, to);

  /// Fecha (no projeto ativo) toda aba de viewer cujo arquivo está em/sob [path].
  /// Coleta os pares (pane, aba) antes de fechar pra não mutar a árvore durante
  /// a varredura. (Multi-projeto fica pra depois — a árvore opera no ativo.)
  void _closeSessionsUnder(String path) {
    final tree = _activeTree;
    if (tree == null) return;
    final targets = <(String, String)>[];
    for (final leaf in leaves(tree)) {
      for (final tabId in leaf.tabs) {
        final s = _workspace.item(tabId);
        if (s is FileViewerSession && _isUnder(s.path, path)) {
          targets.add((leaf.id, tabId));
        }
      }
    }
    for (final (paneId, tabId) in targets) {
      closeTab(paneId, tabId);
    }
  }

  /// Árvore do projeto (para renderizar cada folha do `IndexedStack`).
  PaneNode? tree(String projectId) => _documents[projectId]?.root;

  /// Pane focada do projeto.
  String? focusedPaneId(String projectId) =>
      _documents[projectId]?.focusedPaneId;

  /// Nº de agentes do workspace que terminaram um turno e ainda não foram
  /// vistos (badge de notificações).
  int notificationCount(String projectId) => _workspace.items.where((item) {
    if (item is! AgentSession) return false;
    return item.projection.projectId == projectId && item.unseenFinish;
  }).length;

  // ---- init -----------------------------------------------------------------
  Future<void> init() async {
    _projectList.addAll(await _projects.all());
    // Carrega os layouts salvos (mas não reconstrói nada ainda — lazy).
    for (final project in _projectList) {
      _savedLayouts[project.id] = await _layoutStore.load(project.id);
    }
    _selectedProjectId = await _initialSelection();
    // Só o projeto selecionado é ativado (sobe os processos) no boot.
    final selected = _selectedProjectId;
    if (selected != null) await _activateProject(selected);
    _startGitWatch(selected); // watcher ao vivo do projeto inicial
    _ready = true;
    notifyListeners();
    // Estado git + worktrees de todos os projetos (assíncrono — a rail atualiza
    // conforme chega). Só há raízes no boot; os forks entram pela reconciliação.
    for (final project in _projectList) {
      unawaited(_refreshGit(project.id));
      unawaited(_refreshWorktrees(project.id));
    }
    // Detecta IDEs instaladas (assíncrono — topbar atualiza ao chegar).
    unawaited(
      _launcher.probe().then((apps) {
        _availableApps = apps;
        notifyListeners();
      }),
    );
  }

  /// Workspace a pré-selecionar no boot: o último selecionado (se ainda existir);
  /// senão — ou se der erro ao ler a preferência — o primeiro. `null` se vazio.
  Future<String?> _initialSelection() async {
    final roots = rootProjects;
    if (roots.isEmpty) return null;
    try {
      final last = await _projects.loadLastSelected();
      if (last != null && roots.any((p) => p.id == last)) return last;
    } catch (_) {
      // erro ao ler a preferência → fallback silencioso pro primeiro.
    }
    return roots.first.id;
  }

  /// Abre a pasta do projeto selecionado no [app] informado.
  Future<void> openProjectInApp(LaunchableApp app) async {
    final project = selectedProject;
    if (project == null) return;
    await _launcher.launch(app, project.path);
  }

  /// Abre [path] no app padrão do SO ("Open with" do menu do file tree).
  Future<void> openWithDefaultApp(String path) =>
      _launcher.openWithDefaultApp(path);

  // ---- projects -------------------------------------------------------------
  /// Cria (ou seleciona, se já existir) um workspace pra [path]. [name] e
  /// [colorValue] permitem sobrescrever os defaults (fluxo "Criar Workspace",
  /// onde o usuário edita nome/cor antes de confirmar).
  Future<Project> addProject(
    String path, {
    String? name,
    int? colorValue,
    String? imagePath,
  }) async {
    for (final existing in _projectList) {
      if (existing.path == path) {
        _selectedProjectId = existing.id;
        unawaited(_projects.saveLastSelected(existing.id));
        notifyListeners();
        return existing;
      }
    }
    final basename = _basename(path);
    final resolvedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (basename.isEmpty ? path : basename);
    // Cor pela contagem de raízes (forks não entram no rodízio da paleta).
    final roots = _projectList.where((p) => p.parentId == null);
    final rootCount = roots.length;
    // Entra no fim da lista (maior order + 1).
    final nextOrder = roots.isEmpty
        ? 0
        : roots.map((p) => p.order).reduce(max) + 1;
    final project = Project(
      id: path, // o caminho é único e estável entre reinícios
      name: resolvedName,
      path: path,
      colorValue: colorValue ?? _palette[rootCount % _palette.length],
      createdAt: DateTime.now(),
      order: nextOrder,
      imagePath: imagePath,
    );
    _projectList.add(project);
    _selectedProjectId = project.id;
    await _projects.save(project);
    unawaited(_projects.saveLastSelected(project.id));
    await _activateProject(project.id); // sem layout salvo → pane vazia
    unawaited(_refreshGit(project.id));
    unawaited(_refreshWorktrees(project.id)); // pode já ter worktrees no disco
    notifyListeners();
    return project;
  }

  /// Altera nome, cor e/ou imagem do projeto e persiste. [imagePath] usa o
  /// sentinel [Project.unchanged] como default — passe `null` para **remover** a
  /// imagem, ou um caminho para defini-la.
  Future<void> updateProject(
    String id, {
    String? name,
    int? colorValue,
    Object? imagePath = Project.unchanged,
  }) async {
    final index = _projectList.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final updated = _projectList[index].copyWith(
      name: name,
      colorValue: colorValue,
      imagePath: imagePath,
    );
    _projectList[index] = updated;
    await _projects.save(updated);
    notifyListeners();
  }

  /// Reordena os workspaces raiz (drag-drop no rail): move [movedId] para antes
  /// ou depois de [targetId] e persiste a nova sequência no campo `order`. As
  /// worktrees acompanham o pai (herdam o `order` na reconciliação).
  Future<void> reorderWorkspace(
    String movedId,
    String targetId, {
    required bool before,
  }) async {
    if (movedId == targetId) return;
    final roots = rootProjects.toList(); // já ordenado por order
    final from = roots.indexWhere((p) => p.id == movedId);
    if (from < 0 || roots.indexWhere((p) => p.id == targetId) < 0) return;
    final moved = roots.removeAt(from);
    var insertAt = roots.indexWhere((p) => p.id == targetId);
    if (!before) insertAt += 1;
    roots.insert(insertAt, moved);
    // Reatribui order sequencial (0..n) e persiste cada raiz.
    for (var i = 0; i < roots.length; i++) {
      final updated = roots[i].copyWith(order: i);
      final idx = _projectList.indexWhere((p) => p.id == updated.id);
      if (idx >= 0) _projectList[idx] = updated;
      await _projects.save(updated);
    }
    notifyListeners();
  }

  Future<void> removeProject(String id) async {
    // Encerra as worktrees do workspace junto (não deixa fork órfão).
    for (final fork in _worktrees.remove(id) ?? const <Project>[]) {
      _disposeProjectRuntime(fork.id);
      _projectList.removeWhere((p) => p.id == fork.id);
    }
    _disposeProjectRuntime(id);
    _projectList.removeWhere((p) => p.id == id);
    if (_selectedProjectId == id || _projectById(_selectedProjectId) == null) {
      _selectedProjectId = rootProjects.isEmpty ? null : rootProjects.first.id;
    }
    await _projects.remove(id);
    await _layoutStore.remove(id);
    final next = _selectedProjectId;
    if (next != null) await _activateProject(next);
    notifyListeners();
  }

  /// Encerra o runtime de um projeto (árvore de panes + sessões + foco + caches),
  /// **sem** mexer em persistência. Usado ao remover um workspace e ao detectar
  /// que uma worktree sumiu (mata `pi` + fecha panes — decisão 9).
  void _disposeProjectRuntime(String id) {
    final document = _documents.remove(id);
    if (document != null) {
      _workspace.disposeProject(document);
    }
    _savedLayouts.remove(id);
    _gitInfo.remove(id);
    _gitTree.remove(id);
    _saveTimers.remove(id)?.cancel();
  }

  /// Cria uma worktree [name] no workspace [rootId] (decisões 2, 3, 14, 15). Em
  /// sucesso, reconcilia, **auto-seleciona** o fork (pane vazia) e o devolve; em
  /// falha, devolve o erro do git pra mostrar inline no dialog (decisão 21).
  Future<Result<Project, WorktreeOpError>> createWorktree(
    String rootId,
    String name,
  ) async {
    final root = _projectById(rootId);
    if (root == null) {
      return const Failure(WorktreeOpError('Workspace not found.'));
    }
    final res = await _worktreeMgr.add(root.path, name);
    switch (res) {
      case Failure(:final error):
        return Failure<Project, WorktreeOpError>(error);
      case Success(:final value):
        // Clona a estrutura (panes/abas/posições) do pai pra o fork: mesma
        // organização, pasta nova, sessões do zero (ver _cloneLayoutForWorktree).
        final clonedLayout = _cloneLayoutForWorktree(rootId);
        await _refreshWorktrees(rootId); // insere o fork em _projectList
        final fork = _projectById(value.path);
        if (fork == null) {
          return const Failure(
            WorktreeOpError(
              'Worktree created, but did not appear in the list.',
            ),
          );
        }
        if (clonedLayout != null) {
          // Vira o layout salvo do fork → _activateProject reconstrói a estrutura
          // apontando pra fork.path. Persiste pra sobreviver a reload.
          _savedLayouts[fork.id] = clonedLayout;
          unawaited(_layoutStore.save(fork.id, clonedLayout));
        }
        selectProject(
          fork.id,
        ); // auto-select → activate → reconstrói a estrutura
        return Success<Project, WorktreeOpError>(fork);
    }
  }

  /// Branches locais + worktrees de [rootId], pra validação ao vivo do dialog
  /// de criar (decisão 11).
  Future<WorktreeNamespace> worktreeNamespace(String rootId) async {
    final root = _projectById(rootId);
    if (root == null) return const WorktreeNamespace.empty();
    return _worktreeMgr.namespace(root.path);
  }

  /// Remove o fork [forkId] (decisão 6): `git worktree remove` + `git branch -D`
  /// via [WorktreeManager.remove]; em sucesso, reconcilia com `_refreshWorktrees`
  /// — a **mesma** rotina do someço externo, que mata os `pi`, fecha as panes e
  /// devolve a seleção pro pai (decisão 9). Em falha, devolve o erro do git pra
  /// mostrar inline.
  Future<Result<void, WorktreeOpError>> removeWorktree(String forkId) async {
    final fork = _projectById(forkId);
    if (fork == null || fork.parentId == null) {
      return const Failure(WorktreeOpError('Worktree not found.'));
    }
    final root = _projectById(fork.parentId);
    if (root == null) {
      return const Failure(WorktreeOpError('Parent workspace not found.'));
    }
    final res = await _worktreeMgr.remove(root.path, fork.path, fork.name);
    if (res.isSuccess) {
      // O fork sai do `git worktree list` → a reconciliação detecta o someço e
      // dispara kill+close+volta-pro-pai (não duplicamos a rotina).
      await _refreshWorktrees(fork.parentId!);
    }
    return res;
  }

  /// `true` se a branch do fork [forkId] já foi mergeada — alimenta o aviso forte
  /// de remoção (decisão 6). Em dúvida/erro, `false` (mostra o aviso por segurança).
  Future<bool> isWorktreeBranchMerged(String forkId) async {
    final fork = _projectById(forkId);
    if (fork == null || fork.parentId == null) return false;
    final root = _projectById(fork.parentId);
    if (root == null) return false;
    return _worktreeMgr.isBranchMerged(root.path, fork.name);
  }

  void selectProject(String id) {
    if (_selectedProjectId == id) return;
    _selectedProjectId = id;
    // Persiste o workspace (raiz) pra pré-selecionar na próxima abertura.
    unawaited(_projects.saveLastSelected(_rootOf(id)));
    _clearFocusedNotification();
    unawaited(_activateProject(id)); // reconstrói (lazy) se ainda não ativo
    _startGitWatch(id); // segue o working tree do novo projeto ao vivo
    unawaited(_refreshGit(id)); // pode ter mudado desde a última vez
    unawaited(_refreshWorktrees(_rootOf(id))); // reflete worktrees externas
    notifyListeners();
  }

  /// Subpastas do projeto selecionado em [relativePath] (vazio = raiz), para o
  /// seletor navegável de "onde o agente atua". [relativePath] usa `/` e fica
  /// sempre **dentro** do root do projeto (o dialog não sobe acima dele).
  Future<List<String>> subfolders([String relativePath = '']) async {
    final project = selectedProject;
    if (project == null) return const <String>[];
    final base = relativePath.isEmpty
        ? project.path
        : '${project.path}/$relativePath';
    return _folders.subfolders(base);
  }

  /// Sessões salvas do pi para uma pasta (histórico), mais recentes primeiro.
  Future<List<SessionInfo>> historyFor(String cwd) =>
      _history.sessionsFor(cwd, withTitle: true);

  /// Aplica nome e relay ao agente. Se houver mudança real e o processo estiver
  /// rodando, reinicia com a nova config (preservando `sessionPath`).
  Future<void> saveAgentConfig(
    String sessionId, {
    required String agentName,
    required bool autoStartRelay,
  }) async {
    final s = _workspace.item(sessionId);
    if (s is! AgentSession) return;

    final nameChanged = agentName.trim() != s.title;
    final relayChanged = autoStartRelay != s.autoStartRelay;
    if (!nameChanged && !relayChanged) return;

    s.rename(agentName.trim());
    s.setAutoStartRelay(autoStartRelay);
    if (nameChanged && s.isAlive) {
      unawaited(s.sendRelayControl('rename:${agentName.trim()}'));
    }
    notifyListeners();
  }

  // ---- agent / tab / split operations (projeto ativo) -----------------------
  void focus(String paneId) {
    _applyWorkspaceCommand(
      (document) =>
          WorkspaceDocumentCommands.focusPane(document, paneId: paneId),
    );
  }

  void selectTab(String paneId, String agentId) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.selectTab(
        document,
        paneId: paneId,
        tabId: agentId,
      ),
    );
  }

  /// Abre uma aba "Novo" (placeholder vazio) na pane — o usuário escolhe ali
  /// dentro se quer um agente ou um terminal (via [fillEmpty]). Mesma cara da
  /// aba inicial de um workspace recém-aberto.
  void newEmptyTab(String paneId) {
    final projectId = _selectedProjectId;
    final project = selectedProject;
    if (projectId == null || project == null) return;
    final empty = _makeEmpty(projectId);
    final applied = _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.appendTab(
        document,
        paneId: paneId,
        tab: _workspace.descriptorFor(empty, project),
      ),
    );
    if (!applied) _workspace.disposeTab(empty.id);
  }

  /// Cria uma aba (agente ou terminal) direto na subpasta [subRelative] do
  /// projeto ativo, na pane focada — **sem dialog**. Usada pelo menu de contexto
  /// da árvore de arquivos. Se a pane focada está num placeholder "Novo" vazio,
  /// substitui-o; senão, anexa uma aba nova e a ativa.
  void newTabIn(String subRelative, {required bool terminal}) {
    final document = _activeDocument;
    final project = selectedProject;
    if (document == null || project == null) return;
    final paneId = focusedPaneId(project.id) ?? leaves(document.root).first.id;
    final leaf = findLeaf(document.root, paneId) ?? leaves(document.root).first;
    final s = _spawn(subRelative, terminal: terminal);
    final tab = _workspace.descriptorFor(s, project);

    final active = _workspace.item(leaf.active);
    final replaceEmpty = active is AgentSession && active.isPlaceholder;

    final applied = _applyWorkspaceCommand(
      (doc) => replaceEmpty
          ? WorkspaceDocumentCommands.replaceTab(
              doc,
              paneId: leaf.id,
              oldTabId: leaf.active,
              newTab: tab,
            )
          : WorkspaceDocumentCommands.appendTab(doc, paneId: leaf.id, tab: tab),
    );
    if (!applied) _workspace.disposeTab(s.id);
  }

  /// Divide a pane criando um agente novo ao lado/abaixo.
  void splitPane(String paneId, SplitDir dir, String subRelative) {
    final document = _activeDocument;
    final project = selectedProject;
    if (document == null || project == null) return;
    // O novo pane espelha o tipo da aba ativa: terminal → terminal, agente → agente.
    final leaf = findLeaf(document.root, paneId);
    final active = leaf == null ? null : _workspace.item(leaf.active);
    final terminal = active is TerminalSession;
    final s = _spawn(subRelative, terminal: terminal);
    final applied = _applyWorkspaceCommand(
      (doc) => WorkspaceDocumentCommands.splitPane(
        doc,
        targetPaneId: paneId,
        dir: dir,
        tab: _workspace.descriptorFor(s, project),
        newPaneId: _nid('pane'),
        newSplitId: _nid('sp'),
      ),
    );
    if (!applied) _workspace.disposeTab(s.id);
  }

  // ---- drag & drop de abas --------------------------------------------------

  /// Move a aba [tabId] (de [srcPaneId]) pra dentro de [targetPaneId] como mais
  /// uma aba (acoplar). A sessão **não** é morta — só muda de lugar.
  void moveTabToPane(String srcPaneId, String tabId, String targetPaneId) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.moveTabToPane(
        document,
        srcPaneId: srcPaneId,
        tabId: tabId,
        targetPaneId: targetPaneId,
      ),
    );
  }

  /// Move a aba [tabId] (de [srcPaneId]) pra um **novo pane** criado dividindo
  /// [targetPaneId] em [dir]. [before] = novo pane antes (esquerda/cima) ou
  /// depois (direita/baixo). A sessão só muda de lugar (não é morta).
  void moveTabToNewSplit(
    String srcPaneId,
    String tabId,
    String targetPaneId,
    SplitDir dir, {
    required bool before,
  }) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.moveTabToNewSplit(
        document,
        srcPaneId: srcPaneId,
        tabId: tabId,
        targetPaneId: targetPaneId,
        dir: dir,
        before: before,
        newPaneId: _nid('pane'),
        newSplitId: _nid('sp'),
      ),
    );
  }

  /// Reordena a aba [tabId] dentro do **mesmo** pane, ou a insere numa posição
  /// específica de **outro** pane. [index] é o slot desejado na lista de abas do
  /// destino (0..len). A sessão só muda de lugar (não é morta).
  void moveTabToIndex(
    String srcPaneId,
    String tabId,
    String targetPaneId,
    int index,
  ) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.moveTabToIndex(
        document,
        srcPaneId: srcPaneId,
        tabId: tabId,
        targetPaneId: targetPaneId,
        index: index,
      ),
    );
  }

  /// Preenche uma pane vazia: troca o placeholder por um agente ou terminal.
  void fillEmpty(
    String paneId,
    String emptyId,
    String subRelative, {
    bool terminal = false,
  }) {
    final project = selectedProject;
    if (project == null) return;
    final s = _spawn(subRelative, terminal: terminal);
    final applied = _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.fillEmpty(
        document,
        paneId: paneId,
        emptyTabId: emptyId,
        replacement: _workspace.descriptorFor(s, project),
      ),
    );
    if (!applied) _workspace.disposeTab(s.id);
  }

  void closeTab(String paneId, String agentId) {
    final projectId = _selectedProjectId;
    if (projectId == null) return;
    final empty = _emptyTabDescriptor(projectId);
    final applied = _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.closeTab(
        document,
        paneId: paneId,
        tabId: agentId,
        emptyTab: empty,
      ),
    );
    if (!applied || !(_activeDocument?.tabs.containsKey(empty.id) ?? false)) {
      _workspace.disposeTab(empty.id);
    }
  }

  void closePane(String paneId) {
    final projectId = _selectedProjectId;
    if (projectId == null) return;
    final empty = _emptyTabDescriptor(projectId);
    final applied = _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.closePane(
        document,
        paneId: paneId,
        emptyTab: empty,
      ),
    );
    if (!applied || !(_activeDocument?.tabs.containsKey(empty.id) ?? false)) {
      _workspace.disposeTab(empty.id);
    }
  }

  void resizeSplit(String splitId, double frac) {
    _applyWorkspaceCommand(
      (document) => WorkspaceDocumentCommands.resizeSplit(
        document,
        splitId: splitId,
        frac: frac,
      ),
    );
  }

  void toggleRail() {
    _railVisible = !_railVisible;
    notifyListeners();
  }

  void toggleTree() {
    _treeVisible = !_treeVisible;
    notifyListeners();
  }

  // ---- helpers --------------------------------------------------------------
  Project? _projectById(String? id) {
    for (final project in _projectList) {
      if (project.id == id) return project;
    }
    return null;
  }

  /// Id do workspace raiz dono de [id] (ele mesmo, se já for raiz).
  String _rootOf(String id) => _projectById(id)?.parentId ?? id;

  WorkspaceDocument? get _activeDocument =>
      _selectedProjectId == null ? null : _documents[_selectedProjectId];

  PaneNode? get _activeTree => _activeDocument?.root;

  void _setDocument(WorkspaceDocument document) {
    _documents[document.projectId] = document.ensureFocusValid();
  }

  bool _applyWorkspaceCommand(
    WorkspaceCommandResult Function(WorkspaceDocument document) command,
  ) {
    final document = _activeDocument;
    if (document == null) return false;
    final result = command(document);
    final changed =
        !identical(result.document, document) ||
        result.disposeTabIds.isNotEmpty;
    if (!changed) return false;
    _setDocument(result.document);
    for (final id in result.disposeTabIds) {
      _workspace.disposeTab(id);
    }
    _clearFocusedNotification();
    notifyListeners();
    return true;
  }

  void _initDocument(String projectId) {
    if (_documents.containsKey(projectId)) return;
    final empty = _emptyTabDescriptor(projectId);
    final leaf = LeafPane(id: _nid('pane'), tabs: [empty.id], active: empty.id);
    _setDocument(
      WorkspaceDocument(
        projectId: projectId,
        root: leaf,
        focusedPaneId: leaf.id,
        tabs: <String, WorkspaceTab>{empty.id: empty},
      ),
    );
  }

  PaneItem _spawn(String subRelative, {required bool terminal}) {
    final project = selectedProject!;
    final cwd = subRelative.isEmpty
        ? project.path
        : '${project.path}/$subRelative';
    final title = _sanitizeName(
      subRelative.isEmpty ? project.name : _basename(subRelative),
    );
    return terminal
        ? _workspace.createTerminal(
            id: _nid('t'),
            projectId: project.id,
            workingDirectory: cwd,
            title: title,
          )
        : _workspace.createAgent(
            id: _nid('a'),
            project: project,
            workingDirectory: cwd,
            title: title,
          );
  }

  // ---- notificações ---------------------------------------------------------

  /// Id do agente que o usuário está olhando (aba ativa da pane focada do
  /// projeto selecionado).
  String? get _focusedAgentId {
    final pid = _selectedProjectId;
    if (pid == null) return null;
    final document = _documents[pid];
    if (document == null) return null;
    final tree = document.root;
    final paneId = document.focusedPaneId;
    final leaf = findLeaf(tree, paneId);
    if (leaf != null) return leaf.active;
    final ls = leaves(tree);
    return ls.isEmpty ? null : ls.first.active;
  }

  void _onAgentTurnEnd(AgentSession session) {
    if (session.sessionPath == null) {
      unawaited(_workspace.captureSessionPath(session));
    }
    unawaited(_refreshGit(session.projectId));
    unawaited(_refreshWorktrees(_rootOf(session.projectId)));
    unawaited(
      _workspace.notifyIfNeeded(
        session,
        isActiveTab: session.id == _focusedAgentId,
        notificationsEnabled: _notificationsEnabled,
        workspace: _projectById(session.projectId)?.name ?? '',
      ),
    );
  }

  /// Limpa a notificação do agente que acabou de virar o focado.
  void _clearFocusedNotification() {
    final id = _focusedAgentId;
    if (id != null) _workspace.clearUnseen(id);
  }

  AgentSession _makeEmpty(String projectId) =>
      _workspace.createEmpty(id: _nid('a'), projectId: projectId);

  WorkspaceTab _emptyTabDescriptor(String projectId) {
    final id = _nid('a');
    _workspace.createEmpty(id: id, projectId: projectId);
    return WorkspaceTab.empty(id: id);
  }

  // ---- persistência do layout ----------------------------------------------

  /// Ativa um projeto (sobe os processos). Se há layout salvo, reconstrói a
  /// árvore + sessões; senão, abre uma pane vazia. Idempotente: já-ativo é no-op.
  Future<void> _activateProject(String id) async {
    if (_documents.containsKey(id)) return;
    final doc = _savedLayouts[id];
    if (doc == null) {
      _initDocument(id); // síncrono — pane vazia padrão
      return;
    }
    _restoring = true;
    try {
      await _restoreProject(id, doc);
    } finally {
      _restoring = false;
    }
    notifyListeners();
  }

  Future<void> _restoreProject(String id, Map<String, dynamic> doc) async {
    final project = _projectById(id);
    if (project == null) {
      _initDocument(id);
      return;
    }
    var document = WorkspaceDocument.fromPersistedJson(
      projectId: id,
      json: doc,
    );
    _bumpSeqPast(document.tabs.keys, document.root);

    final restored = <String>{};
    for (final tab in document.tabs.values) {
      if (await _workspace.realize(tab, project)) restored.add(tab.id);
    }

    document = document.filterTabs(
      restored,
      emptyTabFactory: () => _emptyTabDescriptor(project.id),
    );
    _setDocument(document);
  }

  /// Avança `_seq` além de qualquer sufixo numérico dos ids restaurados, pra
  /// `_nid` não colidir com ids reaproveitados.
  void _bumpSeqPast(Iterable<String> sessionIds, PaneNode tree) {
    var maxN = _seq;
    void scan(String id) {
      final m = RegExp(r'(\d+)$').firstMatch(id);
      if (m != null) maxN = max(maxN, int.parse(m.group(1)!) + 1);
    }

    sessionIds.forEach(scan);
    void walk(PaneNode n) {
      scan(n.id);
      switch (n) {
        case LeafPane():
          n.tabs.forEach(scan);
        case SplitPane():
          walk(n.a);
          walk(n.b);
      }
    }

    walk(tree);
    _seq = maxN;
  }

  Map<String, dynamic> _serializeLayout(String projectId) {
    final document = _documents[projectId];
    if (document == null) return const <String, dynamic>{};
    final refreshed = _documentWithLiveTabs(projectId, document);
    _setDocument(refreshed);
    return refreshed.toPersistedJson();
  }

  WorkspaceDocument _documentWithLiveTabs(
    String projectId,
    WorkspaceDocument document,
  ) {
    final project = _projectById(projectId);
    return project == null
        ? document
        : _workspace.documentWithLiveTabs(project, document);
  }

  /// Clona a estrutura de panes/abas do projeto [rootId] num doc de layout novo:
  /// **ids frescos**, **sem `sessionPath`** (sessões começam do zero) e **sem
  /// viewers**. A árvore (splits/posições/frac) e o `sub` relativo de cada
  /// agente/terminal são preservados — ao restaurar no fork, o `cwd` vira
  /// `fork.path + sub`, ou seja, a mesma estrutura na pasta do worktree.
  /// `null` se o root não tem layout (ou só tinha viewers).
  Map<String, dynamic>? _cloneLayoutForWorktree(String rootId) {
    final doc = _documents.containsKey(rootId)
        ? _serializeLayout(rootId)
        : _savedLayouts[rootId];
    if (doc == null || doc.isEmpty) return null;
    final treeJson = doc['tree'];
    final sessionsJson = doc['sessions'];
    if (treeJson is! Map || sessionsJson is! Map) return null;

    // 1. Remapeia sessões: dropa viewers, remove sessionPath, id novo por tipo.
    final tabIdMap = <String, String>{};
    final newSessions = <String, dynamic>{};
    for (final entry in sessionsJson.entries) {
      final desc = Map<String, dynamic>.from(entry.value as Map);
      if (desc['type'] == 'viewer') continue; // worktree não replica viewers
      desc.remove('sessionPath'); // não continua sessão — começa do zero
      final newId = _nid(desc['type'] == 'terminal' ? 't' : 'a');
      tabIdMap[entry.key as String] = newId;
      newSessions[newId] = desc;
    }
    if (newSessions.isEmpty) return null;

    // 2. Remapeia a árvore (ids de folha/split novos; abas via tabIdMap).
    final nodeIdMap = <String, String>{};
    final newTree = _remapTreeForClone(
      paneNodeFromJson(treeJson.cast<String, dynamic>()),
      tabIdMap,
      nodeIdMap,
    );
    final focused = doc['focused'];
    return <String, dynamic>{
      'v': 1,
      'focused': focused is String ? nodeIdMap[focused] : null,
      'tree': paneNodeToJson(newTree),
      'sessions': newSessions,
    };
  }

  PaneNode _remapTreeForClone(
    PaneNode node,
    Map<String, String> tabIdMap,
    Map<String, String> nodeIdMap,
  ) {
    switch (node) {
      case LeafPane():
        final newId = nodeIdMap.putIfAbsent(node.id, () => _nid('pane'));
        final tabs = <String>[
          for (final t in node.tabs)
            if (tabIdMap[t] != null) tabIdMap[t]!,
        ];
        // Folha que só tinha viewers fica vazia → o sanitize do restore põe um
        // placeholder. `active` aqui é só um fallback inofensivo nesse caso.
        final active =
            tabIdMap[node.active] ?? (tabs.isNotEmpty ? tabs.first : newId);
        return LeafPane(id: newId, tabs: tabs, active: active);
      case SplitPane():
        final newId = nodeIdMap.putIfAbsent(node.id, () => _nid('sp'));
        return SplitPane(
          id: newId,
          dir: node.dir,
          frac: node.frac,
          a: _remapTreeForClone(node.a, tabIdMap, nodeIdMap),
          b: _remapTreeForClone(node.b, tabIdMap, nodeIdMap),
        );
    }
  }

  /// Caminho de [cwd] relativo à raiz [root] do projeto ('' = raiz). Devolve
  /// sempre com separador `/` (forma canônica interna).
  ///
  /// Normaliza `\`→`/` antes de comparar: no Windows os paths podem misturar
  /// separadores (ex.: a pasta do worktree vem do git com `\`, enquanto os cwds
  /// internos são montados com `/`). Sem isso o prefixo não casaria e o `sub`
  /// sairia vazio — quebrando o posicionamento por subpasta (e a clonagem de
  /// layout pro worktree).
  String _subOf(String cwd, String root) {
    final c = cwd.replaceAll('\\', '/');
    final r = root.replaceAll('\\', '/');
    if (c == r) return '';
    final prefix = r.endsWith('/') ? r : '$r/';
    return c.startsWith(prefix) ? c.substring(prefix.length) : '';
  }

  void _scheduleSave(String projectId) {
    _saveTimers[projectId]?.cancel();
    _saveTimers[projectId] = Timer(const Duration(milliseconds: 500), () {
      _saveTimers.remove(projectId);
      final doc = _serializeLayout(projectId);
      if (doc.isNotEmpty) unawaited(_layoutStore.save(projectId, doc));
    });
  }

  /// (Re)lê o estado git de um projeto e atualiza a rail. Chamado no boot (todos),
  /// ao selecionar e no fim de turno do agente (que pode ter mexido em arquivos).
  Future<void> _refreshGit(String projectId) async {
    final project = _projectById(projectId);
    if (project == null) return;
    final info = await _gitReader.read(project.path);
    // Evita rebuild se nada mudou (branch + ahead/behind + mapa de arquivos).
    final old = _gitInfo[projectId];
    if (old == info) {
      _gitInfo[projectId] = info; // garante a chave mesmo sem mudança visível
      return;
    }
    _gitInfo[projectId] = info;
    _gitTree[projectId] = _buildGitTree(info?.files);
    notifyListeners();
  }

  /// Expande o mapa path→status (só arquivos) num índice que também cobre as
  /// **pastas ancestrais**, cada uma com o estado mais forte dos descendentes.
  static Map<String, GitFileStatus> _buildGitTree(
    Map<String, GitFileStatus>? files,
  ) {
    if (files == null || files.isEmpty) return const <String, GitFileStatus>{};
    final tree = <String, GitFileStatus>{};
    for (final entry in files.entries) {
      final path = entry.key; // relativo, separador '/'
      tree[path] = GitFileStatus.strongest(tree[path], entry.value)!;
      // Propaga pros ancestrais: 'a/b/c.dart' → 'a/b', 'a'.
      var slash = path.lastIndexOf('/');
      while (slash > 0) {
        final dir = path.substring(0, slash);
        tree[dir] = GitFileStatus.strongest(tree[dir], entry.value)!;
        slash = dir.lastIndexOf('/');
      }
    }
    return tree;
  }

  /// (Re)inicia o watcher de filesystem do projeto **selecionado** → mantém a
  /// árvore/branch atualizadas ao vivo conforme o disco muda (o agente edita
  /// arquivos, troca de branch, comita). No-op se já observa esse mesmo path.
  void _startGitWatch(String? projectId) {
    final path = projectId == null ? null : _projectById(projectId)?.path;
    if (path == _gitWatchPath) return; // já observando este projeto
    _gitWatch?.cancel();
    _gitWatchDebounce?.cancel();
    _gitWatch = null;
    _gitWatchPath = path;
    if (path == null || projectId == null) return;
    try {
      _gitWatch = Directory(path)
          .watch(recursive: true)
          .listen((event) => _onGitFsEvent(projectId, event));
    } catch (_) {
      _gitWatchPath = null; // pasta inacessível → sem watcher (refresh manual)
    }
  }

  /// Evento de filesystem do watcher. Filtra o ruído interno do `.git/` (o
  /// próprio `git status` mexe em `index.lock` etc. → loop), exceto `HEAD` e
  /// `index`, que sinalizam checkout/commit/staging. Debounce junta rajadas.
  void _onGitFsEvent(String projectId, FileSystemEvent event) {
    final p = event.path.replaceAll('\\', '/');
    final gitIdx = p.indexOf('/.git/');
    if (gitIdx != -1) {
      final rest = p.substring(gitIdx + 6); // depois de '/.git/'
      if (rest != 'HEAD' && rest != 'index') return;
    }
    _gitWatchDebounce?.cancel();
    _gitWatchDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_refreshGit(projectId));
    });
  }

  /// Reconcilia as worktrees de um workspace raiz contra o git (decisões 4, 5,
  /// 17, 20). Forks novos entram em [_projectList]; forks sumidos (por fora ou
  /// via remove) têm o runtime encerrado (mata `pi` + fecha panes — decisão 9) e,
  /// se selecionados, a seleção volta pro pai. Só notifica quando a lista muda.
  Future<void> _refreshWorktrees(String rootId) async {
    final root = _projectById(rootId);
    if (root == null || root.parentId != null) return;

    final wts = await _worktreeMgr.list(root.path);
    final forks = <Project>[
      for (final Worktree w in wts)
        Project(
          id: w.path, // o caminho é o id estável do fork
          name: w.branch,
          path: w.path,
          colorValue: root.colorValue,
          createdAt: root.createdAt,
          parentId: rootId,
          order: root.order, // aninha junto do pai
        ),
    ];

    final old = _worktrees[rootId] ?? const <Project>[];
    final oldSig = old.map((f) => '${f.id}|${f.name}').toList();
    final newSig = forks.map((f) => '${f.id}|${f.name}').toList();
    final newIds = forks.map((f) => f.id).toSet();
    final oldIds = old.map((f) => f.id).toSet();

    // Forks que sumiram → encerra runtime e tira de _projectList.
    var switched = false;
    for (final gone in old.where((f) => !newIds.contains(f.id))) {
      _disposeProjectRuntime(gone.id);
      _projectList.removeWhere((p) => p.id == gone.id);
      if (_selectedProjectId == gone.id) {
        _selectedProjectId = rootId; // pai assume
        switched = true;
      }
    }
    // Forks novos → entram em _projectList + carregam layout salvo (decisão 18).
    for (final fresh in forks.where((f) => !oldIds.contains(f.id))) {
      _projectList.add(fresh);
      _savedLayouts[fresh.id] = await _layoutStore.load(fresh.id);
    }
    _worktrees[rootId] = forks;

    // dirtyCount por fork (decisão 8) — cada um notifica se mudou.
    for (final f in forks) {
      unawaited(_refreshGit(f.id));
    }

    if (switched) await _activateProject(_selectedProjectId!);
    if (switched || !listEquals(oldSig, newSig)) notifyListeners();
  }

  String _basename(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  String _sanitizeName(String name) => name.replaceAll(' ', '-');

  /// Toda mudança estrutural passa por aqui → agenda (debounced) a gravação do
  /// layout do projeto ativo. Pulado durante a restauração (layout meio-feito).
  @override
  void notifyListeners() {
    super.notifyListeners();
    if (_restoring) return;
    final id = _selectedProjectId;
    if (id != null && _documents.containsKey(id)) _scheduleSave(id);
  }

  @override
  void dispose() {
    _gitWatch?.cancel();
    _gitWatchDebounce?.cancel();
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    _saveTimers.clear();
    _workspace.dispose();
    super.dispose();
  }
}
