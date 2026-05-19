import 'package:app/config/dependencies.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/routing/app_router.dart';
import 'package:app/ui/app_theme.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupDependencies();
  runApp(const RemotePiApp());
}

class RemotePiApp extends StatefulWidget {
  const RemotePiApp({super.key});

  @override
  State<RemotePiApp> createState() => _RemotePiAppState();
}

class _RemotePiAppState extends State<RemotePiApp> {
  late final _router = buildRouter(injector.get<PairingStorage>());

  @override
  void dispose() {
    disposeDependencies();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Remote Pi',
      theme: buildAppTheme(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
