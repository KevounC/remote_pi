import 'package:app/config/dependencies.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/ui/chat/chat_page.dart';
import 'package:app/ui/chat/viewmodels/chat_viewmodel.dart';
import 'package:app/ui/pairing/pairing_page.dart';
import 'package:app/ui/pairing/viewmodels/pairing_viewmodel.dart';
import 'package:app/ui/settings/settings_page.dart';
import 'package:app/ui/settings/viewmodels/settings_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Boot decision is async — _BootState is a ChangeNotifier used as
// refreshListenable so the router redirects once the storage check finishes.
class _BootState extends ChangeNotifier {
  bool _ready = false;
  bool _hasPeer = false;

  bool get ready => _ready;
  bool get hasPeer => _hasPeer;

  Future<void> load(PairingStorage storage) async {
    final peers = await storage.listPeers();
    _hasPeer = peers.isNotEmpty;
    _ready = true;
    notifyListeners();
  }
}

GoRouter buildRouter(PairingStorage storage) {
  final boot = _BootState();
  boot.load(storage);

  return GoRouter(
    initialLocation: '/boot',
    refreshListenable: boot,
    redirect: (context, state) {
      if (!boot.ready) return '/boot';
      if (state.uri.path == '/boot') {
        return boot.hasPeer ? '/chat' : '/pair';
      }
      return null;
    },
    routes: [
      // Splash while boot.load() is in flight
      GoRoute(
        path: '/boot',
        builder: (ctx, st) => const _BootSplash(),
      ),

      // QR pairing flow — scanner + handshake + safety number all inline
      GoRoute(
        path: '/pair',
        builder: (ctx, st) => MultiProvider(
          providers: [ViewmodelProvider<PairingViewModel>()],
          child: const PairingPage(),
        ),
      ),

      // Main chat screen
      GoRoute(
        path: '/chat',
        builder: (ctx, st) => MultiProvider(
          providers: [ViewmodelProvider<ChatViewModel>()],
          child: const ChatPage(),
        ),
      ),

      // Settings
      GoRoute(
        path: '/settings',
        builder: (ctx, st) => MultiProvider(
          providers: [ViewmodelProvider<SettingsViewModel>()],
          child: const SettingsPage(),
        ),
      ),
    ],
  );
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF000000),
      body: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: Color(0xFF00D4FF),
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}
