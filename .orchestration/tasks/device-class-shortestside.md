Melhorar a detecção celular vs tablet: hoje um CELULAR em landscape vira "modo
tablet" porque a classificação é por LARGURA. Trocar pra `shortestSide`
(invariante à rotação).

Decisão do usuário: **Opção A — `shortestSide`**, breakpoint mantido em **600**.

## Arquivo (fonte única de verdade)
`lib/routing/adaptive.dart`.

Estado atual (~linhas 6-13):
```dart
const double kTabletBreakpoint = 600.0;

bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kTabletBreakpoint;
```
O comentário atual justifica `width` "pra reagir a Split View / Slide Over". Essa
racionalização será intencionalmente revertida — MAS o comportamento de Split
View CONTINUA correto com `shortestSide` (explicado abaixo).

## Mudança
1. Trocar o corpo de `isWideLayout` para:
   `MediaQuery.sizeOf(context).shortestSide >= kTabletBreakpoint`.
   - MANTER o nome `isWideLayout` (6 call sites consomem — não renomear).
   - MANTER `kTabletBreakpoint = 600.0`.
2. **Reescrever o comentário** explicando a nova lógica:
   - `shortestSide` = min(width, height), invariante à rotação. Celular em
     landscape tem shortestSide ~360-430 (< 600) → continua phone (mata o bug).
     Tablet em qualquer orientação tem shortestSide >= 768 → tablet.
   - Split View / Slide Over no iPadOS CONTINUA colapsando pra single-pane: o
     `MediaQuery` mede a JANELA dada ao app (não o device físico), então quando a
     janela encolhe o `shortestSide` também cai abaixo de 600. shortestSide
     satisfaz os dois objetivos: estável como classe-de-device + colapso em
     multitarefa estreita.
   - shortestSide é estritamente mais rígido que width (exige AMBAS dimensões
     >= 600). A única diferença de comportamento vs antes é "landscape com altura
     < 600" (= celulares) virar phone — exatamente o desejado.

## Tests — `test/routing/adaptive_test.dart`
Os testes atuais provavelmente setam só a largura do MediaQuery. Com shortestSide
o teste precisa de `Size(w, h)` com AS DUAS dimensões coerentes. Atualize/adicione:
- **Regressão do bug**: celular em landscape, ex. `Size(932, 430)` →
  `isWideLayout == false` (phone).
- iPad portrait `Size(768, 1024)` → true.
- iPad landscape `Size(1024, 768)` → true.
- Janela estreita tipo Split View `Size(400, 1000)` → false.
- Ajuste os testes de shell (master-only vs two-pane) pra usarem Sizes coerentes:
  two-pane com algo como `1024x768`; single-pane com `932x430` (celular
  landscape) e/ou `420x900` (celular portrait).
- Revise o teste de zero-state collapse e o do notch/SafeArea — se dependiam só
  de width, dê a eles Sizes com as duas dimensões.

## Restrições
- NÃO adicionar dependência (nada de `device_info_plus` etc. — Opção A é pura
  MediaQuery).
- NÃO renomear a função nem mudar o breakpoint.
- NÃO tocar arquivos da feature de voz com WIP não-commitado (`input_bar.dart`,
  `speech_service*`).

## Verificação obrigatória antes de gravar resultado
- `dart format` ESCOPADO aos 2 arquivos da task (NÃO rode `dart format .` global —
  há WIP de voz não-commitado de outro worker).
- `flutter analyze` (0 issues).
- `flutter test test/routing/adaptive_test.dart` (verde). Rode também os testes de
  routing/shell relacionados se existirem.

No result file: resumo do diff (arquivos/linhas) + confirmação dos comandos
verdes + lista dos casos de teste novos. NÃO commitar.
