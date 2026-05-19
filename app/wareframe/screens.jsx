// Remote Pi — three iPhone screens
// Dark terminal-iOS aesthetic. Cyan #00d4ff used sparingly.

const RP_BG = '#000';
const RP_SURFACE = '#0a0a0a';
const RP_SURFACE_2 = '#121212';
const RP_BORDER = '#1a1a1a';
const RP_TEXT = '#ffffff';
const RP_MUTED = '#6b6b6b';
const RP_MUTED_2 = '#8a8a8a';
const RP_MONO = '"JetBrains Mono", "IBM Plex Mono", ui-monospace, Menlo, monospace';
const RP_SANS = '-apple-system, "SF Pro Text", "Inter", system-ui, sans-serif';

// shared icons -----------------------------------------------------------
const IconLock = ({ size = 11, color = RP_MUTED }) => (
  <svg width={size} height={size * 1.2} viewBox="0 0 11 13" fill="none">
    <rect x="1" y="5.5" width="9" height="7" rx="1.5" stroke={color} strokeWidth="1.1"/>
    <path d="M3 5.5V3.5a2.5 2.5 0 0 1 5 0v2" stroke={color} strokeWidth="1.1"/>
  </svg>
);
const IconBack = ({ color = '#fff' }) => (
  <svg width="11" height="18" viewBox="0 0 11 18" fill="none">
    <path d="M9 1.5L1.5 9 9 16.5" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
);
const IconGear = ({ color = '#bbb' }) => (
  <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
    <circle cx="10" cy="10" r="2.5" stroke={color} strokeWidth="1.4"/>
    <path d="M10 1.5v2.2M10 16.3v2.2M18.5 10h-2.2M3.7 10H1.5M16 4l-1.6 1.6M5.6 14.4L4 16M16 16l-1.6-1.6M5.6 5.6L4 4" stroke={color} strokeWidth="1.4" strokeLinecap="round"/>
  </svg>
);
const IconPlus = ({ color = '#000' }) => (
  <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
    <path d="M11 3v16M3 11h16" stroke={color} strokeWidth="2.4" strokeLinecap="round"/>
  </svg>
);
const IconPaperclip = ({ color = RP_MUTED }) => (
  <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
    <path d="M12.5 8.5L7.8 13.2a2.5 2.5 0 0 1-3.5-3.5L9.6 4.3a4 4 0 0 1 5.7 5.7l-5.3 5.3a5.5 5.5 0 0 1-7.8-7.8" stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
);
const IconArrowUp = ({ color = '#000' }) => (
  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
    <path d="M8 13V3M3 8l5-5 5 5" stroke={color} strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
);
const IconTerminal = ({ color, size = 14 }) => (
  <svg width={size} height={size} viewBox="0 0 14 14" fill="none">
    <rect x="0.7" y="2" width="12.6" height="10" rx="1.6" stroke={color} strokeWidth="1.2"/>
    <path d="M3.5 5.5L5.5 7l-2 1.5M6.5 9h4" stroke={color} strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
);

// status bar (custom dark) -----------------------------------------------
function StatusBar({ time = '9:41' }) {
  return (
    <div style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: '16px 28px 0', height: 44, boxSizing: 'border-box',
      fontFamily: RP_SANS, color: '#fff', fontSize: 15, fontWeight: 600,
      position: 'relative', zIndex: 20,
    }}>
      <span style={{ letterSpacing: -0.2 }}>{time}</span>
      <div style={{ width: 95, height: 30 }} />
      <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
        <svg width="17" height="11" viewBox="0 0 17 11"><rect x="0" y="6.5" width="3" height="4.5" rx="0.6" fill="#fff"/><rect x="4.5" y="4.5" width="3" height="6.5" rx="0.6" fill="#fff"/><rect x="9" y="2.5" width="3" height="8.5" rx="0.6" fill="#fff"/><rect x="13.5" y="0" width="3" height="11" rx="0.6" fill="#fff"/></svg>
        <svg width="15" height="11" viewBox="0 0 15 11"><path d="M7.5 3a7 7 0 0 1 5 2l1-1a8.5 8.5 0 0 0-12 0l1 1a7 7 0 0 1 5-2zM7.5 6a4 4 0 0 1 2.8 1.2l1-1a5.5 5.5 0 0 0-7.6 0l1 1A4 4 0 0 1 7.5 6z" fill="#fff"/><circle cx="7.5" cy="9.5" r="1.3" fill="#fff"/></svg>
        <svg width="25" height="12" viewBox="0 0 25 12"><rect x="0.5" y="0.5" width="21" height="11" rx="3" stroke="#fff" strokeOpacity="0.45" fill="none"/><rect x="2" y="2" width="18" height="8" rx="1.5" fill="#00d4ff"/><path d="M23 4v4c.7-.2 1.3-1 1.3-2s-.6-1.8-1.3-2z" fill="#fff" fillOpacity="0.5"/></svg>
      </div>
    </div>
  );
}

function DynamicIsland() {
  return (
    <div style={{
      position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
      width: 122, height: 36, borderRadius: 22, background: '#000', zIndex: 50,
    }} />
  );
}

function HomeIndicator() {
  return (
    <div style={{
      position: 'absolute', bottom: 8, left: 0, right: 0, height: 5,
      display: 'flex', justifyContent: 'center', zIndex: 60, pointerEvents: 'none',
    }}>
      <div style={{ width: 135, height: 5, borderRadius: 100, background: 'rgba(255,255,255,0.55)' }} />
    </div>
  );
}

// SCREEN 1 — Pair with Mac --------------------------------------------------
function ScreenPair({ accent, paired, onPair }) {
  return (
    <div style={{
      width: '100%', height: '100%', background: RP_BG, color: RP_TEXT,
      display: 'flex', flexDirection: 'column', position: 'relative',
    }}>
      <StatusBar />
      {/* nav */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '12px 20px 4px', height: 44,
      }}>
        <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'flex-start' }}>
          <IconBack color="#fff" />
        </div>
        <div style={{ fontFamily: RP_SANS, fontSize: 17, fontWeight: 600, letterSpacing: -0.2 }}>Pair device</div>
        <div style={{ width: 36 }} />
      </div>
      {/* viewfinder */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '36px 28px 0' }}>
        <div
          onClick={onPair}
          style={{
            width: 268, height: 268, borderRadius: 24, background: '#050505',
            position: 'relative', boxShadow: 'inset 0 0 0 1px #161616',
            cursor: 'pointer', overflow: 'hidden',
          }}>
          {/* simulated camera noise */}
          <div style={{
            position: 'absolute', inset: 0,
            background: 'radial-gradient(circle at 30% 20%, #1a1a1a, transparent 60%), radial-gradient(circle at 80% 70%, #141414, transparent 50%)',
            opacity: 0.7,
          }} />
          {/* fake QR pattern */}
          <div style={{
            position: 'absolute', inset: 36, borderRadius: 4, opacity: paired ? 1 : 0.85,
            background: 'conic-gradient(from 0deg at 50% 50%, #0e0e0e, #1c1c1c, #0e0e0e, #1c1c1c, #0e0e0e)',
            transition: 'opacity 280ms ease',
          }}>
            <QRGlyph paired={paired} accent={accent} />
          </div>
          {/* corner brackets */}
          {[[0,0,0],[1,0,90],[1,1,180],[0,1,270]].map(([x,y,r], i) => (
            <div key={i} style={{
              position: 'absolute',
              [x ? 'right' : 'left']: 14, [y ? 'bottom' : 'top']: 14,
              width: 32, height: 32, transform: `rotate(${r}deg)`,
            }}>
              <div style={{ position: 'absolute', top: 0, left: 0, width: 18, height: 3, background: accent, borderRadius: 1 }} />
              <div style={{ position: 'absolute', top: 0, left: 0, width: 3, height: 18, background: accent, borderRadius: 1 }} />
            </div>
          ))}
          {/* scanning line */}
          {!paired && (
            <div style={{
              position: 'absolute', left: 14, right: 14, height: 1.5,
              background: `linear-gradient(90deg, transparent, ${accent}, transparent)`,
              boxShadow: `0 0 12px ${accent}`,
              animation: 'rpScan 2.4s ease-in-out infinite',
            }} />
          )}
        </div>

        <div style={{
          marginTop: 26, textAlign: 'center', maxWidth: 280,
          fontFamily: RP_SANS, fontSize: 14, color: RP_MUTED_2, lineHeight: 1.45, letterSpacing: -0.1,
        }}>
          {paired ? 'Connected to your computer' : 'Point camera at the QR shown on your computer'}
        </div>

        <button
          onClick={onPair}
          style={{
            marginTop: 22, background: 'transparent', border: 'none', cursor: 'pointer',
            fontFamily: RP_SANS, fontSize: 14, fontWeight: 500, color: accent, letterSpacing: -0.1, padding: 8,
          }}>Enter code manually</button>
      </div>
      {/* footer */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
        padding: '0 24px 28px',
        fontFamily: RP_MONO, fontSize: 11, color: RP_MUTED, letterSpacing: 0.2,
      }}>
        <IconLock size={11} color={RP_MUTED} />
        <span>END-TO-END ENCRYPTED</span>
      </div>
      <HomeIndicator />
    </div>
  );
}

function QRGlyph({ paired, accent }) {
  // deterministic dotted pattern
  const cells = 11;
  const seed = [3,5,2,7,11,13,17,19,23,29,31];
  const isOn = (x, y) => {
    // corner finders
    const inFinder = (cx, cy) => x >= cx && x < cx + 3 && y >= cy && y < cy + 3;
    if (inFinder(0,0) || inFinder(cells-3,0) || inFinder(0,cells-3)) {
      const f = (cx, cy) => {
        const dx = x - cx, dy = y - cy;
        const onEdge = dx === 0 || dy === 0 || dx === 2 || dy === 2;
        const center = dx === 1 && dy === 1;
        return onEdge || center;
      };
      if (inFinder(0,0)) return f(0,0);
      if (inFinder(cells-3,0)) return f(cells-3,0);
      if (inFinder(0,cells-3)) return f(0,cells-3);
    }
    return ((x * seed[y % seed.length] + y * seed[(x + 3) % seed.length]) % 7) < 3;
  };
  const grid = [];
  for (let y = 0; y < cells; y++) for (let x = 0; x < cells; x++) {
    if (isOn(x, y)) grid.push(<rect key={`${x}-${y}`} x={x*9+2} y={y*9+2} width="7" height="7" fill={paired ? accent : '#e8e8e8'} rx="0.5" />);
  }
  return (
    <svg viewBox={`0 0 ${cells*9+4} ${cells*9+4}`} style={{ width: '100%', height: '100%', display: 'block' }}>
      <rect width="100%" height="100%" fill={paired ? '#000' : '#0a0a0a'} />
      {grid}
    </svg>
  );
}

// SCREEN 2 — Sessions ------------------------------------------------------
function ScreenSessions({ accent, onOpenSession }) {
  const sessions = [
    { id: 'protocol', title: 'remote_pi · feature/protocol', model: 'opus-4.7', when: '2 minutes ago', active: true, unread: true, locked: true },
    { id: 'rust', title: 'explore-rust', model: 'haiku', when: 'yesterday', active: false, unread: false, locked: true },
    { id: 'site', title: 'site refactor', model: 'opus', when: '3 days ago', active: false, unread: false, locked: true },
  ];
  return (
    <div style={{
      width: '100%', height: '100%', background: RP_BG, color: RP_TEXT,
      display: 'flex', flexDirection: 'column', position: 'relative',
    }}>
      <StatusBar />
      {/* header */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '14px 22px 0',
      }}>
        <div style={{ fontFamily: RP_SANS, fontSize: 28, fontWeight: 700, letterSpacing: -0.6 }}>Remote Pi</div>
        <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <IconGear color="#b5b5b5" />
        </div>
      </div>
      {/* status row */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '6px 22px 18px',
        fontFamily: RP_MONO, fontSize: 12, color: RP_MUTED_2, letterSpacing: 0.1,
      }}>
        <span style={{
          width: 7, height: 7, borderRadius: 999, background: accent,
          boxShadow: `0 0 8px ${accent}`,
        }} />
        <span style={{ color: '#cfcfcf' }}>MacBook Pro</span>
        <span style={{ color: RP_MUTED }}>·</span>
        <span style={{ color: RP_MUTED_2 }}>Connected</span>
      </div>

      <div style={{
        fontFamily: RP_SANS, fontSize: 11, fontWeight: 600,
        color: RP_MUTED, letterSpacing: 1.4, textTransform: 'uppercase',
        padding: '0 24px 10px',
      }}>Sessions</div>

      {/* cards */}
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column', gap: 10,
        padding: '0 18px', overflow: 'hidden',
      }}>
        {sessions.map(s => (
          <button
            key={s.id}
            onClick={() => onOpenSession(s.id)}
            style={{
              textAlign: 'left', cursor: 'pointer', background: RP_SURFACE,
              border: `1px solid ${RP_BORDER}`, borderLeft: s.active ? `2px solid ${accent}` : `1px solid ${RP_BORDER}`,
              borderRadius: 12, padding: '14px 14px 14px 14px',
              display: 'flex', flexDirection: 'column', gap: 6,
              position: 'relative',
            }}>
            {s.unread && (
              <span style={{
                position: 'absolute', top: 14, right: 14, width: 7, height: 7,
                borderRadius: 999, background: accent, boxShadow: `0 0 6px ${accent}`,
              }} />
            )}
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, paddingRight: s.unread ? 14 : 0 }}>
              <div style={{
                fontFamily: RP_MONO, fontSize: 13.5, color: '#fff',
                letterSpacing: -0.2, flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
              }}>{s.title}</div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
              <span style={{
                fontFamily: RP_MONO, fontSize: 10.5, color: '#bdbdbd',
                background: '#161616', border: `1px solid #1f1f1f`,
                padding: '2px 7px', borderRadius: 5, letterSpacing: 0.2,
              }}>{s.model}</span>
              <span style={{ fontFamily: RP_SANS, fontSize: 12, color: RP_MUTED }}>{s.when}</span>
              <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center' }}>
                <IconLock size={10} color={RP_MUTED} />
              </div>
            </div>
          </button>
        ))}
      </div>

      {/* FAB */}
      <button
        onClick={() => onOpenSession('protocol')}
        style={{
          position: 'absolute', right: 22, bottom: 38,
          width: 56, height: 56, borderRadius: 999, border: 'none',
          background: accent, color: '#000', cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: `0 8px 24px ${accent}55, 0 0 0 1px rgba(255,255,255,0.08) inset`,
        }}>
        <IconPlus color="#000" />
      </button>
      <HomeIndicator />
    </div>
  );
}

// SCREEN 3 — Chat with approval card --------------------------------------
function ScreenChat({ accent, decision, onDecide, onBack }) {
  return (
    <div style={{
      width: '100%', height: '100%', background: RP_BG, color: RP_TEXT,
      display: 'flex', flexDirection: 'column', position: 'relative',
    }}>
      <StatusBar />
      {/* top bar */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '12px 18px 12px',
        borderBottom: `1px solid ${RP_BORDER}`,
      }}>
        <button onClick={onBack} style={{
          width: 28, height: 28, border: 'none', background: 'transparent', cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}><IconBack color="#fff" /></button>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontFamily: RP_MONO, fontSize: 13, color: '#fff', letterSpacing: -0.2,
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>remote_pi · feature/protocol</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 2 }}>
            <IconLock size={9} color={RP_MUTED} />
            <span style={{ fontFamily: RP_MONO, fontSize: 10, color: RP_MUTED, letterSpacing: 0.3 }}>E2E</span>
          </div>
        </div>
      </div>

      {/* messages */}
      <div style={{
        flex: 1, overflow: 'auto', padding: '18px 16px 12px',
        display: 'flex', flexDirection: 'column', gap: 14,
      }}>
        {/* user bubble */}
        <div style={{ alignSelf: 'flex-end', maxWidth: '78%' }}>
          <div style={{
            background: '#1a1a1a', borderRadius: 12, padding: '10px 13px',
            fontFamily: RP_SANS, fontSize: 14, color: '#fff', lineHeight: 1.35, letterSpacing: -0.1,
          }}>Add JWT refresh to auth endpoint</div>
        </div>

        {/* agent message */}
        <div style={{ alignSelf: 'flex-start', maxWidth: '92%' }}>
          <div style={{
            fontFamily: RP_MONO, fontSize: 12.5, color: '#e6e6e6', lineHeight: 1.5, letterSpacing: 0,
          }}>
            Reading <span style={{ color: '#9fe6ff' }}>backend/src/auth/login.ts</span>…
            <span className="rp-cursor" style={{
              display: 'inline-block', width: 7, height: 14, background: accent,
              marginLeft: 4, verticalAlign: -2, animation: 'rpBlink 1s steps(1) infinite',
            }} />
          </div>
        </div>

        {/* approval card */}
        <div style={{
          alignSelf: 'stretch', background: RP_SURFACE,
          border: `1px solid ${accent}`, borderRadius: 12, padding: 14,
          boxShadow: `0 0 0 1px ${accent}22, 0 8px 20px rgba(0,0,0,0.4)`,
          opacity: decision ? 0.55 : 1, transition: 'opacity 200ms ease',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
            <IconTerminal color={accent} size={14} />
            <span style={{ fontFamily: RP_MONO, fontSize: 11.5, color: accent, letterSpacing: 0.6, textTransform: 'uppercase' }}>Bash</span>
            <span style={{ marginLeft: 'auto', fontFamily: RP_MONO, fontSize: 10, color: RP_MUTED, letterSpacing: 0.4 }}>
              {decision === 'allow' ? 'ALLOWED' : decision === 'deny' ? 'DENIED' : 'AWAITING'}
            </span>
          </div>
          <div style={{
            background: '#050505', border: `1px solid ${RP_BORDER}`, borderRadius: 8,
            padding: '10px 12px', fontFamily: RP_MONO, fontSize: 12.5, color: '#e6e6e6',
            letterSpacing: 0, lineHeight: 1.4,
          }}>
            <span style={{ color: '#6b6b6b' }}>$ </span>
            cargo test <span style={{ color: '#9fe6ff' }}>auth::jwt_refresh</span>
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
            <button
              onClick={() => onDecide('deny')}
              disabled={!!decision}
              style={{
                flex: 1, height: 38, borderRadius: 9, cursor: decision ? 'default' : 'pointer',
                background: 'transparent', color: '#cfcfcf',
                border: `1px solid #2a2a2a`,
                fontFamily: RP_SANS, fontSize: 13.5, fontWeight: 500, letterSpacing: -0.1,
              }}>Deny</button>
            <button
              onClick={() => onDecide('allow')}
              disabled={!!decision}
              style={{
                flex: 1, height: 38, borderRadius: 9, cursor: decision ? 'default' : 'pointer',
                background: accent, color: '#000', border: 'none',
                fontFamily: RP_SANS, fontSize: 13.5, fontWeight: 600, letterSpacing: -0.1,
              }}>Allow</button>
          </div>
        </div>

        {decision === 'allow' && (
          <div style={{ alignSelf: 'flex-start', maxWidth: '92%' }}>
            <div style={{
              fontFamily: RP_MONO, fontSize: 12.5, color: '#e6e6e6', lineHeight: 1.5,
            }}>
              <span style={{ color: '#6cd28a' }}>✓</span> running tests<span className="rp-cursor" style={{
                display: 'inline-block', width: 7, height: 14, background: accent,
                marginLeft: 4, verticalAlign: -2, animation: 'rpBlink 1s steps(1) infinite',
              }} />
            </div>
          </div>
        )}
      </div>

      {/* input bar */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '10px 14px 22px',
        borderTop: `1px solid ${RP_BORDER}`,
      }}>
        <button style={{
          width: 32, height: 32, background: 'transparent', border: 'none', cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}><IconPaperclip color={RP_MUTED} /></button>
        <div style={{
          flex: 1, height: 38, borderRadius: 19, background: '#0e0e0e',
          border: `1px solid ${RP_BORDER}`, display: 'flex', alignItems: 'center', padding: '0 14px',
          fontFamily: RP_MONO, fontSize: 13, color: RP_MUTED, letterSpacing: 0,
        }}>Send a message…</div>
        <button style={{
          width: 38, height: 38, borderRadius: 19, background: accent, border: 'none',
          cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: `0 0 16px ${accent}55`,
        }}><IconArrowUp color="#000" /></button>
      </div>
      <HomeIndicator />
    </div>
  );
}

// device shell -----------------------------------------------------------
function PhoneShell({ children, glow, accent }) {
  return (
    <div style={{
      position: 'relative', width: 360, height: 780,
    }}>
      {/* cyan underglow */}
      {glow > 0 && (
        <div style={{
          position: 'absolute', left: '50%', bottom: -60, transform: 'translateX(-50%)',
          width: 320, height: 180, borderRadius: '50%',
          background: `radial-gradient(ellipse at center, ${accent}, transparent 70%)`,
          opacity: glow, filter: 'blur(28px)', pointerEvents: 'none', zIndex: 0,
        }} />
      )}
      <div style={{
        position: 'relative', width: 360, height: 780, borderRadius: 46,
        background: '#000', overflow: 'hidden',
        boxShadow: '0 0 0 10px #111, 0 0 0 11px #2a2a2a, 0 50px 90px rgba(0,0,0,0.6), 0 0 60px rgba(0,212,255,0.04)',
      }}>
        <DynamicIsland />
        {children}
      </div>
    </div>
  );
}

Object.assign(window, {
  ScreenPair, ScreenSessions, ScreenChat, PhoneShell,
});
