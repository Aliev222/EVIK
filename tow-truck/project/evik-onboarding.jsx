// EVIK Onboarding Screens

// 1.1 Splash Screen
const SplashScreen = ({ onDone }) => {
  React.useEffect(() => {
    const t = setTimeout(onDone, 2200);
    return () => clearTimeout(t);
  }, []);
  return (
    <div style={{ flex: 1, background: C.black, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 20 }}>
      <div style={{ animation: 'fadeInUp 0.8s ease forwards', opacity: 0 }}>
        {/* Logo */}
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
          <div style={{ width: 80, height: 80, borderRadius: 24, background: C.orange, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: `0 0 40px ${C.orange}55` }}>
            <Icon name="truck" size={42} color="#fff" />
          </div>
          <div style={{ fontSize: 42, fontWeight: 800, color: '#fff', letterSpacing: '-0.02em', fontFamily: 'Manrope, sans-serif' }}>
            EVIK
          </div>
          <div style={{ fontSize: 14, color: C.gray500, fontWeight: 500, letterSpacing: '0.12em', textTransform: 'uppercase', fontFamily: 'Manrope, sans-serif' }}>
            Сервис эвакуаторов
          </div>
        </div>
      </div>
      <div style={{ position: 'absolute', bottom: 60, display: 'flex', gap: 6 }}>
        {[0,1,2].map(i => (
          <div key={i} style={{ width: 6, height: 6, borderRadius: 3, background: i === 0 ? C.orange : C.gray500, animation: `dotPulse 1.2s ease ${i * 0.2}s infinite` }} />
        ))}
      </div>
    </div>
  );
};

// 1.2 Role Selection
const RoleScreen = ({ onSelect }) => {
  const [selected, setSelected] = React.useState(null);
  return (
    <div style={{ flex: 1, background: C.white, display: 'flex', flexDirection: 'column', padding: '40px 24px 40px' }}>
      <div style={{ marginTop: 20, marginBottom: 40 }}>
        <div style={{ fontSize: 28, fontWeight: 800, color: C.black, lineHeight: 1.2, fontFamily: 'Manrope, sans-serif' }}>Добро пожаловать<br />в <span style={{ color: C.orange }}>EVIK</span></div>
        <div style={{ fontSize: 15, color: C.gray500, marginTop: 10, fontWeight: 500 }}>Выберите, как вы хотите использовать приложение</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 16, flex: 1 }}>
        {[
          { id: 'client', emoji: '🚗', title: 'Я клиент', sub: 'Вызвать эвакуатор для своего автомобиля', icon: 'car' },
          { id: 'driver', emoji: '🚛', title: 'Я водитель', sub: 'Принимать заказы на эвакуацию и зарабатывать', icon: 'truck' },
        ].map(r => (
          <div key={r.id} onClick={() => setSelected(r.id)}
            style={{ border: `2.5px solid ${selected === r.id ? C.orange : C.gray200}`, borderRadius: 20, padding: '22px 20px', cursor: 'pointer', background: selected === r.id ? C.orange + '08' : C.white, transition: 'all 0.2s', display: 'flex', alignItems: 'center', gap: 18 }}>
            <div style={{ width: 60, height: 60, borderRadius: 18, background: selected === r.id ? C.orange + '18' : C.gray100, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 28 }}>
              {r.emoji}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 17, fontWeight: 700, color: C.black, marginBottom: 4 }}>{r.title}</div>
              <div style={{ fontSize: 13, color: C.gray500, lineHeight: 1.4 }}>{r.sub}</div>
            </div>
            <div style={{ width: 24, height: 24, borderRadius: '50%', border: `2px solid ${selected === r.id ? C.orange : C.gray200}`, background: selected === r.id ? C.orange : 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {selected === r.id && <Icon name="check" size={13} color="#fff" />}
            </div>
          </div>
        ))}
      </div>
      <div style={{ paddingBottom: 16 }}>
        <Btn style={{ width: '100%' }} disabled={!selected} onPress={() => selected && onSelect(selected)}>
          Продолжить
        </Btn>
        <div style={{ textAlign: 'center', fontSize: 12, color: C.gray500, marginTop: 16, lineHeight: 1.5 }}>
          Продолжая, вы соглашаетесь с <span style={{ color: C.orange, fontWeight: 600 }}>Условиями использования</span><br />и <span style={{ color: C.orange, fontWeight: 600 }}>Политикой конфиденциальности</span>
        </div>
      </div>
    </div>
  );
};

// 1.3 Phone Auth
const PhoneScreen = ({ onNext }) => {
  const [phone, setPhone] = React.useState('');
  const formatPhone = (v) => {
    const digits = v.replace(/\D/g, '').slice(0, 11);
    if (digits.length === 0) return '';
    let r = '+7';
    if (digits.length > 1) r += ' (' + digits.slice(1, 4);
    if (digits.length > 4) r += ') ' + digits.slice(4, 7);
    if (digits.length > 7) r += '-' + digits.slice(7, 9);
    if (digits.length > 9) r += '-' + digits.slice(9, 11);
    return r;
  };
  const digits = phone.replace(/\D/g, '');
  return (
    <div style={{ flex: 1, background: C.white, display: 'flex', flexDirection: 'column', padding: '40px 24px 40px' }}>
      <div style={{ marginTop: 20, marginBottom: 40 }}>
        <div style={{ fontSize: 26, fontWeight: 800, color: C.black, lineHeight: 1.2, fontFamily: 'Manrope, sans-serif' }}>Вход<br />в приложение</div>
        <div style={{ fontSize: 15, color: C.gray500, marginTop: 10 }}>Введите номер телефона для входа или регистрации</div>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, background: C.gray50, borderRadius: 14, padding: '0 16px', border: `2px solid ${digits.length >= 11 ? C.orange : C.gray200}`, transition: 'border-color 0.2s', marginBottom: 16 }}>
        <span style={{ fontSize: 24 }}>🇷🇺</span>
        <input value={phone} onChange={e => setPhone(formatPhone(e.target.value))}
          placeholder="+7 (999) 000-00-00" style={{ flex: 1, border: 'none', background: 'transparent', fontSize: 18, fontWeight: 600, fontFamily: 'Manrope, sans-serif', padding: '18px 0', outline: 'none', color: C.black, letterSpacing: '0.04em' }} />
      </div>
      <div style={{ fontSize: 13, color: C.gray500, marginBottom: 'auto', lineHeight: 1.5 }}>
        Мы отправим SMS с кодом подтверждения на этот номер
      </div>
      <div style={{ paddingBottom: 16 }}>
        <Btn style={{ width: '100%' }} disabled={digits.length < 11} onPress={onNext}>
          Получить код
        </Btn>
        <div style={{ textAlign: 'center', fontSize: 12, color: C.gray500, marginTop: 14, lineHeight: 1.5 }}>
          Нажимая кнопку, вы соглашаетесь с <span style={{ color: C.orange, fontWeight: 600 }}>Политикой конфиденциальности</span>
        </div>
      </div>
    </div>
  );
};

// 1.4 SMS Verification
const SmsScreen = ({ onNext }) => {
  const [code, setCode] = React.useState(['', '', '', '', '', '']);
  const [timer, setTimer] = React.useState(75);
  const refs = Array(6).fill(null).map(() => React.useRef(null));
  React.useEffect(() => {
    const t = setInterval(() => setTimer(prev => Math.max(0, prev - 1)), 1000);
    return () => clearInterval(t);
  }, []);
  const filled = code.every(c => c !== '');
  const handleChange = (i, v) => {
    const d = v.replace(/\D/g, '');
    if (!d) return;
    const nc = [...code]; nc[i] = d[0];
    setCode(nc);
    if (i < 5) refs[i+1].current && refs[i+1].current.focus();
    if (nc.every(c => c !== '')) onNext();
  };
  const handleKey = (i, e) => {
    if (e.key === 'Backspace' && !code[i] && i > 0) {
      const nc = [...code]; nc[i-1] = '';
      setCode(nc);
      refs[i-1].current && refs[i-1].current.focus();
    }
  };
  const mins = String(Math.floor(timer / 60)).padStart(2, '0');
  const secs = String(timer % 60).padStart(2, '0');
  return (
    <div style={{ flex: 1, background: C.white, display: 'flex', flexDirection: 'column', padding: '40px 24px 40px' }}>
      <div style={{ marginTop: 20, marginBottom: 36 }}>
        <div style={{ fontSize: 26, fontWeight: 800, color: C.black, lineHeight: 1.2, fontFamily: 'Manrope, sans-serif' }}>Введите код<br />из SMS</div>
        <div style={{ fontSize: 15, color: C.gray500, marginTop: 10 }}>Отправлен на номер +7 (999) 000-00-00</div>
      </div>
      <div style={{ display: 'flex', gap: 10, justifyContent: 'center', marginBottom: 32 }}>
        {code.map((c, i) => (
          <input key={i} ref={refs[i]} value={c} maxLength={1} inputMode="numeric"
            onChange={e => handleChange(i, e.target.value)}
            onKeyDown={e => handleKey(i, e)}
            style={{ width: 46, height: 54, textAlign: 'center', fontSize: 22, fontWeight: 700, border: `2.5px solid ${c ? C.orange : C.gray200}`, borderRadius: 12, background: c ? C.orange + '10' : C.gray50, fontFamily: 'Manrope, sans-serif', color: C.black, outline: 'none', transition: 'all 0.15s' }} />
        ))}
      </div>
      <div style={{ textAlign: 'center', marginBottom: 'auto' }}>
        {timer > 0 ? (
          <span style={{ fontSize: 14, color: C.gray500 }}>Повторить через <span style={{ fontWeight: 700, color: C.black }}>{mins}:{secs}</span></span>
        ) : (
          <span onClick={() => setTimer(75)} style={{ fontSize: 14, color: C.orange, fontWeight: 700, cursor: 'pointer' }}>Отправить повторно</span>
        )}
      </div>
      <div style={{ paddingBottom: 16 }}>
        <Btn style={{ width: '100%' }} disabled={!filled} onPress={onNext}>Войти</Btn>
      </div>
    </div>
  );
};

// 2.1 Document Upload
const DocUploadScreen = ({ onNext }) => {
  const [uploads, setUploads] = React.useState({});
  const docs = [
    { id: 'passport', label: 'Паспорт', sub: 'Разворот с фото', emoji: '🪪' },
    { id: 'license', label: 'Водительское удостоверение', sub: 'Обе стороны', emoji: '📋' },
    { id: 'pts', label: 'ПТС / СТС автомобиля', sub: 'Свидетельство о регистрации', emoji: '🚛' },
    { id: 'truck_photo', label: 'Фото эвакуатора', sub: 'Вид спереди и сбоку', emoji: '📷' },
    { id: 'selfie', label: 'Селфи с документами', sub: 'Лицо и паспорт в руках', emoji: '🤳' },
  ];
  const allUploaded = docs.every(d => uploads[d.id]);
  return (
    <div style={{ flex: 1, background: C.white, display: 'flex', flexDirection: 'column' }}>
      {/* Progress */}
      <div style={{ padding: '20px 24px 0' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <span style={{ fontSize: 12, fontWeight: 600, color: C.gray500 }}>Шаг 1 из 3</span>
          <span style={{ fontSize: 12, fontWeight: 700, color: C.orange }}>33%</span>
        </div>
        <div style={{ height: 4, background: C.gray100, borderRadius: 2 }}>
          <div style={{ width: '33%', height: '100%', background: C.orange, borderRadius: 2, transition: 'width 0.4s' }} />
        </div>
        <div style={{ fontSize: 22, fontWeight: 800, color: C.black, marginTop: 24, fontFamily: 'Manrope, sans-serif' }}>Загрузите документы</div>
        <div style={{ fontSize: 14, color: C.gray500, marginTop: 6 }}>Документы необходимы для верификации аккаунта</div>
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '20px 24px' }}>
        {docs.map(d => (
          <div key={d.id} onClick={() => setUploads(u => ({ ...u, [d.id]: !u[d.id] }))}
            style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 16px', borderRadius: 14, border: `1.5px solid ${uploads[d.id] ? C.green : C.gray200}`, background: uploads[d.id] ? C.green + '08' : C.white, marginBottom: 10, cursor: 'pointer', transition: 'all 0.2s' }}>
            <div style={{ width: 44, height: 44, borderRadius: 12, background: uploads[d.id] ? C.green + '18' : C.gray100, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20 }}>
              {uploads[d.id] ? <Icon name="check" size={20} color={C.green} /> : d.emoji}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 14, fontWeight: 700, color: C.black }}>{d.label}</div>
              <div style={{ fontSize: 12, color: C.gray500, marginTop: 2 }}>{d.sub}</div>
            </div>
            {uploads[d.id]
              ? <StatusPill label="Загружено" color={C.green} />
              : <div style={{ fontSize: 12, fontWeight: 600, color: C.orange, padding: '6px 12px', border: `1.5px solid ${C.orange}`, borderRadius: 8 }}>Загрузить</div>
            }
          </div>
        ))}
      </div>
      <div style={{ padding: '0 24px 24px' }}>
        <Btn style={{ width: '100%' }} disabled={!allUploaded} onPress={onNext}>Продолжить</Btn>
      </div>
    </div>
  );
};

// 2.2 Driver Profile
const DriverProfileScreen = ({ onNext }) => {
  const [form, setForm] = React.useState({ name: '', truck: '', plate: '', type: '' });
  const valid = Object.values(form).every(v => v.length > 0);
  return (
    <div style={{ flex: 1, background: C.white, display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '20px 24px 0' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <span style={{ fontSize: 12, fontWeight: 600, color: C.gray500 }}>Шаг 2 из 3</span>
          <span style={{ fontSize: 12, fontWeight: 700, color: C.orange }}>66%</span>
        </div>
        <div style={{ height: 4, background: C.gray100, borderRadius: 2 }}>
          <div style={{ width: '66%', height: '100%', background: C.orange, borderRadius: 2 }} />
        </div>
        <div style={{ fontSize: 22, fontWeight: 800, color: C.black, marginTop: 24 }}>Заполните профиль</div>
        <div style={{ fontSize: 14, color: C.gray500, marginTop: 6 }}>Информация о вас и вашем транспорте</div>
      </div>
      <div style={{ flex: 1, overflow: 'auto', padding: '24px 24px' }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
          <Field label="Полное имя" value={form.name} onChange={v => setForm(f => ({ ...f, name: v }))} placeholder="Иванов Иван Иванович" icon="user" />
          <Field label="Марка эвакуатора" value={form.truck} onChange={v => setForm(f => ({ ...f, truck: v }))} placeholder="КАМАЗ, ГАЗель..." icon="truck" />
          <Field label="Гос. номер" value={form.plate} onChange={v => setForm(f => ({ ...f, plate: v }))} placeholder="А 123 ВС 77" />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            <span style={{ fontSize: 12, fontWeight: 600, color: C.gray500, letterSpacing: '0.04em', textTransform: 'uppercase' }}>Тип эвакуатора</span>
            <div style={{ display: 'flex', gap: 10 }}>
              {['Частичная погрузка', 'Полная погрузка'].map(t => (
                <div key={t} onClick={() => setForm(f => ({ ...f, type: t }))}
                  style={{ flex: 1, padding: '12px 10px', borderRadius: 12, border: `2px solid ${form.type === t ? C.orange : C.gray200}`, background: form.type === t ? C.orange + '10' : C.white, cursor: 'pointer', textAlign: 'center', fontSize: 13, fontWeight: 600, color: form.type === t ? C.orange : C.gray800, transition: 'all 0.15s' }}>
                  {t}
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
      <div style={{ padding: '0 24px 24px' }}>
        <Btn style={{ width: '100%' }} disabled={!valid} onPress={onNext}>Отправить на модерацию</Btn>
      </div>
    </div>
  );
};

// 2.3 Moderation
const ModerationScreen = ({ status = 'pending', onApproved }) => {
  const states = {
    pending: { icon: '⏳', title: 'Документы на проверке', sub: 'Проверка занимает до 24 часов. Мы уведомим вас о результате по SMS.', color: C.amber, pill: 'Ожидание' },
    rejected: { icon: '❌', title: 'Документы отклонены', sub: 'Причина: фото паспорта нечёткое. Исправьте замечания и подайте документы заново.', color: C.red, pill: 'Отклонено' },
    approved: { icon: '✅', title: 'Добро пожаловать в EVIK!', sub: 'Ваши документы проверены. Теперь вы можете принимать заказы и зарабатывать.', color: C.green, pill: 'Одобрено' },
  };
  const s = states[status];
  return (
    <div style={{ flex: 1, background: C.white, display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '20px 24px 0' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <span style={{ fontSize: 12, fontWeight: 600, color: C.gray500 }}>Шаг 3 из 3</span>
          <span style={{ fontSize: 12, fontWeight: 700, color: C.orange }}>100%</span>
        </div>
        <div style={{ height: 4, background: C.gray100, borderRadius: 2 }}>
          <div style={{ width: '100%', height: '100%', background: status === 'rejected' ? C.red : C.orange, borderRadius: 2 }} />
        </div>
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '0 32px', textAlign: 'center', gap: 20 }}>
        <div style={{ fontSize: 64, lineHeight: 1 }}>{s.icon}</div>
        <StatusPill label={s.pill} color={s.color} />
        <div style={{ fontSize: 22, fontWeight: 800, color: C.black, lineHeight: 1.3, fontFamily: 'Manrope, sans-serif' }}>{s.title}</div>
        <div style={{ fontSize: 15, color: C.gray500, lineHeight: 1.6 }}>{s.sub}</div>
        {status === 'pending' && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '12px 20px', background: C.amber + '12', borderRadius: 12 }}>
            <Icon name="time" size={16} color={C.amber} />
            <span style={{ fontSize: 14, fontWeight: 600, color: C.amber }}>Ожидание: 4 часа 23 минуты</span>
          </div>
        )}
      </div>
      <div style={{ padding: '0 24px 32px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        {status === 'approved' && <Btn style={{ width: '100%' }} variant="green" onPress={onApproved}>Начать работу</Btn>}
        {status === 'rejected' && <><Btn style={{ width: '100%' }} onPress={() => {}}>Исправить документы</Btn><Btn style={{ width: '100%' }} variant="ghost" onPress={() => {}}>Обратиться в поддержку</Btn></>}
        {status === 'pending' && <Btn style={{ width: '100%' }} variant="ghost" onPress={() => {}}>Обратиться в поддержку</Btn>}
      </div>
    </div>
  );
};

Object.assign(window, {
  SplashScreen, RoleScreen, PhoneScreen, SmsScreen,
  DocUploadScreen, DriverProfileScreen, ModerationScreen
});
