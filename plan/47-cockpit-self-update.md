# Plano 47 — Self-update do Cockpit (Sparkle + WinSparkle)

> Referências: [`43-cockpit-packaging.md`](./43-cockpit-packaging.md) (notify + download),
> [`00-decisions.md`](./00-decisions.md) (Distribuição — reversão da decisão "sem auto-update").

> **STATUS — implementado 2026-06-27** (na worktree `feat/update-system`). Feito e
> verificado neste Mac: camada Dart (`SelfUpdater` + impl `auto_updater` + noop, VM por
> plataforma, card), `flutter analyze` limpo, **137 testes** passam (9 novos), **build
> macOS** linka o Sparkle (framework + SUPublicEDKey no bundle), config nativa
> (Info.plist, Runner.rc, Inno template), CI (`.app.zip` notarizado + appcasts assinados
> via PyNaCl, gate de build number), chave EdDSA gerada e exportada pro iCloud, docs +
> CHANGELOG. **Pendências (não testáveis aqui):** adicionar o secret `SPARKLE_PRIVATE_KEY`
> no repo; validar Windows real (EdDSAPub, silent install, relaunch); validar codesign do
> Sparkle na notarização; E2E real (subir appcast e ver um cockpit antigo atualizar);
> subir os appcasts no rp-s3 (gate).

## Contexto

Hoje o cockpit tem **"notify + download manual"** (plano 43): no boot, `UpdateChecker`
lê `latest.json` no rp-s3, e o `UpdateCard` no rail abre o `.dmg`/`.exe`/`.deb` no
navegador — o usuário **instala na mão**. O alvo é o padrão VSCode/cmux/Paseo: **fecha,
atualiza, reabre sozinho**.

A lição desses três: ninguém escreve self-update do zero. macOS = **Sparkle**,
Windows = **WinSparkle**, Linux = package manager do SO. Em Flutter isso é o pacote
**`auto_updater`** (leanflutter, mesmo autor do Fastforge que já usamos), que embrulha
Sparkle (macOS) + WinSparkle (Windows). **Linux fica fora** (segue no card de notify).

Resultado pretendido: em macOS/Windows o cockpit **baixa o update em background**,
mostra **"v1.6 pronta — reiniciar para instalar"** no card existente, e ao reiniciar
troca o binário e relança — agentes `pi --mode rpc` morrem e **voltam sozinhos** (estado
no Hive). Linux inalterado.

> **Reversão consciente:** `00-decisions.md` (Distribuição, 2026-06-12) dizia "Updates:
> sem auto-update" e o plano 43 adiou "Auto-update in-app". O usuário reabriu e aprovou
> este escopo em **2026-06-27**. A linha de Distribuição já foi atualizada (riscada +
> nova). Linux **mantém** notify manual; o gate de publicação manual no rp-s3 **continua**
> (agora cobre os appcasts).

## Decisões fechadas (2026-06-27)

| # | Decisão |
|---|---|
| **A** | Self-update via `auto_updater ^1.0.0` (Sparkle no macOS, WinSparkle no Windows). **Linux fora** — segue no card de notify (`latest.json` + abrir URL). |
| **B** | **UX híbrida**: checagem/download **em background** (`checkForUpdates(inBackground:true)`); diálogo nativo do Sparkle/WinSparkle **suprimido** (config de auto-update no nativo); o **card do rail** é a única UI visível ("pronta — reiniciar p/ instalar"). |
| **C** | **Reinício silencioso (estilo VSCode)**: sem aviso "N agentes". Ao reiniciar, agentes morrem e **respawnam** pelo estado no Hive. Sem confirm-on-quit nesta fase. |
| **D** | **Coexistência, não substituição**: mantém `UpdateChecker`/`latest.json`/`UpdateCard` como camada informativa e **fallback** (e caminho único do Linux). `auto_updater` entra por baixo, atrás de um contrato `SelfUpdater`, ativo só em macOS/Windows. |
| **E** | **Dois appcasts separados** (`appcast-macos.xml`, `appcast-windows.xml`), **uma chave EdDSA** pros dois. *(Refinado na implementação 2026-06-27: ed25519 é determinístico e Sparkle/WinSparkle compartilham o esquema — verificado que `sign_update` e PyNaCl geram assinatura idêntica. Logo um par só, assinado por PyNaCl no CI, embarcado como `SUPublicEDKey` + `EdDSAPub`. Original previa dois pares.)* |
| **F** | **Artefato de update ≠ instalador**: macOS = `.app.zip` (ditto do `.app` notarizado+stapled); Windows = **o mesmo `.exe` do Inno** em modo silencioso; o `.dmg` e o `.exe` seguem como primeira instalação. |

## API verificada (`auto_updater 1.0.0`, conferida na fonte)

- Plugin federado: `auto_updater_macos` puxa `Sparkle` via CocoaPods (`pod install` roda
  no `flutter build macos`); `auto_updater_windows` **vendoriza** `WinSparkle 0.8.1` e a DLL.
- Fachada `autoUpdater`: `setFeedURL(url)`, `checkForUpdates({inBackground})`,
  `setScheduledCheckInterval(int seconds)` (default 86400, min 3600, 0 desliga),
  `addListener/removeListener`.
- `UpdaterListener` (mixin): `onUpdaterError`, `onUpdaterCheckingForUpdate`,
  `onUpdaterUpdateAvailable`, `onUpdaterUpdateNotAvailable`, `onUpdaterUpdateDownloaded`,
  `onUpdaterBeforeQuitForUpdate` (pré-relaunch, **fire-and-forget — não bloqueia o quit**).
- **macOS**: chave pública EdDSA vai no `Info.plist` (`SUPublicEDKey`); cockpit é
  **non-sandbox** (Sparkle ok sem entitlements extras); feed é HTTPS (rp-s3) → sem exceção ATS.
- **Windows**: a fachada **não** chama `win_sparkle_set_eddsa_public_key()` → a chave
  pública precisa ser embarcada como **recurso `EdDSAPub`** no `windows/runner/Runner.rc`;
  WinSparkle lê versão/empresa do `VERSIONINFO` (já existe no `Runner.rc`).

## Estrutura esperada (camadas novas, máximo reuso)

```
cockpit/lib/app/cockpit/
├── domain/
│   ├── contracts/self_updater.dart          # NOVO: SelfUpdater (isSupported, status, initialize, check)
│   └── value_objects/update_target.dart     # EDITAR: + String? selfUpdateFeedUrl por plataforma
├── data/update/
│   ├── auto_updater_self_updater.dart        # NOVO: impl + UpdaterListener → SelfUpdateStatus
│   └── noop_self_updater.dart                # NOVO: isSupported=false (Linux)
├── ui/
│   ├── viewmodels/update_viewmodel.dart       # EDITAR: modo por plataforma (self-update vs download); injeta SelfUpdater
│   └── widgets/update_card.dart               # EDITAR: texto/ação por vm.isSelfUpdate (mínimo)
└── cockpit_module.dart                        # EDITAR: bind SelfUpdater (switch plataforma) + injeta no VM
cockpit/lib/app/cockpit/ui/cockpit_page.dart   # EDITAR: selfUpdater.initialize() no initState (junto do check())
cockpit/macos/Runner/Info.plist                # EDITAR: SUPublicEDKey + chaves de auto-update
cockpit/windows/runner/Runner.rc               # EDITAR: recurso EdDSAPub
cockpit/windows/packaging/exe/make_config.yaml # EDITAR: Inno CloseApplications/RestartApplications
.github/workflows/cockpit-release.yml          # EDITAR: zip+sign+appcast macOS; sign+appcast Windows; gate
```

Contrato proposto:

```dart
abstract class SelfUpdater {
  bool get isSupported;                       // macOS/Win = true; Linux = false
  Stream<SelfUpdateStatus> get status;        // idle/checking/available/downloaded/error
  Future<void> initialize();                  // setFeedURL + addListener + setScheduledCheckInterval
  Future<void> checkForUpdates({bool inBackground});
}
```

`UpdateViewModel` continua dono do card; ganha `bool get isSelfUpdate`. Em macOS/Windows
o `check()` do boot dispara `selfUpdater.checkForUpdates(inBackground:true)` e o card
reflete o `status` (clicar = `checkForUpdates()` que conduz install no próximo quit).
Em Linux, comportamento atual intacto. Evita um 2º ChangeNotifier e mantém `UpdateCard`
quase inalterado.

## Passos (com critério de aceite)

1. **Dep + nativo base.** `auto_updater: ^1.0.0` no `pubspec.yaml`; `flutter pub get`;
   `pod install` (macOS). **Aceite:** `flutter build macos` e `flutter build windows`
   passam com o plugin linkado (Sparkle.framework embarcado; WinSparkle.dll empacotada).

2. **Chaves EdDSA.** Gerar par Sparkle (`generate_keys -x privfile`) e par WinSparkle
   (`winsparkle-tool`). Públicas **commitadas** (`SUPublicEDKey` no Info.plist; `EdDSAPub`
   no `Runner.rc`). Privadas viram os secrets `SPARKLE_PRIVATE_KEY`/`WINSPARKLE_PRIVATE_KEY`
   **e** backup junto dos certs na pasta iCloud
   `/Users/jacob/Library/Mobile Documents/com~apple~CloudDocs/Flutterando/RemotePi/CockpitApp`
   (mesma que hoje guarda `certs.p12` + `AuthKey_*.p8`). **Aceite:** públicas no repo;
   privadas salvas no iCloud e como secrets; `sign_update`/`winsparkle-tool` produzem
   assinatura válida localmente contra um zip/exe de teste.

3. **Camada de domínio/data.** Criar `self_updater.dart` (+ enum de status),
   `auto_updater_self_updater.dart` (impl + `UpdaterListener`, traduz callbacks),
   `noop_self_updater.dart`; estender `update_target.dart` com `selfUpdateFeedUrl`
   (`.../appcast-macos.xml` / `appcast-windows.xml`). **Aceite:** `flutter analyze` zero
   issues; teste de unidade do mapeamento callback→status com `SelfUpdater` mockado.

4. **ViewModel + card + DI.** `UpdateViewModel` decide modo por plataforma e injeta
   `SelfUpdater`; `UpdateCard` muda texto/ação por `isSelfUpdate`; `cockpit_module.dart`
   registra `SelfUpdater` com switch (`Platform.isMacOS||isWindows ? AutoUpdaterSelfUpdater : NoopSelfUpdater`);
   `cockpit_page.dart` chama `initialize()` no `initState` ao lado do `check()` (linha 51).
   **Aceite:** em macOS o card mostra "pronta — reiniciar p/ instalar" quando há update;
   em Linux o card abre URL como hoje (sem regressão).

5. **UX híbrida silenciosa.** Configurar o nativo pra **baixar automático e instalar no
   quit** (Info.plist: `SUAutomaticallyUpdate`/`SUEnableAutomaticChecks`; WinSparkle:
   `automatic_check`), surfaçando `onUpdaterUpdateDownloaded` no card; suprimir o diálogo
   nativo. **Aceite:** update aparece **só** no nosso card; a instalação ocorre ao
   reiniciar, sem 2ª janela do Sparkle/WinSparkle. *(Risco: se a fachada não expõe
   supressão total, registrar follow-up — ver Riscos.)*

6. **Ciclo de vida (silencioso).** Em `onUpdaterBeforeQuitForUpdate`, kill **best-effort
   síncrono** dos agentes (mesmo caminho do `dispose()` em `pi_rpc_process.dart:206`);
   confiar no respawn via Hive e no `cleanOrphans()` (SIGKILL, `main.dart:33`) como rede
   de segurança. **Aceite:** após um update real, nenhum `pi` órfão (checa `agent-pids`);
   workspace/panes reabrem nas mesmas pastas.

7. **CI macOS.** Notarizar+`staple` o **`.app`** (hoje só o `.dmg`); `ditto -c -k
   --keepParent Cockpit.app Cockpit-<v>-macos.zip`; `sign_update` com `SPARKLE_PRIVATE_KEY`;
   gerar `appcast-macos.xml` (`sparkle:version` = **build number** do `+n`). Manter o `.dmg`.
   **Aceite:** a release contém `.dmg` + `.app.zip`; `appcast-macos.xml` válido com
   `edSignature`/`length`.

8. **CI Windows.** Recurso `EdDSAPub` no `Runner.rc`; assinar o `.exe` com
   `WINSPARKLE_PRIVATE_KEY`; `appcast-windows.xml` com `sparkle:installerArguments`
   silencioso (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-`); Inno com
   `CloseApplications=yes`/`RestartApplications=yes`. **Aceite:** WinSparkle baixa e
   instala silencioso (sem UAC, per-user em LOCALAPPDATA) e relança.

9. **CI publish + versão.** Ajustar o **gate de 6 artefatos** (`cockpit-release.yml:284`)
   pro novo total (+`.app.zip`; mantê-lo **fora** do `latest.json` — serve só ao Sparkle);
   publicar `appcast-macos.xml`+`appcast-windows.xml` no **mesmo gate manual** do rp-s3
   (`/Users/flutterando/cockpit/data/`); o job `meta` passa a validar que o **build
   number `+n` foi incrementado**. **Aceite:** release ponta a ponta gera os dois appcasts;
   subir os appcasts no rp-s3 faz um cockpit antigo se auto-atualizar.

10. **Docs.** Atualizar `cockpit/packaging/README.md` (runbook: zip/sign/appcast, rotação
    de chaves) e `CHANGELOG.md`. **Aceite:** runbook reproduz uma release de self-update
    do zero. *(A reversão em `00-decisions.md` já foi feita ao abrir este plano.)*

## Definition of Done

- [ ] `auto_updater ^1.0.0` integrado; `flutter build macos`/`windows` ok com o nativo embarcado
- [ ] Chaves EdDSA geradas; públicas no repo; privadas como secrets (`SPARKLE_PRIVATE_KEY`, `WINSPARKLE_PRIVATE_KEY`)
- [ ] `SelfUpdater` (contrato + impl auto_updater + noop) com `flutter analyze` limpo e teste do mapeamento de status
- [ ] `UpdateViewModel`/`UpdateCard`/`cockpit_module`/`cockpit_page` em modo por plataforma; Linux sem regressão
- [ ] UX híbrida: update visível só no card; instala no quit; sem diálogo nativo duplicado
- [ ] Reinício silencioso: agentes respawnam, zero órfãos
- [ ] CI macOS: `.app.zip` notarizado+stapled+assinado + `appcast-macos.xml`
- [ ] CI Windows: `.exe` assinado + `EdDSAPub` no Runner.rc + `appcast-windows.xml` + Inno silencioso
- [ ] CI publish: gate de artefatos ajustado; appcasts publicados no rp-s3; validação de build number
- [ ] Update real end-to-end testado nas duas plataformas; runbook + CHANGELOG atualizados

## Riscos / pontos de atenção

- **Codesign do Sparkle**: o `codesign --force --deep` atual (`cockpit-release.yml:93`)
  precisa cobrir `Sparkle.framework` + `Autoupdate`/`Updater.app`/XPCServices com Hardened
  Runtime + timestamp, ou a notarização rejeita. `--deep` é desencorajado pela Apple →
  pode ser preciso assinar os componentes do Sparkle **explicitamente** antes do `.app`.
- **Versão = build number**: Sparkle compara `CFBundleVersion` (o `+n`). **Obrigatório
  incrementar o `+n` a cada release** — hoje o `meta` valida só a versão marketing.
- **Fachada não bloqueia o quit** (`onUpdaterBeforeQuitForUpdate` é fire-and-forget) →
  kill gracioso completo não é garantido; depende do SIGKILL de boot (já existe).
- **Supressão total da UI nativa** (passo 5) pode não ser exposta pela fachada → se não
  der, follow-up: estender o plugin / `MethodChannel` direto, ou aceitar UI nativa mínima.
- **WinSparkle exige `EdDSAPub`** como recurso (não há API) — sem ele, sem verificação.
- **Inno + Restart Manager**: confirmar que o cockpit em execução (per-user) é fechado e
  relançado silencioso, sem UAC.
- **Gate de 6 artefatos** quebra ao somar o `.app.zip` — ajustar a contagem.
- **Consistência de versão**: o card (compara versão marketing via `isNewerVersion`) e o
  Sparkle (compara build number) não podem divergir.

## Verificação end-to-end

1. `flutter analyze` zero issues; `flutter test` (inclui teste novo de `SelfUpdater`).
2. `flutter build macos` / `flutter build windows` localmente — plugin linkado.
3. **macOS**: instalar v(N) do `.dmg`; subir appcast apontando p/ v(N+1) `.app.zip` num
   host de teste; abrir o app → card "pronta"; reiniciar → relança em v(N+1); checar
   `~/.pi/cockpit/agent-pids` sem órfãos e panes restaurados.
4. **Windows**: instalar v(N) do `.exe` (per-user); appcast p/ v(N+1); reiniciar →
   instala silencioso sem UAC, relança em v(N+1).
5. **Linux**: confirmar que o card ainda abre a URL do `.deb`/`.rpm` (sem regressão).
6. Release real via tag `cockpit-v<x>` gera `.app.zip`+appcasts; gate manual publica os
   appcasts no rp-s3; um cliente antigo se auto-atualiza.

## Próximos planos (futuro)

- Repositórios APT/DNF no rp-s3 → self-update nativo do Linux (`apt/dnf upgrade`).
- Assinatura Authenticode do `.exe` (OV/Azure Trusted Signing) — remove aviso SmartScreen.
- Staged rollout (Sparkle `phasedRolloutInterval`).
- Delta updates (Sparkle) se o tamanho do download incomodar.
- Confirm-on-quit geral ("N agentes rodando — fechar?") via `window_manager.onWindowClose`,
  se o reinício silencioso se mostrar agressivo demais.
