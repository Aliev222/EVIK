// EVIK Driver Screens

const DriverBottomNav = ({ active, onNav }) => {
  const items = [
    { id: 'home', icon: 'navigate', label: 'Главная' },
    { id: 'orders', icon: 'history', label: 'Заказы' },
    { id: 'earnings', icon: 'money', label: 'Доходы' },
    { id: 'profile', icon: 'user', label: 'Профиль' },
  ];
  return (
    <div style={{ display: 'flex', borderTop: `1px solid ${C.gray100}`, background: C.white, padding: '8px 0 4px' }}>
      {items.map(it => (
        <div key={it.id} onClick={() => onNav(it.id)} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, cursor: 'pointer', padding: '4px 0' }}>
          <Icon name={it.icon} size={22} color={active === it.id ? C.orange : C.gray500} />
          <span style={{ fontSize: 10, fontWeight: 600, color: active === it.id ? C.orange : C.gray500 }}>{it.label}</span>
        </div>
      ))}
    </div>
  );
};

// 4.1 Offline
const DriverOffline = ({ onGoOnline }) => (
  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: C.white, padding: '28px 24px 32px' }}>
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 32 }}>
      <div>
        <div style={{ fontSize: 22, fontWeight: 800, color: C.black }}>Добрый день,</div>
        <div style={{ fontSize: 22, fontWeight: 800, color: C.black }}>Михаил 👋</div>
      </div>
      <Avatar name="М" size={48} color={C.black} />
    </div>
    {/* Offline card */}
    <div style={{ background: C.gray50, borderRadius: 20, padding: '28px 24px', textAlign: 'center', marginBottom: 24, border: `1.5px solid ${C.gray200}` }}>
      <div style={{ width: 64, height: 64, borderRadius: 20, background: C.gray200, display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 16px' }}>
        <Icon name="power" size={28} color={C.gray500} />
      </div>
      <div style={{ fontSize: 17, fontWeight: 700, color: C.gray800, marginBottom: 6 }}>Вы не в сети</div>
      <div style={{ fontSize: 14, color: C.gray500 }}>Включите режим работы, чтобы получать заказы</div>
    </div>
    {/* Yesterday stats */}
    <div style={{ background: C.gray50, borderRadius: 16, padding: '16px 20px', marginBottom: 24, border: `1px solid ${C.gray200}` }}>
      <div style={{ fontSize: 12, fontWeight: 700, color: C.gray500, textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: 14 }}>Вчера</div>
      <div style={{ display: 'flex', justifyContent: 'space-around' }}>
        {[{ val: '4', label: 'Заказа' }, { val: '6 200 ₽', label: 'Заработано' }, { val: '4.9 ⭐', label: 'Рейтинг' }].map(s => (
          <div key={s.label} style={{ textAlign: 'center' }}>
            <div style={{ fontSize: 18, fontWeight: 800, color: C.black }}>{s.val}</div>
            <div style={{ fontSize: 11, color: C.gray500, marginTop: 3 }}>{s.label}</div>
          </div>
        ))}
      </div>
    </div>
    <div style={{ marginTop: 'auto' }}>
      <Btn variant="green" style={{ width: '100%', fontSize: 17, padding: '17px' }} onPress={onGoOnline}>
        Начать работу
      </Btn>
    </div>
  </div>
);

// 4.2 Online - waiting
const DriverOnline = ({ onOrderPress, onGoOffline }) => {
  const orders = [
    { id: 1, car: 'Toyota Camry', type: '🚗 Легковой', from: 'ул. Тверская, 15', to: 'СТО на Ленинском', price: '2 300 ₽', dist: '3.2 км', time: '8 мин', problem: 'Не заводится' },
    { id: 2, car: 'BMW X5', type: '🚙 Внедорожник', from: 'Садовое кольцо, 28', to: 'Дилерский центр', price: '3 100 ₽', dist: '5.8 км', time: '12 мин', problem: 'ДТП' },
  ];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: C.gray50 }}>
      {/* AppBar */}
      <div style={{ padding: '14px 20px', background: C.white, borderBottom: `1px solid ${C.gray100}`, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div>
          <div style={{ fontSize: 12, color: C.gray500, fontWeight: 500 }}>Сегодня</div>
          <div style={{ fontSize: 15, fontWeight: 800, color: C.black }}>2 заказа · 3 200 ₽</div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <div style={{ width: 8, height: 8, borderRadius: '50%', background: C.green, boxShadow: `0 0 0 3px ${C.green}30` }} />
            <span style={{ fontSize: 13, fontWeight: 700, color: C.green }}>В сети</span>
          </div>
          <div onClick={onGoOffline} style={{ width: 44, height: 26, borderRadius: 13, background: C.green, position: 'relative', cursor: 'pointer', transition: 'background 0.2s' }}>
            <div style={{ width: 20, height: 20, borderRadius: '50%', background: C.white, position: 'absolute', top: 3, right: 3, boxShadow: '0 1px 4px rgba(0,0,0,0.2)', transition: 'right 0.2s' }} />
          </div>
        </div>
      </div>
      {/* Map strip */}
      <MapBg style={{ height: 160 }}>
        <Marker type="driver" x="50%" y="55%" />
      </MapBg>
      {/* Orders list */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px' }}>
        <SectionLabel>Доступные заказы ({orders.length})</SectionLabel>
        {orders.map(o => (
          <div key={o.id} style={{ background: C.white, borderRadius: 16, padding: '16px', marginBottom: 12, boxShadow: '0 1px 8px rgba(0,0,0,0.06)', border: `1px solid ${C.gray100}` }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
              <span style={{ fontSize: 13, fontWeight: 700, color: C.black }}>{o.type} · {o.car}</span>
              <StatusPill label={o.problem} color={o.problem === 'ДТП' ? C.red : C.amber} />
            </div>
            <div style={{ display: 'flex', gap: 6, marginBottom: 10 }}>
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 4 }}>
                <div style={{ width: 7, height: 7, borderRadius: '50%', background: C.orange }} />
                <div style={{ width: 1.5, height: 20, background: C.gray200 }} />
                <div style={{ width: 7, height: 7, borderRadius: '50%', background: C.black }} />
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 12, color: C.gray800, fontWeight: 600, marginBottom: 8 }}>{o.from}</div>
                <div style={{ fontSize: 12, color: C.gray800, fontWeight: 600 }}>{o.to}</div>
              </div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ display: 'flex', gap: 14 }}>
                <span style={{ fontSize: 13, color: C.gray500 }}>📍 {o.dist}</span>
                <span style={{ fontSize: 13, color: C.gray500 }}>⏱ {o.time}</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ fontSize: 18, fontWeight: 800, color: C.black }}>{o.price}</span>
                <Btn small onPress={onOrderPress}>Принять</Btn>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

// 4.3 New Order Modal (countdown)
const DriverNewOrder = ({ onAccept, onDecline }) => {
  const [count, setCount] = React.useState(30);
  React.useEffect(() => {
    if (count <= 0) { onDecline(); return; }
    const t = setTimeout(() => setCount(c => c - 1), 1000);
    return () => clearTimeout(t);
  }, [count]);
  const pct = (count / 30) * 100;
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: C.white }}>
      {/* Countdown header */}
      <div style={{ padding: '20px 20px 0', textAlign: 'center' }}>
        <div style={{ fontSize: 13, fontWeight: 600, color: C.gray500, marginBottom: 8 }}>Новый заказ!</div>
        <div style={{ position: 'relative', width: 72, height: 72, margin: '0 auto 16px' }}>
          <svg viewBox="0 0 72 72" style={{ width: 72, height: 72, transform: 'rotate(-90deg)' }}>
            <circle cx="36" cy="36" r="30" fill="none" stroke={C.gray100} strokeWidth="6" />
            <circle cx="36" cy="36" r="30" fill="none" stroke={count > 10 ? C.orange : C.red} strokeWidth="6"
              strokeDasharray={`${2 * Math.PI * 30}`}
              strokeDashoffset={`${2 * Math.PI * 30 * (1 - pct / 100)}`}
              strokeLinecap="round" style={{ transition: 'stroke-dashoffset 0.9s linear, stroke 0.3s' }} />
          </svg>
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 22, fontWeight: 800, color: count > 10 ? C.black : C.red }}>{count}</div>
        </div>
      </div>
      {/* Map */}
      <MapBg style={{ height: 140 }}>
        <RouteLine />
        <Marker type="client" x="35%" y="55%" />
        <Marker type="dest" x="65%" y="35%" />
      </MapBg>
      {/* Details */}
      <div style={{ flex: 1, padding: '16px 20px', overflow: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
          <div>
            <div style={{ fontSize: 18, fontWeight: 800, color: C.black }}>2 300 ₽</div>
            <div style={{ fontSize: 12, color: C.gray500 }}>Оплата картой</div>
          </div>
          <div style={{ textAlign: 'right' }}>
            <StatusPill label="Не заводится" color={C.amber} />
            <div style={{ fontSize: 12, color: C.gray500, marginTop: 4 }}>🚗 Toyota Camry</div>
          </div>
        </div>
        <div style={{ background: C.gray50, borderRadius: 14, padding: '14px', marginBottom: 14 }}>
          {[{ icon: 'location', color: C.orange, text: 'ул. Тверская, 15', label: 'Забрать' }, { icon: 'pin', color: C.black, text: 'СТО Автодром, ул. Ленинский, 42', label: 'Доставить' }].map(r => (
            <div key={r.label} style={{ display: 'flex', gap: 10, alignItems: 'flex-start', marginBottom: r.label === 'Забрать' ? 10 : 0 }}>
              <Icon name={r.icon} size={16} color={r.color} style={{ marginTop: 2 }} />
              <div>
                <div style={{ fontSize: 10, fontWeight: 700, color: C.gray500, textTransform: 'uppercase', letterSpacing: '0.04em' }}>{r.label}</div>
                <div style={{ fontSize: 13, fontWeight: 600, color: C.black }}>{r.text}</div>
              </div>
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', gap: 14 }}>
          <div style={{ flex: 1, textAlign: 'center', padding: '10px', background: C.gray50, borderRadius: 10 }}>
            <div style={{ fontSize: 15, fontWeight: 800, color: C.black }}>3.2 км</div>
            <div style={{ fontSize: 11, color: C.gray500 }}>до клиента</div>
          </div>
          <div style={{ flex: 1, textAlign: 'center', padding: '10px', background: C.gray50, borderRadius: 10 }}>
            <div style={{ fontSize: 15, fontWeight: 800, color: C.black }}>8 мин</div>
            <div style={{ fontSize: 11, color: C.gray500 }}>время подачи</div>
          </div>
          <div style={{ flex: 1, textAlign: 'center', padding: '10px', background: C.gray50, borderRadius: 10 }}>
            <div style={{ fontSize: 15, fontWeight: 800, color: C.black }}>12 км</div>
            <div style={{ fontSize: 11, color: C.gray500 }}>маршрут</div>
          </div>
        </div>
      </div>
      {/* Actions */}
      <div style={{ padding: '12px 20px 24px', display: 'flex', gap: 12 }}>
        <Btn variant="ghost" style={{ flex: 1, color: C.red }} onPress={onDecline}>Отклонить</Btn>
        <Btn variant="green" style={{ flex: 2, fontSize: 16 }} onPress={onAccept}>✓ Принять заказ</Btn>
      </div>
    </div>
  );
};

// 4.4 Active Order
const DriverActiveOrder = ({ onComplete }) => {
  const steps = ['Еду к клиенту', 'Я на месте', 'Начать эвакуацию', 'Завершить'];
  const [step, setStep] = React.useState(0);
  const advance = () => { if (step < steps.length - 1) setStep(s => s + 1); else onComplete(); };
  const stepColors = [C.amber, C.blue || '#3B82F6', C.orange, C.green];
  const currentColor = [C.amber, '#3B82F6', C.orange, C.green][step];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: C.gray50 }}>
      {/* Status bar */}
      <div style={{ padding: '14px 20px', background: C.white, borderBottom: `1px solid ${C.gray100}` }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <StatusPill label={steps[step]} color={currentColor} />
          <span style={{ fontSize: 15, fontWeight: 800, color: C.black }}>2 300 ₽</span>
        </div>
        {/* Step progress */}
        <div style={{ display: 'flex', gap: 6, marginTop: 12 }}>
          {steps.map((s, i) => (
            <div key={i} style={{ flex: 1, height: 4, borderRadius: 2, background: i <= step ? currentColor : C.gray200, transition: 'background 0.3s' }} />
          ))}
        </div>
      </div>
      <MapBg style={{ flex: 1 }}>
        <RouteLine />
        <Marker type="driver" x="40%" y="55%" />
        <Marker type="client" x="60%" y="38%" />
      </MapBg>
      {/* Client card */}
      <div style={{ padding: '16px 20px 20px', background: C.white }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 14 }}>
          <Avatar name="А" size={44} color={C.orange} />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 14, fontWeight: 700, color: C.black }}>Алексей Иванов</div>
            <div style={{ fontSize: 12, color: C.gray500 }}>🚗 Toyota Camry · Не заводится</div>
          </div>
          <div style={{ display: 'flex', gap: 8 }}>
            <div style={{ width: 38, height: 38, borderRadius: 10, background: C.gray100, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
              <Icon name="phone" size={17} color={C.black} />
            </div>
            <div style={{ width: 38, height: 38, borderRadius: 10, background: C.gray100, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
              <Icon name="chat" size={17} color={C.black} />
            </div>
          </div>
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <Btn variant="ghost" style={{ flex: 1, fontSize: 13 }} onPress={() => {}}>
            <Icon name="navigate" size={16} color={C.black} />Навигатор
          </Btn>
          <Btn style={{ flex: 2, fontSize: 14 }} variant={step === steps.length - 1 ? 'green' : 'primary'} onPress={advance}>
            {step < steps.length - 1 ? steps[step + 1] : '✓ Завершить заказ'}
          </Btn>
        </div>
      </div>
    </div>
  );
};

Object.assign(window, {
  DriverBottomNav, DriverOffline, DriverOnline, DriverNewOrder, DriverActiveOrder
});
