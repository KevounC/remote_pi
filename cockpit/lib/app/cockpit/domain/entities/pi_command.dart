/// Um slash command disponível no agente (vem de `get_commands`). No pi, os
/// comandos são providos por **extensions**; o `name` pode ter espaço (ex.:
/// `remote-pi setup`). Invocado mandando `/<name>` como prompt.
class PiCommand {
  const PiCommand({required this.name, required this.description});

  final String name;
  final String description;
}

/// Canonical command names from `protocol/schema/cockpit-control.schema.json`.
///
/// Cockpit keeps this as a domain value and lets the RPC process adapter choose
/// the active transport encoding (currently the compatibility NUL-prefixed
/// prompt frame).
enum PiControlCommandName {
  relayOn('relay_on'),
  relayOff('relay_off'),
  relayToggle('relay_toggle'),
  relayStatus('relay_status'),
  rename('rename');

  const PiControlCommandName(this.wire);

  /// `command` value used by the structured cockpit-control schema object.
  final String wire;
}

/// Relay subcommands carried by the cockpit-control command family.
enum PiRelayControlAction {
  on(PiControlCommandName.relayOn),
  off(PiControlCommandName.relayOff),
  toggle(PiControlCommandName.relayToggle),
  status(PiControlCommandName.relayStatus);

  const PiRelayControlAction(this.commandName);

  final PiControlCommandName commandName;
}

/// Schema-aligned control command sent through [RpcProcessGateway.sendControl].
///
/// This replaces raw `relay:on` / `rename:...` strings at the domain boundary.
/// The gateway implementation remains the only layer that serializes this value
/// to the current compatibility transport frame.
final class PiControlCommand {
  PiControlCommand.relay(PiRelayControlAction relay)
    : command = relay.commandName,
      relay = relay,
      name = null;

  PiControlCommand.rename(String name)
    : command = PiControlCommandName.rename,
      relay = null,
      name = name.trim();

  final PiControlCommandName command;
  final PiRelayControlAction? relay;
  final String? name;

  bool get isRename => command == PiControlCommandName.rename;
}
