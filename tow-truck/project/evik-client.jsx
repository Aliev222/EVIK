// EVIK Client Screens

const ClientBottomNav = ({ active, onNav }) => {
  const items = [
    { id: 'home', icon: 'navigate', label: 'Главная' },
    { id: 'history', icon: 'history', label: 'Заказы' },
    { id: 'wallet', icon: 'wallet', label: 'Оплата' },
    { id: 'profile', icon: 'user', label: 'Профиль' },
  ];
  return (
    <div style={{ display: 'flex', borderTop: `1px solid ${C.gray100}`, background: C.white, padding: '8px 0 4px' }}>
      {items.map(it => (
        <div key={it.id} onClick={() => onNav(it.id)} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, cursor: 'pointer', padding: '4px 0' }}>
          <Icon name={it.icon} size={22} color={active === it.id ? C.orange : C.gray500} />
          <span style={{ fontSize: 10, fontWeight: 600, color: active === it.id ? C.orange : C.gray500, letterSpacing: '0.02em' }}>{it.label}</span>
        </div>
      ))}
    </div>
  );
};

// 3.1 Idle Home
const ClientIdle = ({ onOrder, darkMap }) => (
  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', position: 'relative' }}>
    {/* AppBar */}
    <div style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20, padding: '12px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
      <div style={{ background: C.white, borderRadius: 14, padding: '8px 14px', display: 'flex', alignItems: 'center', gap: 8, boxShadow: '0 2px 12px rgba(0,0,0,0.12)' }}>
        <div style={{ width: 8, height: 8, borderRadius: '50%', background: C.orange }} />
        <span style={{ fontSize: 13, fontWeight: 700, color: C.black, fontFamily: 'Manrope, sans-serif' }}>Москва, ЦАО</span>
      </div>
      <Avatar name="А" size={40} color={C.black} />
    </div>
    {/* Map */}
    <MapBg dark={darkMap} style={{ flex: 1 }}>
      <Marker type="client" x="50%" y="55%" />
      {/* Geo button */}
      <div style={{ position: 'absolute', right: 16, bottom: 100, width: 44, height: 44, borderRadius: 12, background: C.white, boxShadow: '0 2px 12px rgba(0,0,0,0.15)', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
        <Icon name="navigate" size={20} color={C.orange} />
      </div>
    </MapBg>
    {/* Bottom CTA */}
    <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, padding: '16px 20px 20px', background: 'linear-gradient(to top, rgba(255,255,255,1) 70%, transparent)' }}>
      <Btn style={{ width: '100%', fontSize: 17, padding: '18px 24px', borderRadius: 16, boxShadow: `0 4px 20px ${C.orange}50` }} onPress={onOrder}>
        🚛 Вызвать эвакуатор
      </Btn>
    </div>
  </div>
);

// 3.2 Selecting location
const ClientSelecting = ({ onConfirm, onBack }) => {
  const [address, setAddress] = React.useState('ул. Тверская, 15');
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', position: 'relative' }}>
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 20, padding: '12px 16px', background: 'rgba(255,255,255,0.95)', backdropFilter: 'blur(8px)', borderBottom: `1px solid ${C.gray100}` }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12 }}>
          <div onClick={onBack} style={{ width: 36, height: 36, borderRadius: 10, background: C.gray100, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
            <Icon name="arrow" size={16} color={C.black} style={{ transform: 'rotate(180deg)' }} />
          </div>
          <span style={{ fontSize: 16, fontWeight: 700, color: C.black }}>Выберите место</span>
        </div>
        <div style={{ background: C.orange + '10', borderRadius: 12, padding: '10px 14px', border: `1.5px solid ${C.orange}30`, display: 'flex', alignItems: 'center', gap: 10 }}>
          <Icon name="pin" size={16} color={C.orange} />
          <span style={{ fontSize: 13, fontWeight: 600, color: C.gray800 }}>Где стоит ваш автомобиль?</span>
        </div>
      </div>
      <MapBg style={{ flex: 1, marginTop: 100 }}>
        {/* Crosshair */}
        <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)', zIndex: 10 }}>
          <div style={{ width: 2, height: 24, background: C.orange, position: 'absolute', top: -24, left: '50%', transform: 'translateX(-50%)' }} />
          <div style={{ width: 2, height: 24, background: C.orange, position: 'absolute', bottom: -24, left: '50%', transform: 'translateX(-50%)' }} />
          <div style={{ height: 2, width: 24, background: C.orange, position: 'absolute', left: -24, top: '50%', transform: 'translateY(-50%)' }} />
          <div style={{ height: 2, width: 24, background: C.orange, position: 'absolute', right: -24, top: '50%', transform: 'translateY(-50%)' }} />
          <div style={{ width: 14, height: 14, borderRadius: '50%', background: C.orange, border: '3px solid #fff', boxShadow: '0 2px 8px rgba(0,0,0,0.3)' }} />
        </div>
      </MapBg>
      <div style={{ padding: '16px 20px 20px', background: C.white }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px', background: C.gray50, borderRadius: 14, border: `1.5px solid ${C.gray200}`, marginBottom: 14 }}>
          <Icon name="location" size={18} color={C.orange} />
          <span style={{ flex: 1, fontSize: 14, fontWeight: 600, color: C.black }}>{address}</span>
          <Icon name="edit" size={16} color={C.gray500} />
        </div>
        <Btn style={{ width: '100%' }} onPress={onConfirm}>Подтвердить место</Btn>
      </div>
    </div>
  );
};

// 3.3 Order Form
const ClientOrderForm = ({ onSubmit, onBack }) => {
  const [from] = React.useState('ул. Тверская, 15');
  const [to, setTo] = React.useState('');
  const [carType, setCarType] = React.useState('');
  const [problem, setProblem] = React.useState('');
  const [payment, setPayment] = React.useState('card');
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: C.white }}>
      <div style={{ padding: '16px 20px', display: 'flex', alignItems: 'center', gap: 14, borderBottom: `1px solid ${C.gray100}` }}>
        <div onClick={onBack} style={{ width: 36, height: 36, borderRadius: 10, background: C.gray100, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
          <Icon name="arrow" size={16} color={C.black} style={{ transform: 'rotate(180deg)' }} />
        </div>
        <span style={{ fontSize: 17, fontWeight: 800, color: C.black }}>Оформить заказ</span>
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '20px' }}>
        {/* Route */}
        <div style={{ background: C.gray50, borderRadius: 16, padding: '16px', marginBottom: 16 }}>
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12, marginBottom: 14 }}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 4 }}>
              <div style={{ width: 10, height: 10, borderRadius: '50%', background: C.orange, border: '2px solid #fff', boxShadow: `0 0 0 2px ${C.orange}` }} />
              <div style={{ width: 2, height: 30, background: C.gray200, margin: '4px 0' }} />
              <div style={{ width: 10, height: 10, borderRadius: '50%', background: C.black, border: '2px solid #fff', boxShadow: `0 0 0 2px ${C.black}` }} />
            </div>
            <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 14 }}>
              <div>
                <div style={{ fontSize: 11, fontWeight: 600, color: C.gray500, marginBottom: 2, textTransform: 'uppercase', letterSpacing: '0.04em' }}>Откуда</div>
                <div style={{ fontSize: 14, fontWeight: 600, color: C.black }}>{from}</div>
              </div>
              <div>
                <div style={{ fontSize: 11, fontWeight: 600, color: C.gray500, marginBottom: 2, textTransform: 'uppercase', letterSpacing: '0.04em' }}>Куда</div>
                <input value={to} onChange={e => setTo(e.target.value)} placeholder="Введите адрес СТО или стоянки"
                  style={{ fontSize: 14, fontWeight: 600, color: C.black, border: 'none', background: 'transparent', outline: 'none', width: '100%', fontFamily: 'Manrope, sans-serif' }} />
              </div>
            </div>
          </div>
        </div>
        {/* Car type */}
        <div style={{ marginBottom: 16 }}>
          <SectionLabel>Тип автомобиля</SectionLabel>
          <div style={{ display: 'flex', gap: 8 }}>
            {[{ id: 'sedan', label: 'Легковой', emoji: '🚗' }, { id: 'suv', label: 'Внедорожник', emoji: '🚙' }, { id: 'truck', label: 'Грузовой', emoji: '🚚' }].map(t => (
              <div key={t.id} onClick={() => setCarType(t.id)} style={{ flex: 1, padding: '10px 6px', borderRadius: 12, border: `2px solid ${carType === t.id ? C.orange : C.gray200}`, background: carType === t.id ? C.orange + '10' : C.white, cursor: 'pointer', textAlign: 'center', transition: 'all 0.15s' }}>
                <div style={{ fontSize: 20 }}>{t.emoji}</div>
                <div style={{ fontSize: 11, fontWeight: 600, color: carType === t.id ? C.orange : C.gray800, marginTop: 4 }}>{t.label}</div>
              </div>
            ))}
          </div>
        </div>
        {/* Problem */}
        <div style={{ marginBottom: 16 }}>
          <SectionLabel>Причина вызова</SectionLabel>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {[{ id: 'nostart', label: 'Не заводится' }, { id: 'accident', label: 'ДТП' }, { id: 'flat', label: 'Прокол колеса' }, { id: 'other', label: 'Другое' }].map(p => (
              <div key={p.id} onClick={() => setProblem(p.id)} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderRadius: 12, border: `2px solid ${problem === p.id ? C.orange : C.gray200}`, background: problem === p.id ? C.orange + '08' : C.white, cursor: 'pointer', transition: 'all 0.15s' }}>
                <div style={{ width: 18, height: 18, borderRadius: '50%', border: `2px solid ${problem === p.id ? C.orange : C.gray300}`, background: problem === p.id ? C.orange : 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  {problem === p.id && <div style={{ width: 8, height: 8, borderRadius: '50%', background: '#fff' }} />}
                </div>
                <span style={{ fontSize: 14, fontWeight: 600, color: C.black }}>{p.label}</span>
              </div>
            ))}
          </div>
        </div>
        {/* Payment */}
        <div style={{ marginBottom: 8 }}>
          <SectionLabel>Оплата</SectionLabel>
          <div style={{ display: 'flex', gap: 10 }}>
            {[{ id: 'card', label: 'Карта', icon: 'cash' }, { id: 'cash', label: 'Наличные', icon: 'money' }].map(p => (
              <div key={p.id} onClick={() => setPayment(p.id)} style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8, padding: '12px 14px', borderRadius: 12, border: `2px solid ${payment === p.id ? C.orange : C.gray200}`, background: payment === p.id ? C.orange + '08' : C.white, cursor: 'pointer', transition: 'all 0.15s' }}>
                <Icon name={p.icon} size={16} color={payment === p.id ? C.orange : C.gray500} />
                <span style={{ fontSize: 13, fontWeight: 600, color: payment === p.id ? C.orange : C.gray800 }}>{p.label}</span>
              </div>
            ))}
          </div>
        </div>
        {/* Price */}
        <div style={{ background: C.gray50, borderRadius: 14, padding: '14px 16px', border: `1.5px solid ${C.gray200}`, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: 14, color: C.gray500, fontWeight: 500 }}>Стоимость</span>
          <span style={{ fontSize: 20, fontWeight: 800, color: C.black }}>2 500 – 3 000 ₽</span>
        </div>
      </div>
      <div style={{ padding: '12px 20px 20px' }}>
        <Btn style={{ width: '100%', fontSize: 17, padding: '17px 24px', boxShadow: `0 4px 20px ${C.orange}40` }} onPress={onSubmit}>
          Заказать эвакуатор
        </Btn>
      </div>
    </div>
  );
};

// 3.4 Searching
const ClientSearching = ({ onCancel }) => {
  const [secs, setSecs] = React.useState(0);
  React.useEffect(() => {
    const t = setInterval(() => setSecs(s => s + 1), 1000);
    return () => clearInterval(t);
  }, []);
  const mins = String(Math.floor(secs / 60)).padStart(2, '0');
  const s2 = String(secs % 60).padStart(2, '0');
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', position: 'relative' }}>
      <MapBg style={{ flex: 1 }}>
        {/* Pulse rings */}
        <div style={{ position: 'absolute', top: '42%', left: '50%', transform: 'translate(-50%,-50%)' }}>
          {[0,1,2].map(i => (
            <div key={i} style={{ position: 'absolute', width: 60 + i*50, height: 60 + i*50, borderRadius: '50%', border: `2px solid ${C.orange}`, top: '50%', left: '50%', transform: 'translate(-50%,-50%)', animation: `pulseRing 2s ease-out ${i * 0.5}s infinite`, opacity: 0.5 - i * 0.1 }} />
          ))}
          <div style={{ width: 24, height: 24, borderRadius: '50%', background: C.orange, border: '3px solid #fff', boxShadow: `0 0 0 4px ${C.orange}40`, position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)' }} />
        </div>
      </MapBg>
      <div style={{ padding: '16px 20px 24px', background: C.white }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 20 }}>
          <div style={{ width: 48, height: 48, borderRadius: 14, background: C.amber + '15', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="search" size={22} color={C.amber} />
          </div>
          <div>
            <div style={{ fontSize: 17, fontWeight: 800, color: C.black }}>Ищем водителя...</div>
            <div style={{ fontSize: 14, color: C.gray500, marginTop: 2 }}>Поиск: <span style={{ fontWeight: 700, color: C.amber }}>{mins}:{s2}</span></div>
          </div>
          <div style={{ marginLeft: 'auto' }}>
            <div style={{ display: 'flex', gap: 4 }}>
              {[0,1,2].map(i => (
                <div key={i} style={{ width: 8, height: 8, borderRadius: '50%', background: C.amber, animation: `dotPulse 1s ease ${i * 0.2}s infinite` }} />
              ))}
            </div>
          </div>
        </div>
        <Btn variant="ghost" style={{ width: '100%', color: C.red, border: `1.5px solid ${C.red}20` }} onPress={onCancel}>
          Отменить поиск
        </Btn>
      </div>
    </div>
  );
};

// 3.5 Driver Assigned
const ClientDriverAssigned = ({ onNext }) => (
  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', position: 'relative' }}>
    <MapBg style={{ flex: 1 }}>
      <RouteLine />
      <Marker type="driver" x="35%" y="40%" />
      <Marker type="client" x="60%" y="60%" />
    </MapBg>
    <div style={{ padding: '20px 20px 24px', background: C.white }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginBottom: 16 }}>
        <Avatar name="М" size={52} color={C.black} />
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 16, fontWeight: 800, color: C.black }}>Михаил Соколов</div>
          <Stars rating={5} size={14} />
          <div style={{ fontSize: 12, color: C.gray500, marginTop: 2 }}>КАМАЗ 65117 · А 234 КО 77</div>
        </div>
        <div style={{ background: C.green + '15', borderRadius: 12, padding: '8px 12px', textAlign: 'center' }}>
          <div style={{ fontSize: 11, color: C.gray500, fontWeight: 600 }}>Прибудет</div>
          <div style={{ fontSize: 17, fontWeight: 800, color: C.green }}>15 мин</div>
        </div>
      </div>
      <Divider style={{ margin: '0 0 16px' }} />
      <div style={{ display: 'flex', gap: 12 }}>
        <Btn variant="ghost" style={{ flex: 1, gap: 8 }} onPress={() => {}}>
          <Icon name="phone" size={18} color={C.black} />Позвонить
        </Btn>
        <Btn variant="ghost" style={{ flex: 1, gap: 8 }} onPress={onNext}>
          <Icon name="chat" size={18} color={C.black} />Написать
        </Btn>
      </div>
    </div>
  </div>
);

// 3.6 Evacuating
const ClientEvacuating = ({ onNext }) => (
  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', position: 'relative' }}>
    <MapBg style={{ flex: 1 }}>
      <RouteLine />
      <Marker type="driver" x="42%" y="50%" />
      <Marker type="dest" x="65%" y="30%" />
    </MapBg>
    <div style={{ padding: '20px 20px 24px', background: C.white }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16 }}>
        <div style={{ width: 48, height: 48, borderRadius: 14, background: C.orange + '15', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon name="truck" size={22} color={C.orange} />
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 16, fontWeight: 800, color: C.black }}>Везёт ваш автомобиль</div>
          <div style={{ fontSize: 14, color: C.gray500 }}>Доставка через <span style={{ fontWeight: 700, color: C.orange }}>25 мин</span></div>
        </div>
        <StatusPill label="В пути" color={C.orange} />
      </div>
      {/* Progress */}
      <div style={{ marginBottom: 16 }}>
        <div style={{ height: 6, background: C.gray100, borderRadius: 3, overflow: 'hidden' }}>
          <div style={{ width: '55%', height: '100%', background: `linear-gradient(90deg, ${C.orange}, ${C.amber})`, borderRadius: 3 }} />
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6 }}>
          <span style={{ fontSize: 11, color: C.gray500, fontWeight: 600 }}>Забрал авто</span>
          <span style={{ fontSize: 11, color: C.gray500, fontWeight: 600 }}>Доставка</span>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 12 }}>
        <Btn variant="ghost" style={{ flex: 1 }} onPress={() => {}}>
          <Icon name="phone" size={18} color={C.black} />
        </Btn>
        <Btn variant="ghost" style={{ flex: 1 }} onPress={() => {}}>
          <Icon name="chat" size={18} color={C.black} />
        </Btn>
        <Btn variant="ghost" style={{ flex: 3 }} onPress={onNext}>Отследить</Btn>
      </div>
    </div>
  </div>
);

// 3.7 Completed
const ClientCompleted = ({ onReset }) => {
  const [rating, setRating] = React.useState(5);
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: C.white, padding: '32px 24px 28px', alignItems: 'center' }}>
      <div style={{ width: 72, height: 72, borderRadius: 22, background: C.green + '15', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 16 }}>
        <Icon name="check" size={34} color={C.green} />
      </div>
      <StatusPill label="Заказ завершён" color={C.green} />
      <div style={{ fontSize: 22, fontWeight: 800, color: C.black, marginTop: 12, textAlign: 'center', lineHeight: 1.3 }}>Автомобиль доставлен!</div>
      <div style={{ fontSize: 14, color: C.gray500, marginTop: 8, textAlign: 'center' }}>ул. Академика Королёва, 12</div>
      {/* Receipt */}
      <div style={{ width: '100%', background: C.gray50, borderRadius: 16, padding: '20px', margin: '24px 0', border: `1px solid ${C.gray200}` }}>
        {[
          { label: 'Подача', val: '500 ₽' },
          { label: 'Транспортировка', val: '1 800 ₽' },
          { label: 'Расстояние', val: '12 км' },
        ].map(r => (
          <div key={r.label} style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 0', borderBottom: `1px solid ${C.gray200}` }}>
            <span style={{ fontSize: 14, color: C.gray500 }}>{r.label}</span>
            <span style={{ fontSize: 14, fontWeight: 600, color: C.black }}>{r.val}</span>
          </div>
        ))}
        <div style={{ display: 'flex', justifyContent: 'space-between', paddingTop: 12 }}>
          <span style={{ fontSize: 16, fontWeight: 700, color: C.black }}>Итого</span>
          <span style={{ fontSize: 18, fontWeight: 800, color: C.orange }}>2 300 ₽</span>
        </div>
      </div>
      {/* Rating */}
      <div style={{ textAlign: 'center', marginBottom: 24 }}>
        <div style={{ fontSize: 15, fontWeight: 700, color: C.black, marginBottom: 12 }}>Оцените водителя</div>
        <Stars rating={rating} size={36} interactive onChange={setRating} />
        <div style={{ fontSize: 13, color: C.gray500, marginTop: 8 }}>Михаил Соколов</div>
      </div>
      <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 10, marginTop: 'auto' }}>
        <Btn variant="green" style={{ width: '100%' }} onPress={onReset}>Оставить отзыв</Btn>
        <Btn variant="ghost" style={{ width: '100%' }} onPress={onReset}>Заказать ещё раз</Btn>
      </div>
    </div>
  );
};

Object.assign(window, {
  ClientBottomNav, ClientIdle, ClientSelecting, ClientOrderForm,
  ClientSearching, ClientDriverAssigned, ClientEvacuating, ClientCompleted
});
