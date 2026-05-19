import 'dart:convert';

import 'protocol.dart';

String encodeClient(ClientMessage m) => '${jsonEncode(m.toJson())}\n';

ServerMessage decodeServer(String line) =>
    ServerMessage.fromJson(jsonDecode(line) as Map<String, dynamic>);
