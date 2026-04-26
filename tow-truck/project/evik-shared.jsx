// EVIK Shared Components & Design System
const C = {
  black: '#1A1A1A',
  white: '#FFFFFF',
  orange: '#FF6B35',
  green: '#10B981',
  amber: '#F59E0B',
  red: '#EF4444',
  gray50: '#F9FAFB',
  gray100: '#F3F4F6',
  gray200: '#E5E7EB',
  gray500: '#6B7280',
  gray800: '#374151',
};

// --- Icons ---
const Icon = ({ name, size = 20, color = C.black, style = {} }) => {
  const s = { width: size, height: size, display: 'inline-block', flexShrink: 0, ...style };
  const paths = {
    car: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M5 17H3a2 2 0 01-2-2V9a2 2 0 012-2h1l2-4h12l2 4h1a2 2 0 012 2v6a2 2 0 01-2 2h-2"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="17.5" r="2.5"/></svg>,
    truck: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><rect x="1" y="3" width="15" height="13" rx="1"/><path d="M16 8h4l3 5v4h-7V8z"/><circle cx="5.5" cy="18.5" r="2.5"/><circle cx="18.5" cy="18.5" r="2.5"/></svg>,
    phone: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M22 16.92v3a2 2 0 01-2.18 2 19.79 19.79 0 01-8.63-3.07 19.5 19.5 0 01-6-6A19.79 19.79 0 012.12 4.18 2 2 0 014.11 2h3a2 2 0 012 1.72c.127.96.361 1.903.7 2.81a2 2 0 01-.45 2.11L8.09 9.91a16 16 0 006 6l1.27-1.27a2 2 0 012.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0122 16.92z"/></svg>,
    chat: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/></svg>,
    star: <svg viewBox="0 0 24 24" fill={color} stroke={color} strokeWidth="1" style={s}><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>,
    starEmpty: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" style={s}><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>,
    location: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/></svg>,
    navigate: <svg viewBox="0 0 24 24" fill={color} stroke={color} strokeWidth="1" strokeLinecap="round" strokeLinejoin="round" style={s}><polygon points="3 11 22 2 13 21 11 13 3 11"/></svg>,
    check: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" style={s}><polyline points="20 6 9 17 4 12"/></svg>,
    close: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>,
    arrow: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><polyline points="9 18 15 12 9 6"/></svg>,
    upload: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><polyline points="16 16 12 12 8 16"/><line x1="12" y1="12" x2="12" y2="21"/><path d="M20.39 18.39A5 5 0 0018 9h-1.26A8 8 0 103 16.3"/></svg>,
    search: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>,
    menu: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" style={s}><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="18" x2="21" y2="18"/></svg>,
    wallet: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M20 12V22H4a2 2 0 01-2-2V6a2 2 0 012-2h16v4"/><path d="M22 12a2 2 0 00-2-2h-4a2 2 0 000 4h4a2 2 0 002-2z"/></svg>,
    history: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-4.45"/></svg>,
    user: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>,
    bell: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M18 8A6 6 0 006 8c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 01-3.46 0"/></svg>,
    info: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>,
    shield: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>,
    edit: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>,
    cash: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><rect x="1" y="4" width="22" height="16" rx="2" ry="2"/><line x1="1" y1="10" x2="23" y2="10"/></svg>,
    pin: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0118 0z"/><circle cx="12" cy="10" r="3"/></svg>,
    alert: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>,
    done: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><polyline points="20 6 9 17 4 12"/></svg>,
    time: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>,
    power: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><path d="M18.36 6.64A9 9 0 0121 12a9 9 0 01-9 9 9 9 0 01-9-9 9 9 0 012.64-6.36"/><line x1="12" y1="2" x2="12" y2="12"/></svg>,
    money: <svg viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={s}><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6"/></svg>,
  };
  return paths[name] || <svg viewBox="0 0 24 24" style={s}><circle cx="12" cy="12" r="10" fill={color} opacity="0.2"/></svg>;
};

// --- Button ---
const Btn = ({ children, variant = 'primary', onPress, disabled, loading, style = {}, small }) => {
  const base = {
    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
    borderRadius: 14, fontFamily: 'Manrope, sans-serif', fontWeight: 700,
    fontSize: small ? 14 : 16, cursor: disabled ? 'not-allowed' : 'pointer',
    border: 'none', transition: 'all 0.18s', userSelect: 'none',
    padding: small ? '10px 18px' : '16px 24px',
    opacity: disabled ? 0.45 : 1,
    letterSpacing: '0.01em',
    ...style,
  };
  const variants = {
    primary: { background: C.orange, color: C.white },
    secondary: { background: 'transparent', color: C.orange, border: `2px solid ${C.orange}` },
    ghost: { background: C.gray100, color: C.black },
    danger: { background: C.red, color: C.white },
    green: { background: C.green, color: C.white },
    dark: { background: C.black, color: C.white },
  };
  return (
    <button style={{ ...base, ...variants[variant] }} onClick={disabled ? null : onPress}
      onMouseEnter={e => { if (!disabled) e.currentTarget.style.opacity = '0.88'; }}
      onMouseLeave={e => { e.currentTarget.style.opacity = disabled ? '0.45' : '1'; }}>
      {loading ? <span style={{ display: 'inline-block', width: 18, height: 18, border: '2.5px solid rgba(255,255,255,0.4)', borderTopColor: '#fff', borderRadius: '50%', animation: 'spin 0.7s linear infinite' }} /> : children}
    </button>
  );
};

// --- Input Field ---
const Field = ({ label, value, onChange, placeholder, type = 'text', icon, style = {} }) => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 6, ...style }}>
    {label && <span style={{ fontSize: 12, fontWeight: 600, color: C.gray500, letterSpacing: '0.04em', textTransform: 'uppercase' }}>{label}</span>}
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, background: C.gray50, borderRadius: 12, padding: '13px 14px', border: `1.5px solid ${C.gray200}` }}>
      {icon && <Icon name={icon} size={18} color={C.gray500} />}
      <input value={value} onChange={e => onChange && onChange(e.target.value)} placeholder={placeholder}
        type={type} style={{ flex: 1, border: 'none', background: 'transparent', fontFamily: 'Manrope, sans-serif', fontSize: 15, color: C.black, outline: 'none' }} />
    </div>
  </div>
);

// --- Avatar placeholder ---
const Avatar = ({ name = '', size = 44, color = C.orange }) => (
  <div style={{ width: size, height: size, borderRadius: '50%', background: color, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontWeight: 700, fontSize: size * 0.35, fontFamily: 'Manrope, sans-serif', flexShrink: 0 }}>
    {name ? name[0].toUpperCase() : '?'}
  </div>
);

// --- Status Pill ---
const StatusPill = ({ label, color = C.amber, bg }) => (
  <span style={{ background: bg || color + '18', color, fontSize: 12, fontWeight: 700, padding: '4px 10px', borderRadius: 20, letterSpacing: '0.02em' }}>{label}</span>
);

// --- Map Placeholder ---
const MapBg = ({ children, style = {}, dark }) => (
  <div style={{ position: 'relative', background: dark ? '#1a2332' : '#e8f0e4', overflow: 'hidden', ...style }}>
    {/* Grid lines */}
    <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', opacity: dark ? 0.15 : 0.25 }} xmlns="http://www.w3.org/2000/svg">
      <defs><pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse"><path d="M 40 0 L 0 0 0 40" fill="none" stroke={dark ? '#fff' : '#8aad7a'} strokeWidth="0.8"/></pattern></defs>
      <rect width="100%" height="100%" fill="url(#grid)"/>
    </svg>
    {/* Roads */}
    <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }} xmlns="http://www.w3.org/2000/svg">
      <path d="M 0 60 Q 80 55 160 70 T 320 65 T 480 60" stroke={dark ? '#2d3f55' : '#ccd9c5'} strokeWidth="18" fill="none"/>
      <path d="M 0 60 Q 80 55 160 70 T 320 65 T 480 60" stroke={dark ? '#fff' : '#fff'} strokeWidth="2" fill="none" strokeDasharray="20 15" opacity="0.4"/>
      <path d="M 40 0 Q 50 80 60 160 T 55 320" stroke={dark ? '#2d3f55' : '#ccd9c5'} strokeWidth="14" fill="none"/>
      <path d="M 160 0 Q 170 80 165 160 T 168 320" stroke={dark ? '#2d3f55' : '#ccd9c5'} strokeWidth="10" fill="none"/>
      <path d="M 0 150 Q 120 145 240 155 T 480 150" stroke={dark ? '#2d3f55' : '#ccd9c5'} strokeWidth="10" fill="none"/>
      <path d="M 0 250 Q 100 245 200 258 T 480 252" stroke={dark ? '#2d3f55' : '#ccd9c5'} strokeWidth="14" fill="none"/>
    </svg>
    {children}
  </div>
);

// --- Marker ---
const Marker = ({ type, x = '50%', y = '50%', pulse }) => {
  const colors = { client: C.orange, driver: C.green, dest: C.black };
  const col = colors[type] || C.orange;
  return (
    <div style={{ position: 'absolute', left: x, top: y, transform: 'translate(-50%, -100%)', zIndex: 10 }}>
      {pulse && <div style={{ position: 'absolute', width: 40, height: 40, borderRadius: '50%', border: `2px solid ${col}`, top: -6, left: -8, animation: 'pulseRing 1.5s ease-out infinite', opacity: 0.5 }} />}
      {pulse && <div style={{ position: 'absolute', width: 60, height: 60, borderRadius: '50%', border: `2px solid ${col}`, top: -16, left: -18, animation: 'pulseRing 1.5s ease-out infinite 0.5s', opacity: 0.3 }} />}
      <div style={{ width: 28, height: 28, borderRadius: '50% 50% 50% 0', background: col, border: '3px solid #fff', transform: 'rotate(-45deg)', boxShadow: '0 3px 10px rgba(0,0,0,0.25)' }} />
    </div>
  );
};

// --- Divider ---
const Divider = ({ style = {} }) => <div style={{ height: 1, background: C.gray100, margin: '4px 0', ...style }} />;

// --- Section label ---
const SectionLabel = ({ children }) => <div style={{ fontSize: 11, fontWeight: 700, color: C.gray500, letterSpacing: '0.08em', textTransform: 'uppercase', marginBottom: 8 }}>{children}</div>;

// --- Stars ---
const Stars = ({ rating = 5, size = 16, interactive, onChange }) => (
  <div style={{ display: 'flex', gap: 2 }}>
    {[1,2,3,4,5].map(i => (
      <span key={i} onClick={() => interactive && onChange && onChange(i)} style={{ cursor: interactive ? 'pointer' : 'default' }}>
        <Icon name={i <= rating ? 'star' : 'starEmpty'} size={size} color={i <= rating ? C.amber : C.gray200} />
      </span>
    ))}
  </div>
);

// --- Route line on map ---
const RouteLine = ({ dark }) => (
  <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', pointerEvents: 'none' }}>
    <path d="M 60 200 Q 120 160 180 140 Q 220 125 260 100" stroke={dark ? '#60a5fa' : C.orange} strokeWidth="4" fill="none" strokeLinecap="round" strokeDasharray="1" opacity="0.9"/>
  </svg>
);

// Export everything
Object.assign(window, {
  C, Icon, Btn, Field, Avatar, StatusPill, MapBg, Marker, Divider, SectionLabel, Stars, RouteLine
});
