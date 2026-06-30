import 'package:flutter/foundation.dart';

/// Base de uma aba do multiplexador — um agente (`AgentSession`) ou um terminal
/// (`TerminalSession`). A VM guarda todas as abas como [PaneItem]; a UI decide
/// como renderizar pelo tipo concreto.
abstract class PaneItem extends ChangeNotifier {
  String get id;
  String get projectId;
  String get title;
  String get workingDirectory;

  /// Resultado novo não visto (só agentes); terminais retornam `false`.
  bool get unseenFinish => false;
  void clearUnseen() {}

  /// Public change hook for the workspace projection, which owns live tab
  /// resources but is not itself a [ChangeNotifier] subclass.
  void notifyItemChanged() => notifyListeners();
}
