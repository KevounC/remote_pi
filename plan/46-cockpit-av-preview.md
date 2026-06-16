# 46 — Cockpit: preview de áudio e vídeo no visualizador de arquivos

## Contexto

O visualizador de arquivos do Cockpit hoje renderiza markdown, código, imagem e
SVG (plano 37). Áudio e vídeo caem em `FileViewUnsupported` — clicar num `.mp4`
ou `.mp3` não faz nada. Este plano adiciona preview de **áudio e vídeo**
multiplataforma (macOS, Windows, Linux) reusando a arquitetura existente.

### Por que `media_kit`

Padrão de fato pra A/V cross-platform no Flutter desktop (libmpv por baixo,
aceleração de hardware, áudio **e** vídeo no mesmo motor). O `video_player`
oficial não cobre desktop direito. Decisão fechada em conversa 2026-06-12.

### O que o mapeamento do código já garante (facilita muito)

- **Detecção por extensão** em `data/filesystem/file_reader_impl.dart` já tem
  um set `_video` (`mp4/mov/avi/mkv/webm/m4v/wmv/flv`) — hoje retorna
  `FileViewUnsupported` (linha 42). É só trocar o destino e somar um set de áudio.
- **`FileViewImage(path)`** já passa **só o caminho absoluto** (não carrega
  bytes) — exatamente o que A/V precisa. Mesmo padrão pros novos tipos.
- **Sealed class `FileView`** (`domain/entities/file_view.dart`) com switch
  exaustivo no widget `FileViewer` (`ui/cockpit/widgets/file_viewer.dart:11-36`)
  — adicionar um subtype força o case novo no compilador.
- **`FileViewerSession`** já carrega `path` absoluto e tem dispose/lifecycle.

### O ponto de atenção real: pausar fora de foco

O `PaneView` usa `IndexedStack` (`pane_view.dart:96-100`) — **todas as abas
ficam montadas**, só a ativa é renderizada. Sem cuidado, um vídeo numa aba de
fundo **continua tocando áudio**. O terminal já resolve foco parecido em
`pane_view.dart:890-903`; o player A/V precisa do mesmo sinal pra **pausar
quando a aba não está ativa** e **dar dispose ao fechar**.

## Decisões de produto (confirmadas pelo usuário 2026-06-12)

- **Não autoplay.** Abrir um vídeo/áudio carrega **pausado**, com controles
  (play/pause, seek, tempo, volume). Áudio estourando ao abrir arquivo é hostil.
- **Pausa ao trocar de aba**, retoma manual (não auto-resume). Pausa também ao
  fechar/dispose.
- **Live-reload desligado pra A/V**: o `_watchFileReader`/`_watchFileViewer`
  recarrega texto ao vivo; pra A/V isso recriaria o player no meio da
  reprodução. A/V ignora o reload (mídia raramente é reescrita em disco).
- **Vídeo**: player com superfície de vídeo + controles. **Áudio**: mesma base,
  sem superfície (só controles + nome do arquivo, talvez waveform no futuro).

## Estrutura esperada

```
cockpit/
  pubspec.yaml                  # + media_kit, media_kit_video, media_kit_libs_video
  lib/
    config/bootstrap...         # MediaKit.ensureInitialized() no startup
    domain/entities/file_view.dart        # + FileViewAudio(path), FileViewVideo(path)
    data/filesystem/file_reader_impl.dart # _audio set; _video/_audio → novos tipos
    ui/cockpit/widgets/
      file_viewer.dart          # switch ganha cases audio/vídeo
      media_view.dart (novo)    # _MediaView stateful: Player + controles + pausa-fora-de-foco
  linux/packaging/deb/make_config.yaml    # + dependency libmpv2
  linux/packaging/rpm/make_config.yaml    # + requires mpv-libs
.github/workflows/cockpit-release.yml     # linux: apt install libmpv-dev no build
```

## Passos

### 1. Dependências + init (cockpit/)

- Adicionar `media_kit`, `media_kit_video`, `media_kit_libs_video` ao pubspec
  (o `_libs_video` empacota libmpv em macOS/Windows; áudio vem junto).
- Chamar `MediaKit.ensureInitialized()` no bootstrap (`config/`), antes do
  `runApp`.

**Aceite**: `flutter pub get` ok; app sobe no macOS sem regressão
(`flutter run -d macos`).

### 2. Domínio + detecção (cockpit/)

- `file_view.dart`: somar `FileViewAudio(String path)` e
  `FileViewVideo(String path)` à sealed class.
- `file_reader_impl.dart`: criar `_audio = {mp3, wav, aac, m4a, flac, ogg, opus}`;
  `_video` e `_audio` passam a retornar `FileViewVideo(path)` /
  `FileViewAudio(path)` (cedo, antes de qualquer leitura de bytes — igual à
  imagem). Sem limite de tamanho (não lê conteúdo).

**Aceite**: teste unitário do `FileReaderImpl` cobrindo: `.mp4` → `FileViewVideo`,
`.mp3` → `FileViewAudio`, extensão desconhecida segue o caminho atual.

### 3. Widget do player (cockpit/)

- `media_view.dart`: `_MediaView` **stateful** — cria `Player` + `VideoController`
  no `initState`, dispõe no `dispose`. Vídeo usa `Video(controller)`; áudio mostra
  card com nome + controles. Carrega `media` **pausado**.
- Controles seguindo o tema (`context.colors`/`context.typo`): play/pause, slider
  de posição, tempo decorrido/total, volume/mute.
- `file_viewer.dart`: adicionar os dois cases no switch → `_MediaView(path, kind)`.

**Aceite**: abrir um `.mp4` e um `.mp3` no macOS toca com controles; fechar a aba
some o player sem áudio fantasma.

### 4. Pausa fora de foco (cockpit/)

- Threadar o estado "aba ativa/visível" do `_PaneBody` (que já conhece foco —
  `pane_view.dart:890-903`) até o `_MediaView`, que **pausa** quando deixa de ser
  a aba ativa. (Implementação: passar um `bool active`/`ValueListenable` pro
  widget, ou um visibility hook no `PaneItem`, espelhando o que o terminal faz.)

**Aceite**: tocar um vídeo, trocar de aba → o áudio para; voltar → continua
pausado no ponto. Dois vídeos em abas diferentes não tocam juntos.

### 5. Empacotamento Linux (cockpit/ + raiz)

- `linux/packaging/deb/make_config.yaml`: somar `libmpv2` às `dependencies`.
- `linux/packaging/rpm/make_config.yaml`: somar `mpv-libs` aos `requires`.
- `cockpit-release.yml` (job linux x64 e arm64): `apt-get install -y libmpv-dev`
  junto das deps de build (GTK etc.), pra o build linkar libmpv.

**Aceite**: release de teste gera `.deb`/`.rpm`; o smoke test do CL instala e o
`ldd` do binário resolve libmpv. (macOS/Windows não precisam — libs embarcadas.)

## Definition of Done

- [x] `media_kit` integrado e inicializado; sem regressão no viewer atual (build macOS linka libmpv via pods)
- [x] `.mp4/.mov/.mkv/.webm/...` e `.mp3/.wav/.flac/...` abrem com player + controles, carregados pausados
- [x] Trocar de aba pausa a mídia; fechar dá dispose (zero áudio fantasma) — implementado via `active = tabId == pane.active`; **validação tátil no macOS pendente**
- [x] Teste unitário da detecção (vídeo/áudio → tipos novos) — 5/5
- [x] Pacotes Linux declaram libmpv (deb `libmpv2`, rpm `mpv-libs`); CI instala `libmpv-dev` no build — feito 2026-06-12; deb/rpm instalam e linkam → valida no CI
- [x] `flutter analyze` zero issues; build macOS ok (Windows/Linux pelo pipeline)
- [x] Primeira release com A/V: `cockpit-v1.2.0` (2026-06-16) — 6 jobs verdes; DMG +21MB / EXE +14MB (libmpv embarcado), deb/rpm +0.3MB (libmpv do sistema, linkou no CI)
- [ ] Validação tátil no macOS (abrir mp4/mp3, play, pausa ao trocar de aba) — passo manual do usuário

## Próximos planos / fora de escopo

- Waveform e scrubbing de áudio, thumbnails de vídeo, legendas.
- Preview de A/V no `app/` mobile (se fizer sentido).
- Formatos exóticos dependem do que o libmpv suporta — não vamos transcodar.
