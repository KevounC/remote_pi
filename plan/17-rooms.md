# Plano 17 — Rooms (multi-sessão por dispositivo)

## Contexto

Hoje pareamento usa `epk_mac` (Ed25519 device-singleton) como peer_id no
relay. Relay impõe "1 conexão por peer_id" — quando user roda 2+
`pi -e .../remote-pi start` no mesmo Mac (cwds diferentes), processos
concorrem pelo único slot → loop de disconnect/reconnect.

Decisão (2026-05-21): adotar **modelo room** (estilo Slack/Discord/IRC):
- 1 pair = autorização do dispositivo (epk_mac)
- N rooms por dispositivo = N sessões Pi paralelas (1 por cwd)
- App descobre rooms automaticamente via push do relay
- Sem IPC entre processos Pi — cada `pi -e` é independente

## Decisões fixadas

| Decisão | Valor / razão |
|---|---|
| **D1: room_id é derivado de cwd** | SHA256(realpath(cwd)) base64url (12 chars). Mesmo cwd = mesma room_id, persiste entre runs |
| **D2: discovery via control frames** | App `subscribe_rooms{peer}` → relay push `room_announced` / `room_ended`. Análogo ao plano 12 (presence) |
| **D3: envelope ganha `room` (opcional)** | `{peer, room?, ct}` — room ausente = default "main" (backward-compat com peers legacy) |
| **D4: cada processo Pi abre WS próprio** | Sem IPC, sem master. Concorrência tratada no relay (multi-conn por peer_id discriminado por room_id) |
| **D5: storage app** | peers.json continua 1 entry por Mac. Rooms vivas vêm via push (em memória + cache). Apelidos (plano 10.3) movem pra room |
| **D6: hello ganha `room_id` + `room_meta`** | `{type:"hello", pubkey, room_id?, room_meta?: {name, cwd}}`. room_id ausente = "main" |
| **D7: roteamento** | Relay mantém `Map<(peer_id, room_id), conn>`. Forward por destino exato. Reescreve peer (sender) E room (sender's room) na delivery |
| **D8: migration** | Peers legacy (epk_mac, sem room_id) viram room "main". Pi atualizado emite room_id derivado. App agrupa "main" + outras rooms sob mesmo Mac |
| **D9: conflito mesmo cwd** | Mesmo cwd = mesma room_id. 2 starts no mesmo cwd: relay rejeita 2º. Pi-ext mostra "Already running in this cwd" |

## Novos types no protocolo

### Outer envelope (mudança)

```jsonc
// Antes
{ "peer": "<epk>", "ct": "<base64>" }

// Depois
{ "peer": "<epk>", "room": "<room_id>", "ct": "<base64>" }
//                  ^^^^^ opcional; default "main" se ausente
```

### Control frames (novos)

App → Relay:

```jsonc
{ "type": "subscribe_rooms", "peers": ["<epk_mac>", ...] }
{ "type": "unsubscribe_rooms", "peers": ["<epk_mac>", ...] }
{ "type": "rooms_check", "peers": ["<epk_mac>", ...] }
```

Relay → App:

```jsonc
{ "type": "room_announced", "peer": "<epk>", "room_id": "...", "name": "...", "cwd": "...", "started_at": <ts> }
{ "type": "room_ended", "peer": "<epk>", "room_id": "...", "since_ts": <ts> }
{ "type": "rooms", "peer": "<epk>", "rooms": [{room_id, name, cwd, started_at}, ...] }
```

### Hello estendido (mudança)

```jsonc
// Antes
{ "type": "hello", "pubkey": "<base64>" }

// Depois
{ "type": "hello", "pubkey": "<base64>", "room_id": "<id>?", "room_meta"?: { "name": "...", "cwd": "..." } }
```

## Estrutura esperada

### Relay (Rust)

- `src/peers/registry.rs`:
  - Map vira `HashMap<(PeerId, RoomId), Conn>` (RoomId = String, default "main")
  - `register(peer_id, room_id, room_meta?, conn)` substitui `register(peer_id, conn)`
  - `unregister(peer_id, room_id)`
  - `forward(to_peer, to_room, payload)` — antes era só `to_peer`
- `src/handlers/peer.rs`:
  - Hello aceita `room_id` (default "main") + `room_meta`
  - Outer envelope vai/vem com `room`
- `src/rooms.rs` (NOVO, análogo a presence):
  - `RoomManager`: `HashMap<PeerId, HashMap<RoomId, RoomMeta>>` (sessões ativas por Mac)
  - `subscribers: HashMap<PeerId, HashSet<SubscriberPeerId>>` (quem se interessa por rooms de qual peer)
  - Handlers `subscribe_rooms`, `unsubscribe_rooms`, `rooms_check`
  - Broadcast `room_announced` quando peer conecta com novo room_id; `room_ended` quando peer desconecta esse room_id
- `src/main.rs`: instancia RoomManager + injeta em handlers
- Tests: registro multi-room, subscribe + push, rejeição de duplicate (peer, room)

### Pi-extension

- `src/rooms.ts` (NOVO):
  ```typescript
  export function roomIdForCwd(cwd: string): string {
    return createHash('sha256').update(realpathSync(cwd)).digest('base64url').slice(0, 12);
  }
  ```
- `src/index.ts`:
  - `_cmdStart`: usa `roomIdForCwd(cwd)`; passa pro RelayClient
  - Envia hello com `room_id` + `room_meta: { name: sessionName, cwd }`
  - Se relay rejeita (duplicate (peer, room)): notify "Already running in this cwd"
- `src/transport/relay_client.ts`:
  - `connect({roomId, roomMeta})` envia esses no hello
- `src/transport/peer_channel.ts`:
  - send/receive incluem `room` no envelope (recebe room do remetente — útil pra distinguir)
- Tests: 2 processos Pi simulados em cwds diferentes → 2 conns OK; mesmo cwd → 2º rejeitado

### App

- `lib/data/transport/ws_transport.dart`:
  - Hello envia `room_id` (gerado pelo app? não — app é cliente, não tem cwd. Usa "main" ou null pra ser "app room")
  - Envelope ganha `room` (target room na send, sender room na receive)
- `lib/data/transport/connection_manager.dart`:
  - Após connect: enviar `subscribe_rooms{peers: [...]}` (junto com subscribe_presence)
  - Handler control frames novos:
    - `RoomAnnounced` → atualiza `_roomsByPeer[peer].add(room)`
    - `RoomEnded` → remove
    - `Rooms` (snapshot) → batch
  - Expor `Stream<Map<PeerId, List<RoomInfo>>> roomsStream`
  - `switchRoom(peer, room)` — análogo a switchTo, mas dentro do mesmo peer (não reabre WS, só muda target)
- `lib/ui/home/`:
  - Tile vira "1 room" (não "1 peer"). Title = `room_meta.name` (ex: "remote_pi · feature/protocol")
  - Se múltiplos peers (Macs diferentes), agrupa por Mac com header
  - HomeNoPeer continua válido (zero pares)
- `lib/ui/chat/viewmodels/chat_viewmodel.dart`:
  - `_activePeer` vira `_activeRoom = (peer, room_id)`
  - `selectedPeerEpk` em Preferences vira `selectedRoom = "peer:room"` (composite key)
- `lib/protocol/protocol.dart`:
  - Outer envelope ganha `room`
  - Novos types: `SubscribeRooms`, `UnsubscribeRooms`, `RoomsCheck`, `RoomAnnounced`, `RoomEnded`, `RoomsSnapshot`
- Tests: discovery, switch room, send/receive com room field

### Contracts

- `.orchestration/contracts/protocol.md`:
  - Atualizar outer envelope com `room`
  - Adicionar 6 control frames de rooms
  - Atualizar hello com room_id + room_meta
- `.orchestration/contracts/pairing.md`:
  - Documentar: pareamento é per-device; rooms são sub-canais
- Fixtures novas (6): subscribe_rooms, unsubscribe_rooms, rooms_check, room_announced, room_ended, rooms

## Passos com critério de aceite

### Wave 0 — Contratos
- [ ] `protocol.md`: outer envelope + 6 control frames de rooms + hello estendido
- [ ] `pairing.md`: nota sobre per-device pair + rooms
- [ ] 6 fixtures novas

### Wave 1 — Subprojetos em paralelo

#### W1.A — Relay
- [ ] PeerRegistry com `HashMap<(PeerId, RoomId), Conn>`
- [ ] Hello + envelope aceitam `room_id` (default "main")
- [ ] `RoomManager` com subscribers + broadcast on connect/disconnect
- [ ] Forward roteia por (peer, room)
- [ ] Tests: multi-conn por peer_id, subscribe_rooms, push announced/ended
- [ ] `cargo test` verde

#### W1.B — Pi-extension
- [ ] `src/rooms.ts` com `roomIdForCwd`
- [ ] `_cmdStart` usa roomIdForCwd, envia hello com room_id + room_meta
- [ ] Trata rejeição "Already running in this cwd"
- [ ] Tests: dois cwds diferentes geram room_ids distintos; mesmo cwd determinístico
- [ ] `pnpm test` verde

#### W1.C — App
- [ ] Outer envelope ganha `room`
- [ ] Hello ganha `room_id="main"` (app é cliente — sempre room "main")
- [ ] ConnectionManager subscribe_rooms + handler de push
- [ ] HomeViewModel: state agrupa rooms por peer
- [ ] ChatViewModel: `_activeRoom = (peer, room_id)`
- [ ] Preferences: `selectedRoom` (composite) em vez de `selectedPeerEpk`
- [ ] UI: SessionTile mostra room name; agrupa por Mac se múltiplos
- [ ] Migration: peers legacy → room "main" automático
- [ ] Tests
- [ ] `flutter test` verde

### Wave 2 — Roundtrip manual

- [ ] Pareamento legacy (peer existente sem room_id) → app conecta, tudo funciona como antes (em room "main")
- [ ] Pi em `/cwd_a` `/remote-pi start` → app vê "cwd_a" na Home (room nova)
- [ ] Pi em `/cwd_b` (outro terminal) `/remote-pi start` → app vê AMBOS simultaneamente
- [ ] Tap em cwd_a no app → chat de cwd_a (msgs vão pra room de cwd_a)
- [ ] Voltar e tap em cwd_b → chat de cwd_b (msgs distintas)
- [ ] Para cwd_a (`/remote-pi stop`) → room some da Home (push `room_ended`)
- [ ] Tentar `/remote-pi start` em cwd_a com cwd_a já rodando outra instância → erro "Already running"
- [ ] Reabrir app: lista de rooms restaurada via `rooms_check` snapshot

### Wave 3 — Polish
- [ ] Atualizar `00-decisions.md`: modelo room, per-device pair
- [ ] Atualizar `README.md`: "multi-sessão paralela"
- [ ] Commit consolidado

## Definition of Done

- [ ] Wave 0: contratos + fixtures
- [ ] W1.A: relay multi-room
- [ ] W1.B: pi-ext room_id por cwd
- [ ] W1.C: app discovery + UI
- [ ] Wave 2: roundtrip 8 cenários
- [ ] Wave 3: docs + commit

## Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Migration quebra peers legacy | Default "main" pra room ausente preserva comportamento |
| App descobre rooms mas user nunca pareou Mac | subscribe_rooms exige peers pareados — só vê rooms de Macs autorizados |
| Mensagem pra room errada (vazamento entre cwds) | Relay roteia por (peer, room) — sem ambiguidade |
| Cwd com mesmo basename mas paths diferentes | `realpath` antes do hash. Disambigua |
| Pi processo crash sem unregister | Relay detecta WS close, broadcast room_ended automático |
| Relay memory bloat com muitas rooms | Limpa room quando peer desconecta. Bounded by max processes Pi por user |

## Próximos planos

- **Plano 18+** — push notifications, polish UI rooms
- **Plano 07** — relay deploy (com env throttle/jitter da memory)
