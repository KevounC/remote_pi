# Remote Pi UI — Flutter Implementation Guide

Document for implementing the three screens (`ScreenPair`, `ScreenSessions`, `ScreenChat`) and shared components from `screens.jsx`.

## 1. Design Tokens

| Token | CSS Value | Flutter Equivalent | Purpose |
|-------|-----------|-------------------|---------|
| `RP_BG` | `#000` | `Color(0xFF000000)` | Screen background |
| `RP_SURFACE` | `#0a0a0a` | `Color(0xFF0a0a0a)` | Card/surface background |
| `RP_SURFACE_2` | `#121212` | `Color(0xFF121212)` | Secondary surface (unused in mockup) |
| `RP_BORDER` | `#1a1a1a` | `Color(0xFF1a1a1a)` | Border/divider color |
| `RP_TEXT` | `#ffffff` | `Color(0xFFffffff)` | Primary text (white) |
| `RP_MUTED` | `#6b6b6b` | `Color(0xFF6b6b6b)` | Secondary text, $ prompt |
| `RP_MUTED_2` | `#8a8a8a` | `Color(0xFF8a8a8a)` | Tertiary text |
| `Accent` | `#00d4ff` | `Color(0xFF00d4ff)` | Cyan, interactive highlights |
| `Highlight` | `#9fe6ff` | `Color(0xFF9fe6ff)` | Code/file paths in chat |
| `Success` | `#6cd28a` | `Color(0xFF6cd28a)` | Checkmark in tool output |
| **RP_MONO** | JetBrains Mono | `fontFamily: 'JetBrains Mono'` or fallback monospace | Code, model names, timestamps |
| **RP_SANS** | SF Pro / Inter | System font (default) | UI text, labels |

### TextStyle presets

```dart
// Code/monospace — 12.5 pt, line height 1.5
const codeTextStyle = TextStyle(
  fontFamily: 'JetBrains Mono',
  fontSize: 12.5,
  color: Color(0xFFe6e6e6),
  height: 1.5,
);

// Title (Sessions page) — 28 pt, bold
const titleTextStyle = TextStyle(
  fontSize: 28,
  fontWeight: FontWeight.w700,
  color: Color(0xFFffffff),
);

// Section label — 11 pt, uppercase, letter spacing 1.4
const sectionLabelTextStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: Color(0xFF6b6b6b),
  letterSpacing: 1.4,
  textTransform: TextTransform.uppercase,
);
```

---

## 2. Shared Components

### StatusBar (Custom)

**Purpose:** Mimic iOS status bar with signal, WiFi, battery.

**Widget Name:** `RemoteStatusBar`

```dart
class RemoteStatusBar extends StatelessWidget {
  final String time;
  final Color textColor;
  
  const RemoteStatusBar({
    this.time = '9:41',
    this.textColor = const Color(0xFFffffff),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(time, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
          // Spacer for Dynamic Island (~120px)
          SizedBox(width: 95),
          // Signal bars, WiFi, battery SVGs
          Row(
            gap: 5,
            children: [
              _buildSignalBars(),
              _buildWiFiIcon(),
              _buildBatteryIcon(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalBars() => SvgPicture.asset('assets/icons/signal.svg', width: 17, height: 11);
  Widget _buildWiFiIcon() => SvgPicture.asset('assets/icons/wifi.svg', width: 15, height: 11);
  Widget _buildBatteryIcon() => SvgPicture.asset('assets/icons/battery.svg', width: 25, height: 12);
}
```

**Usage:** Place at top of each screen; not in AppBar.

---

### HomeIndicator

**Purpose:** Mimic iPhone home swipe indicator at bottom.

**Widget Name:** `HomeIndicator`

```dart
class HomeIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 8,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 135,
          height: 5,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            color: Color.fromARGB(140, 255, 255, 255),
          ),
        ),
      ),
    );
  }
}
```

**Usage:** Wrap screens in Stack; position HomeIndicator as last child.

---

### DynamicIsland

**Purpose:** Notch/Dynamic Island placeholder above status bar.

**Widget Name:** `DynamicIsland`

```dart
class DynamicIsland extends Positioned {
  DynamicIsland()
      : super(
          top: 11,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 122,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Color(0xFF000000),
              ),
            ),
          ),
        );
}
```

---

### Standard NavBar

For screens with top navigation (back + title + optional trailing):

```dart
class NavBar extends StatelessWidget {
  final VoidCallback onBack;
  final String title;
  final Widget? trailing;
  
  const NavBar({
    required this.onBack,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: SizedBox(
              width: 36,
              height: 36,
              child: BackIcon(),
            ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Color(0xFFffffff),
              ),
            ),
          ),
          SizedBox(width: 36, child: trailing),
        ],
      ),
    );
  }
}
```

---

## 3. Screen 1 — PairDevicePage

Displays QR viewfinder and pairing status.

### Layout Structure

```
Scaffold(
  body: Stack(
    children: [
      Column(
        children: [
          RemoteStatusBar(),
          NavBar(onBack: ..., title: 'Pair device'),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  QRViewfinder(
                    paired: _paired,
                    accent: accentColor,
                    onTap: _handlePair,
                  ),
                  SizedBox(height: 26),
                  Text(_paired ? 'Connected to your computer' : 'Point camera...'),
                  SizedBox(height: 22),
                  TextButton(
                    onPressed: _showCodeEntry,
                    child: Text('Enter code manually'),
                  ),
                ],
              ),
            ),
          ),
          Container(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              gap: 6,
              children: [
                LockIcon(),
                Text('END-TO-END ENCRYPTED'),
              ],
            ),
          ),
        ],
      ),
      HomeIndicator(),
      DynamicIsland(),
    ],
  ),
)
```

### Key Widget: QRViewfinder

**Purpose:** Animated QR scanner box with corner brackets and scanning line.

```dart
class QRViewfinder extends StatefulWidget {
  final bool paired;
  final Color accent;
  final VoidCallback onTap;

  const QRViewfinder({
    required this.paired,
    required this.accent,
    required this.onTap,
  });

  @override
  State<QRViewfinder> createState() => _QRViewfinderState();
}

class _QRViewfinderState extends State<QRViewfinder> with TickerProviderStateMixin {
  late AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      duration: Duration(milliseconds: 2400),
      vsync: this,
    );
    if (!widget.paired) {
      _scanController.repeat();
    }
  }

  @override
  void didUpdateWidget(QRViewfinder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paired != widget.paired) {
      if (widget.paired) {
        _scanController.stop();
      } else {
        _scanController.repeat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 268,
        height: 268,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Color(0xFF050505),
          border: Border.all(color: Color(0xFF161616), width: 1),
        ),
        child: Stack(
          children: [
            // Camera noise/texture
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.3, 0.2),
                    radius: 0.6,
                    colors: [Color(0xFF1a1a1a), Colors.transparent],
                  ),
                ),
                opacity: 0.7,
              ),
            ),
            
            // QR glyph (AnimatedOpacity for paired state)
            AnimatedOpacity(
              opacity: widget.paired ? 1 : 0.85,
              duration: Duration(milliseconds: 280),
              child: Padding(
                padding: EdgeInsets.all(36),
                child: QRGlyph(paired: widget.paired, accent: widget.accent),
              ),
            ),

            // Corner brackets (4 rotated corners)
            ..._buildCornerBrackets(),

            // Scanning line animation
            if (!widget.paired)
              AnimatedBuilder(
                animation: _scanController,
                builder: (context, _) {
                  return Positioned(
                    left: 14,
                    right: 14,
                    top: 36 + (196 * _scanController.value), // animate top to bottom
                    child: Container(
                      height: 1.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.accent.withOpacity(0),
                            widget.accent,
                            widget.accent.withOpacity(0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.accent,
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCornerBrackets() {
    final corners = [
      (left: 14.0, top: 14.0, rotation: 0.0),
      (right: 14.0, top: 14.0, rotation: 90.0),
      (right: 14.0, bottom: 14.0, rotation: 180.0),
      (left: 14.0, bottom: 14.0, rotation: 270.0),
    ];
    
    return corners.map((c) {
      return Positioned(
        left: c.left,
        top: c.top,
        right: c.right,
        bottom: c.bottom,
        child: Transform.rotate(
          angle: c.rotation * pi / 180,
          child: Container(
            width: 32,
            height: 32,
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(width: 18, height: 3, color: widget.accent, borderRadius: BorderRadius.circular(1)),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: Container(width: 3, height: 18, color: widget.accent, borderRadius: BorderRadius.circular(1)),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }
}
```

### QRGlyph Widget

Renders an 11×11 grid of dots in a deterministic pattern (corner finders + pseudorandom):

```dart
class QRGlyph extends CustomPaint {
  final bool paired;
  final Color accent;

  QRGlyph({required this.paired, required this.accent})
      : super(painter: _QRGlyphPainter(paired, accent));
}

class _QRGlyphPainter extends CustomPainter {
  final bool paired;
  final Color accent;
  static const cells = 11;
  static const seed = [3, 5, 2, 7, 11, 13, 17, 19, 23, 29, 31];

  _QRGlyphPainter(this.paired, this.accent);

  bool _isOn(int x, int y) {
    // Corner finder logic
    bool inFinder(int cx, int cy) => x >= cx && x < cx + 3 && y >= cy && y < cy + 3;
    
    if (inFinder(0, 0) || inFinder(cells - 3, 0) || inFinder(0, cells - 3)) {
      return _finderPattern(x, y);
    }
    
    // Pseudorandom fill
    return ((x * seed[y % seed.length] + y * seed[(x + 3) % seed.length]) % 7) < 3;
  }

  bool _finderPattern(int x, int y) {
    // Simplified: draw 3×3 border + center
    final corners = [(0, 0), (cells - 3, 0), (0, cells - 3)];
    for (final (cx, cy) in corners) {
      final dx = x - cx, dy = y - cy;
      if (dx >= 0 && dx < 3 && dy >= 0 && dy < 3) {
        final onEdge = dx == 0 || dy == 0 || dx == 2 || dy == 2;
        final center = dx == 1 && dy == 1;
        return onEdge || center;
      }
    }
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / cells;
    final bgColor = paired ? Color(0xFF000000) : Color(0xFF0a0a0a);
    final dotColor = paired ? accent : Color(0xFFe8e8e8);

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = bgColor);

    // Dots
    final paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    for (int y = 0; y < cells; y++) {
      for (int x = 0; x < cells; x++) {
        if (_isOn(x, y)) {
          final rect = Rect.fromLTWH(x * cellSize + 2, y * cellSize + 2, cellSize - 4, cellSize - 4);
          canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(0.5)), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QRGlyphPainter oldDelegate) => oldDelegate.paired != paired || oldDelegate.accent != accent;
}
```

### State Management

- **`_paired`** — Local `bool` in State, toggled by `onTap`
- **Transitions** — AnimationController for scanning line + opacity animation
- **Alternative:** ViewModel if pairing logic is shared with other screens

---

## 4. Screen 2 — SessionsPage

Lists active/inactive sessions with FAB.

### Layout Structure

```
Scaffold(
  body: Stack(
    children: [
      Column(
        children: [
          RemoteStatusBar(),
          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(22, 14, 22, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Remote Pi', style: titleTextStyle),
                IconButton(
                  onPressed: _handleSettings,
                  icon: GearIcon(),
                ),
              ],
            ),
          ),
          // Status row (MacBook Pro · Connected)
          StatusIndicator(device: 'MacBook Pro', status: 'Connected', accent: accent),
          // Section label
          Padding(
            padding: EdgeInsets.fromLTRB(24, 6, 24, 10),
            child: Text('SESSIONS', style: sectionLabelTextStyle),
          ),
          // Session cards list
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: 18),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => SizedBox(height: 10),
              itemBuilder: (_, i) => SessionCard(
                session: sessions[i],
                accent: accent,
                onTap: () => _openSession(sessions[i].id),
              ),
            ),
          ),
        ],
      ),
      // FAB
      Positioned(
        right: 22,
        bottom: 38,
        child: FloatingActionButton(
          onPressed: _createNewSession,
          backgroundColor: accent,
          child: Icon(Icons.add, color: Color(0xFF000000), size: 24),
        ),
      ),
      HomeIndicator(),
      DynamicIsland(),
    ],
  ),
)
```

### StatusIndicator Component

Shows connected device with glowing dot:

```dart
class StatusIndicator extends StatelessWidget {
  final String device;
  final String status;
  final Color accent;

  const StatusIndicator({
    required this.device,
    required this.status,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 6, 22, 18),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent,
              boxShadow: [BoxShadow(color: accent, blurRadius: 8)],
            ),
          ),
          SizedBox(width: 8),
          Text(device, style: const TextStyle(fontSize: 12, fontFamily: 'JetBrains Mono', color: Color(0xFFcfcfcf))),
          SizedBox(width: 4),
          Text('·', style: const TextStyle(fontSize: 12, color: Color(0xFF6b6b6b))),
          SizedBox(width: 4),
          Text(status, style: const TextStyle(fontSize: 12, fontFamily: 'JetBrains Mono', color: Color(0xFF8a8a8a))),
        ],
      ),
    );
  }
}
```

### SessionCard Widget

```dart
class SessionCard extends StatelessWidget {
  final SessionModel session;
  final Color accent;
  final VoidCallback onTap;

  const SessionCard({
    required this.session,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Color(0xFF0a0a0a),
          border: Border(
            left: BorderSide(
              color: session.active ? accent : Color(0xFF1a1a1a),
              width: session.active ? 2 : 1,
            ),
            top: BorderSide(color: Color(0xFF1a1a1a), width: 1),
            right: BorderSide(color: Color(0xFF1a1a1a), width: 1),
            bottom: BorderSide(color: Color(0xFF1a1a1a), width: 1),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          gap: 6,
          children: [
            // Title row with unread dot
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.title,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 13.5,
                      color: Color(0xFFffffff),
                      overflow: TextOverflow.ellipsis,
                    ),
                    maxLines: 1,
                  ),
                ),
                if (session.unread)
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                      boxShadow: [BoxShadow(color: accent, blurRadius: 6)],
                    ),
                  ),
              ],
            ),
            // Model badge + when + lock
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Color(0xFF161616),
                    border: Border.all(color: Color(0xFF1f1f1f), width: 1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    session.model,
                    style: const TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10.5,
                      color: Color(0xFFbdbdbd),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  session.when,
                  style: const TextStyle(
                    fontFamily: '-apple-system',
                    fontSize: 12,
                    color: Color(0xFF6b6b6b),
                  ),
                ),
                Spacer(),
                LockIcon(size: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

### Session Model

```dart
class SessionModel {
  final String id;
  final String title;
  final String model;
  final String when;
  final bool active;
  final bool unread;
  final bool locked;

  SessionModel({
    required this.id,
    required this.title,
    required this.model,
    required this.when,
    required this.active,
    required this.unread,
    required this.locked,
  });
}
```

### State Management

- **Sessions list** — Mutable List<SessionModel>; populate from ViewModel or API
- **FAB** — Creates new session or navigates to creation flow
- **Alternative:** Use `ChangeNotifierProvider` to inject SessionsViewModel

---

## 5. Screen 3 — ChatPage + ApprovalCard

Displays messages, approval card for tool requests, and input bar.

### Layout Structure

```
Scaffold(
  body: Stack(
    children: [
      Column(
        children: [
          RemoteStatusBar(),
          ChatTopBar(
            title: 'remote_pi · feature/protocol',
            onBack: () => Navigator.pop(context),
            accent: accent,
          ),
          Expanded(
            child: MessagesList(
              messages: _messages,
              decisions: _decisions,
              accent: accent,
              onApprovalDecision: _handleApprovalDecision,
            ),
          ),
          InputBar(
            onSend: _sendMessage,
            onAttach: _attachFile,
            accent: accent,
          ),
        ],
      ),
      HomeIndicator(),
      DynamicIsland(),
    ],
  ),
)
```

### ChatTopBar

```dart
class ChatTopBar extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Color accent;

  const ChatTopBar({
    required this.title,
    required this.onBack,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1a1a1a))),
      ),
      child: Row(
        children: [
          GestureDetector(onTap: onBack, child: BackIcon()),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 13,
                    color: Color(0xFFffffff),
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    LockIcon(size: 9),
                    SizedBox(width: 5),
                    Text(
                      'E2E',
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        color: Color(0xFF6b6b6b),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

### Message Model (sealed class)

```dart
sealed class MessageModel {
  final String id;
  final DateTime timestamp;

  MessageModel({required this.id, required this.timestamp});
}

class UserMessage extends MessageModel {
  final String text;

  UserMessage({
    required String id,
    required DateTime timestamp,
    required this.text,
  }) : super(id: id, timestamp: timestamp);
}

class AgentMessage extends MessageModel {
  final String text;
  final bool isStreaming;

  AgentMessage({
    required String id,
    required DateTime timestamp,
    required this.text,
    this.isStreaming = false,
  }) : super(id: id, timestamp: timestamp);
}

class ToolRequest extends MessageModel {
  final String toolName;
  final String command;
  final String description;
  final ToolDecision decision;

  ToolRequest({
    required String id,
    required DateTime timestamp,
    required this.toolName,
    required this.command,
    required this.description,
    required this.decision,
  }) : super(id: id, timestamp: timestamp);
}

enum ToolDecision { awaiting, allowed, denied }
```

### MessagesList Widget

```dart
class MessagesList extends StatefulWidget {
  final List<MessageModel> messages;
  final Map<String, ToolDecision> decisions;
  final Color accent;
  final Function(String toolId, ToolDecision decision) onApprovalDecision;

  const MessagesList({
    required this.messages,
    required this.decisions,
    required this.accent,
    required this.onApprovalDecision,
  });

  @override
  State<MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends State<MessagesList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _scrollController.jumpTo(_scrollController.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      itemCount: widget.messages.length,
      separatorBuilder: (_, __) => SizedBox(height: 14),
      itemBuilder: (_, i) {
        final msg = widget.messages[i];
        if (msg is UserMessage) {
          return _buildUserBubble(msg);
        } else if (msg is AgentMessage) {
          return _buildAgentMessage(msg);
        } else if (msg is ToolRequest) {
          return _buildApprovalCard(msg as ToolRequest);
        }
        return SizedBox.shrink();
      },
    );
  }

  Widget _buildUserBubble(UserMessage msg) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: Color(0xFF1a1a1a),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            msg.text,
            style: const TextStyle(
              fontFamily: '-apple-system',
              fontSize: 14,
              color: Color(0xFFffffff),
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAgentMessage(AgentMessage msg) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.92),
        child: RichText(
          text: TextSpan(
            style: codeTextStyle,
            children: [
              TextSpan(text: msg.text.replaceAll(RegExp(r'`[^`]+`'), '')),
              // Highlight file paths (e.g., backend/src/auth/login.ts)
              if (msg.text.contains('/'))
                TextSpan(
                  text: _extractFilePath(msg.text) ?? '',
                  style: codeTextStyle.copyWith(color: Color(0xFF9fe6ff)),
                ),
              if (msg.isStreaming) ...[
                TextSpan(text: '…'),
                WidgetSpan(child: _buildBlinkingCursor()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApprovalCard(ToolRequest tool) {
    final isApproved = widget.decisions[tool.id] != null;
    return Align(
      alignment: Alignment.centerLeft,
      child: ApprovalCard(
        toolName: tool.toolName,
        command: tool.command,
        decision: widget.decisions[tool.id],
        accent: widget.accent,
        onAllow: () => widget.onApprovalDecision(tool.id, ToolDecision.allowed),
        onDeny: () => widget.onApprovalDecision(tool.id, ToolDecision.denied),
      ),
    );
  }

  Widget _buildBlinkingCursor() {
    return BlinkingCursor(color: widget.accent);
  }

  String? _extractFilePath(String text) {
    final match = RegExp(r'(\w+/[\w/\.]+\.\w+)').firstMatch(text);
    return match?.group(0);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
```

### ApprovalCard Widget

```dart
class ApprovalCard extends StatelessWidget {
  final String toolName;
  final String command;
  final ToolDecision? decision;
  final Color accent;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  const ApprovalCard({
    required this.toolName,
    required this.command,
    required this.accent,
    required this.onAllow,
    required this.onDeny,
    this.decision,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: decision != null ? 0.55 : 1,
      duration: Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          color: Color(0xFF0a0a0a),
          border: Border.all(color: accent, width: 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.13),
              blurRadius: 20,
              spreadRadius: 0,
            ),
          ],
        ),
        padding: EdgeInsets.all(14),
        child: Column(
          children: [
            // Header row
            Row(
              children: [
                TerminalIcon(color: accent, size: 14),
                SizedBox(width: 8),
                Text(
                  toolName.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: accent,
                    letterSpacing: 0.6,
                  ),
                ),
                Spacer(),
                Text(
                  _decisionText(),
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 10,
                    color: Color(0xFF6b6b6b),
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            // Code block
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(0xFF050505),
                border: Border.all(color: Color(0xFF1a1a1a), width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: RichText(
                text: TextSpan(
                  style: codeTextStyle.copyWith(fontSize: 12.5),
                  children: _buildCommandSpans(),
                ),
              ),
            ),
            SizedBox(height: 12),
            // Action buttons
            Row(
              gap: 8,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: decision == null ? onDeny : null,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Color(0xFF2a2a2a)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    ),
                    child: Text(
                      'Deny',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFcfcfcf),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: decision == null ? onAllow : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    ),
                    child: Text(
                      'Allow',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF000000),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _decisionText() {
    return switch (decision) {
      ToolDecision.allowed => 'ALLOWED',
      ToolDecision.denied => 'DENIED',
      _ => 'AWAITING',
    };
  }

  List<InlineSpan> _buildCommandSpans() {
    // E.g., "$ cargo test auth::jwt_refresh"
    // $ is muted, test name is highlighted
    final prompt = '$ ';
    final parts = command.split(' ');
    
    return [
      TextSpan(text: prompt, style: codeTextStyle.copyWith(color: Color(0xFF6b6b6b))),
      TextSpan(text: parts[0], style: codeTextStyle), // cargo
      TextSpan(text: ' '),
      TextSpan(text: parts[1], style: codeTextStyle), // test
      TextSpan(text: ' '),
      TextSpan(
        text: parts.sublist(2).join(' '),
        style: codeTextStyle.copyWith(color: Color(0xFF9fe6ff)),
      ), // auth::jwt_refresh
    ];
  }
}
```

### BlinkingCursor Widget

```dart
class BlinkingCursor extends StatefulWidget {
  final Color color;
  final double width;
  final double height;

  const BlinkingCursor({
    required this.color,
    this.width = 7,
    this.height = 14,
  });

  @override
  State<BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<BlinkingCursor> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );
    _controller.repeat();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final isVisible = _controller.value < 0.5;
        return Opacity(
          opacity: isVisible ? 1 : 0,
          child: Container(
            width: widget.width,
            height: widget.height,
            color: widget.color,
            margin: EdgeInsets.only(left: 4),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### InputBar Widget

```dart
class InputBar extends StatefulWidget {
  final Function(String) onSend;
  final VoidCallback onAttach;
  final Color accent;

  const InputBar({
    required this.onSend,
    required this.onAttach,
    required this.accent,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _textController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 14, 22),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1a1a1a))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.attach_file, size: 18, color: Color(0xFF6b6b6b)),
            onPressed: widget.onAttach,
          ),
          SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _textController,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 13,
                color: Color(0xFFffffff),
              ),
              decoration: InputDecoration(
                hintText: 'Send a message…',
                hintStyle: const TextStyle(color: Color(0xFF6b6b6b)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(19),
                  borderSide: BorderSide(color: Color(0xFF1a1a1a)),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                filled: true,
                fillColor: Color(0xFF0e0e0e),
              ),
            ),
          ),
          SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              if (_textController.text.isNotEmpty) {
                widget.onSend(_textController.text);
                _textController.clear();
              }
            },
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.accent,
                boxShadow: [BoxShadow(color: widget.accent.withOpacity(0.33), blurRadius: 16)],
              ),
              child: Icon(Icons.arrow_upward, color: Color(0xFF000000), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}
```

---

## 6. State Management Mapping

| Feature | State Type | Location | Notes |
|---------|-----------|----------|-------|
| **PairDevicePage** | `_paired` (bool) | Local StatefulWidget | Animation controllers in State |
| **SessionsPage** | `sessions` (List), selected session | ViewModel or Provider | Fetch from API / local DB |
| **ChatPage** | `_messages` (List), `_decisions` (Map) | ViewModel + Provider | Stream incoming messages, sync decisions |
| **ApprovalCard decision** | `ToolDecision` enum | Parent ChatPage State | Update `_decisions` map on choice |
| **Message streaming** | `isStreaming` (bool) in AgentMessage | Reactive to API Stream | Re-render on new chunks |
| **Accent color** | Theme-level config | Config or Provider | Passed top-down as `accent` param |

### Recommended Pattern

Use `ChangeNotifierProvider` from `provider` package:

```dart
// config/providers.dart
final chatViewModelProvider = ChangeNotifierProvider((ref) => ChatViewModel());
final sessionsViewModelProvider = ChangeNotifierProvider((ref) => SessionsViewModel());

// In UI layer:
context.watch<ChatViewModel>().messages;
context.read<ChatViewModel>().sendMessage(text);
```

---

## 7. Implementation Checklist

### Shared Components
- [ ] `RemoteStatusBar` — stateless, 44px height, time + signal/WiFi/battery SVGs
- [ ] `HomeIndicator` — positioned at bottom, 135×5, subtle white bar
- [ ] `DynamicIsland` — positioned at top center, 122×36, black circle
- [ ] Icon SVGs (lock, back, gear, plus, paperclip, arrow-up, terminal) — store in `assets/icons/`

### Screen 1 — PairDevicePage
- [ ] `QRViewfinder` — 268×268, Stack with corner brackets + scanning line animation
- [ ] `QRGlyph` — CustomPainter, 11×11 grid, deterministic pattern with corner finders
- [ ] Tap-to-pair logic → toggle `_paired` state + cancel animations
- [ ] "Enter code manually" button → navigate/show modal
- [ ] Footer E2E lock icon + text
- [ ] Responsive padding (28px horizontal)

### Screen 2 — SessionsPage
- [ ] `StatusIndicator` — glowing dot + device name + status
- [ ] `SessionCard` — title, model badge, when, lock icon, unread dot, active border
- [ ] ListView.separated with session data
- [ ] FAB (56×56 circle, accent color, plus icon)
- [ ] Settings icon (top right)

### Screen 3 — ChatPage
- [ ] `ChatTopBar` — back button, title, E2E lock indicator
- [ ] Message variants (UserMessage, AgentMessage, ToolRequest)
- [ ] `MessagesList` — ListView, scroll-to-bottom, message bubbles
- [ ] File path highlighting in agent messages (#9fe6ff)
- [ ] `ApprovalCard` — 2 buttons, code block, header row, opacity transition on decision
- [ ] `BlinkingCursor` — 1s animation, steps(1) for discrete blink
- [ ] `InputBar` — paperclip, text input, send button with glow
- [ ] Success message on approval ("✓ running tests")

### Integration
- [ ] Wire ViewModels to pages via Provider
- [ ] Routing: define routes in `lib/routing/app_router.dart`
- [ ] Theme: centralize colors + TextStyles in `lib/config/theme.dart`
- [ ] Test: unit tests for models + UI widget tests for components
- [ ] Animations: ensure 60fps by using `SingleTickerProviderStateMixin`

---

## Notes

- **Fonts:** Ensure `JetBrains Mono` is added to `pubspec.yaml` and loaded in `assets/fonts/`
- **Null Safety:** All widgets use non-nullable types; handle optional state gracefully
- **Accessibility:** Add `semanticLabel` to custom painters and icon buttons
- **Dark Mode:** All colors are dark-themed; no light mode variant in mockup
- **Performance:** Use `const` constructors where possible; lazy-load message list with `ListView.builder`

