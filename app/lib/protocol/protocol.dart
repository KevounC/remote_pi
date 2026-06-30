// Public protocol facade. Generated DTOs live under generated/ and are
// regenerated from the canonical schema; do not hand-edit generated files.
//
// Relay control/presence/rooms frames are not yet in the schema IR, so they
// remain in the temporary hand-maintained island exported below.
import 'generated/protocol.g.dart';

export 'control_frames.dart';
export 'generated/protocol.g.dart';

const Set<String> sessionScopedClientTypes =
    generatedSessionScopedClientMessageTypes;
const Set<String> sessionScopedServerTypes =
    generatedSessionScopedServerMessageTypes;

bool isSessionScopedClientType(String type) =>
    isGeneratedSessionScopedClientMessageType(type);

bool isSessionScopedServerType(String type) =>
    isGeneratedSessionScopedServerMessageType(type);
