import { test, assert, F } from './harness.mjs';

/* ============ THEMES ============ */
test('THEMES: exactly 6 themes with valid ids', () => {
  assert.equal(F.THEMES.length, 6);
  const ids = F.THEMES.map(t => t.id).join(',');
  assert.equal(ids, 'aurora,midnight,emerald,sunset,ocean,light');
  for (const t of F.THEMES) {
    assert.ok(t.label && t.swatch, 'each theme has label+swatch: ' + t.id);
  }
});

test('applyTheme: sets data-theme on documentElement and persists', () => {
  F.applyTheme('ocean');
  assert.equal(F.document.documentElement.getAttribute('data-theme'), 'ocean');
  assert.equal(F.localStorage.getItem('admin_theme'), 'ocean');
});

test('applyTheme: unknown id falls back to aurora', () => {
  F.applyTheme('nope');
  assert.equal(F.document.documentElement.getAttribute('data-theme'), 'aurora');
});

test('toggleTheme: cycles through all 6 themes without repeats', () => {
  const seen = [];
  for (let i = 0; i < 6; i++) {
    F.toggleTheme();
    seen.push(F.document.documentElement.getAttribute('data-theme'));
  }
  assert.equal(new Set(seen).size, 6);
  assert.equal(seen[0], 'midnight'); // aurora -> midnight first
});


/* ============ escapeHtml ============ */
test('escapeHtml: null/undefined -> empty', () => {
  assert.equal(F.escapeHtml(null), '');
  assert.equal(F.escapeHtml(undefined), '');
});
test('escapeHtml: escapes 5 dangerous chars', () => {
  assert.equal(F.escapeHtml(`<a href="x">&'`), '&lt;a href=&quot;x&quot;&gt;&amp;&#39;');
});
test('escapeHtml: plain text passes through', () => {
  assert.equal(F.escapeHtml('Привет 123'), 'Привет 123');
});

/* ============ formatMoneyMinor (kopecks -> ₽) ============ */
test('formatMoneyMinor: null/undefined -> dash', () => {
  assert.equal(F.formatMoneyMinor(null), '—');
  assert.equal(F.formatMoneyMinor(undefined), '—');
  assert.equal(F.formatMoneyMinor(''), '—');
});
test('formatMoneyMinor: NaN -> original string', () => {
  assert.equal(F.formatMoneyMinor('abc'), 'abc');
});
test('formatMoneyMinor: 0 kopecks -> 0,00 ₽', () => {
  assert.equal(F.formatMoneyMinor(0), '0,00 ₽');
});
test('formatMoneyMinor: 100 kopecks -> 1,00 ₽', () => {
  assert.equal(F.formatMoneyMinor(100), '1,00 ₽');
});
test('formatMoneyMinor: 12345 kopecks -> 123,45 ₽', () => {
  assert.equal(F.formatMoneyMinor(12345), '123,45 ₽');
});
test('formatMoneyMinor: custom currency', () => {
  assert.equal(F.formatMoneyMinor(5000, '$'), '50,00 $');
});

/* ============ formatBigInt ============ */
test('formatBigInt: non-finite -> 0', () => {
  assert.equal(F.formatBigInt('x'), '0');
  assert.equal(F.formatBigInt(NaN), '0');
});
test('formatBigInt: thousands separator', () => {
  // ru-RU groups with a non-breaking space; strip separators before compare.
  assert.equal(F.formatBigInt(1234567).replace(/\D/g, ''), '1234567');
});

/* ============ formatDate / formatDateOnly ============ */
test('formatDate: empty -> dash', () => {
  assert.equal(F.formatDate(''), '—');
  assert.equal(F.formatDate(null), '—');
});
test('formatDate: invalid -> original', () => {
  assert.equal(F.formatDate('not-a-date'), 'not-a-date');
});
test('formatDate: valid ISO', () => {
  const out = F.formatDate('2024-01-15T10:30:00Z');
  assert.match(out, /2024/);
});
test('formatDateOnly: valid ISO contains day/month', () => {
  const out = F.formatDateOnly('2024-01-15T10:30:00Z');
  assert.match(out, /15/);
});

/* ============ formatResponseTime ============ */
test('formatResponseTime: 0/empty -> dash', () => {
  assert.equal(F.formatResponseTime(0), '—');
  assert.equal(F.formatResponseTime(null), '—');
});
test('formatResponseTime: <60s', () => {
  assert.equal(F.formatResponseTime(42), '42 сек');
});
test('formatResponseTime: minutes+seconds', () => {
  assert.equal(F.formatResponseTime(125), '2 мин 5 сек');
});

/* ============ statusBadge ============ */
test('statusBadge: empty -> muted dash', () => {
  assert.equal(F.statusBadge(''), '<span class="badge badge-muted">—</span>');
});
test('statusBadge: known map', () => {
  assert.equal(F.statusBadge('active', { active: 'badge-success' }),
    '<span class="badge badge-success">active</span>');
});
test('statusBadge: unknown -> muted', () => {
  assert.equal(F.statusBadge('zzz'), '<span class="badge badge-muted">zzz</span>');
});

/* ============ orderStatusBadge ============ */
test('orderStatusBadge: completed -> success + label', () => {
  assert.equal(F.orderStatusBadge('completed'),
    '<span class="badge badge-success">Завершён</span>');
});
test('orderStatusBadge: no_driver_found -> muted', () => {
  assert.match(F.orderStatusBadge('no_driver_found'), /badge-muted/);
});
test('orderStatusBadge: null -> dash', () => {
  assert.match(F.orderStatusBadge(null), /—/);
});

/* ============ paymentMethodBadge ============ */
test('paymentMethodBadge: cash -> warning', () => {
  assert.match(F.paymentMethodBadge('cash'), /badge-warning/);
});
test('paymentMethodBadge: card -> info', () => {
  assert.match(F.paymentMethodBadge('card'), /badge-info/);
});
test('paymentMethodBadge: null -> dash', () => {
  assert.equal(F.paymentMethodBadge(null), '—');
});

/* ============ paymentStatusBadge ============ */
test('paymentStatusBadge: paid -> success', () => {
  assert.match(F.paymentStatusBadge('paid'), /badge-success/);
});
test('paymentStatusBadge: failed -> danger', () => {
  assert.match(F.paymentStatusBadge('failed'), /badge-danger/);
});

/* ============ finStatusBadge ============ */
test('finStatusBadge: settled -> success', () => {
  assert.match(F.finStatusBadge('settled'), /badge-success/);
});

/* ============ driverStatusBadge ============ */
test('driverStatusBadge: online -> success', () => {
  assert.match(F.driverStatusBadge('online'), /badge-success/);
});
test('driverStatusBadge: blocked -> danger', () => {
  assert.match(F.driverStatusBadge('blocked'), /badge-danger/);
});
test('driverStatusBadge: case-insensitive', () => {
  assert.match(F.driverStatusBadge('ONLINE'), /badge-success/);
});

/* ============ documentsBadge / taxBadge ============ */
test('documentsBadge: approved -> success', () => {
  assert.match(F.documentsBadge('approved'), /badge-success/);
});
test('taxBadge: verified -> success', () => {
  assert.match(F.taxBadge('verified'), /badge-success/);
});

/* ============ buildQuery ============ */
test('buildQuery: empty -> empty string', () => {
  assert.equal(F.buildQuery({}), '');
});
test('buildQuery: skips null/undefined/empty', () => {
  assert.equal(F.buildQuery({ a: 1, b: null, c: '', d: undefined }), '?a=1');
});
test('buildQuery: encodes values', () => {
  assert.equal(F.buildQuery({ q: 'a b' }), '?q=a+b');
});

/* ============ shortId ============ */
test('shortId: empty -> dash', () => {
  assert.equal(F.shortId(''), '—');
  assert.equal(F.shortId(null), '—');
});
test('shortId: slices 8 chars', () => {
  assert.equal(F.shortId('abcdef1234567890'), 'abcdef12');
});

/* ============ niceNum ============ */
test('niceNum: <=0 -> 0', () => {
  assert.equal(F.niceNum(0), 0);
  assert.equal(F.niceNum(-5), 0);
});
test('niceNum: 12345 -> 20000', () => {
  assert.equal(F.niceNum(12345), 20000);
});
test('niceNum: 5 -> 5', () => {
  assert.equal(F.niceNum(5), 5);
});

/* ============ formatCompactMoney ============ */
test('formatCompactMoney: 0 -> 0 ₽', () => {
  assert.equal(F.formatCompactMoney(0), '0 ₽');
});
test('formatCompactMoney: thousands -> K', () => {
  assert.equal(F.formatCompactMoney(1500000), '15.0K ₽');
});
test('formatCompactMoney: millions -> M', () => {
  assert.equal(F.formatCompactMoney(25000000000), '250.0M ₽');
});

/* ============ filterSeriesByPeriod ============ */
test('filterSeriesByPeriod: >=30 returns all', () => {
  const s = [{ a: 1 }, { a: 2 }, { a: 3 }];
  assert.equal(F.filterSeriesByPeriod(s, 30).length, 3);
});
test('filterSeriesByPeriod: 7 slices last 7', () => {
  const s = Array.from({ length: 30 }, (_, i) => ({ a: i }));
  assert.equal(F.filterSeriesByPeriod(s, 7).length, 7);
});
test('filterSeriesByPeriod: empty -> empty', () => {
  assert.deepEqual(F.filterSeriesByPeriod([], 7), []);
});

/* ============ isActiveStatus ============ */
test('isActiveStatus: searching true', () => {
  assert.equal(F.isActiveStatus('searching'), true);
});
test('isActiveStatus: completed false', () => {
  assert.equal(F.isActiveStatus('completed'), false);
});

/* ============ isOnlineStatus / isBusyStatus / isBlockedStatus ============ */
test('isOnlineStatus: free/available/online', () => {
  assert.equal(F.isOnlineStatus('free'), true);
  assert.equal(F.isOnlineStatus('available'), true);
  assert.equal(F.isOnlineStatus('busy'), false);
});
test('isBusyStatus: busy/on_order', () => {
  assert.equal(F.isBusyStatus('busy'), true);
  assert.equal(F.isBusyStatus('on_order'), true);
  assert.equal(F.isBusyStatus('offline'), false);
});
test('isBlockedStatus: blocked only', () => {
  assert.equal(F.isBlockedStatus('blocked'), true);
  assert.equal(F.isBlockedStatus('online'), false);
});

/* ============ isStale ============ */
test('isStale: missing -> true', () => {
  assert.equal(F.isStale(''), true);
  assert.equal(F.isStale(null), true);
});
test('isStale: fresh -> false', () => {
  const iso = new Date(Date.now() - 10000).toISOString();
  assert.equal(F.isStale(iso), false);
});
test('isStale: old (>2min) -> true', () => {
  const iso = new Date(Date.now() - 3 * 60 * 1000).toISOString();
  assert.equal(F.isStale(iso), true);
});

/* ============ timeAgo ============ */
test('timeAgo: missing -> dash', () => {
  assert.equal(F.timeAgo(''), '—');
});
test('timeAgo: 30s -> "сек назад"', () => {
  assert.match(F.timeAgo(new Date(Date.now() - 30000).toISOString()), /сек назад/);
});
test('timeAgo: 2h -> "ч назад"', () => {
  assert.match(F.timeAgo(new Date(Date.now() - 2 * 3600000).toISOString()), /ч назад/);
});

/* ============ ordersKpiAggregate ============ */
test('ordersKpiAggregate: sums correctly', () => {
  const items = [
    { status: 'completed', price_total: 1000, commission_amount: 100, driver_amount: 900 },
    { status: 'cancelled', price_total: 0, commission_amount: 0, driver_amount: 0 },
    { status: 'searching', price_total: 500, commission_amount: 50, driver_amount: 450 },
  ];
  const a = F.ordersKpiAggregate(items);
  assert.equal(a.total, 3);
  assert.equal(a.completed, 1);
  assert.equal(a.cancelled, 1);
  assert.equal(a.active, 1);
  assert.equal(a.gmv, 1500);
  assert.equal(a.commission, 150);
  assert.equal(a.payout, 1350);
});

/* ============ effectiveDriverStatus ============ */
test('effectiveDriverStatus: stale online -> stale', () => {
  const rec = { online: { last_seen: new Date(Date.now() - 10 * 60000).toISOString() } };
  assert.equal(F.effectiveDriverStatus(rec), 'stale');
});
test('effectiveDriverStatus: fresh online -> online', () => {
  const rec = { online: { last_seen: new Date().toISOString() } };
  assert.equal(F.effectiveDriverStatus(rec), 'online');
});
test('effectiveDriverStatus: blocked user -> blocked', () => {
  const rec = { user_status: 'blocked' };
  assert.equal(F.effectiveDriverStatus(rec), 'blocked');
});
test('effectiveDriverStatus: nothing -> offline', () => {
  assert.equal(F.effectiveDriverStatus({}), 'offline');
});

/* ============ aggregateDriversKpi ============ */
test('aggregateDriversKpi: counts by status', () => {
  const records = [
    { online: { last_seen: new Date().toISOString() }, verification: { status: 'pending', stars: 5 } },
    { online: { last_seen: new Date(Date.now() - 10 * 60000).toISOString() } },
    { user_status: 'blocked' },
    { verification: { status: 'approved' }, tax: { verification_status: 'pending' } },
  ];
  const a = F.aggregateDriversKpi(records);
  assert.equal(a.total, 4);
  assert.equal(a.online, 1);
  assert.equal(a.blocked, 1);
  assert.equal(a.moderation, 1);
  assert.equal(a.taxPending, 1);
  assert.equal(a.ratingCount, 1);
  assert.equal(a.avgRating, 5);
});

/* ============ matchesDriverFilters ============ */
test('matchesDriverFilters: search across fields', () => {
  const rec = { full_name: 'Иван Петров', phone: '+7', verification: { plate: 'A123' } };
  assert.equal(F.matchesDriverFilters(rec, { search: 'иван' }), true);
  assert.equal(F.matchesDriverFilters(rec, { search: 'zzz' }), false);
});
test('matchesDriverFilters: status online', () => {
  const rec = { online: { last_seen: new Date().toISOString() } };
  assert.equal(F.matchesDriverFilters(rec, { status: 'online' }), true);
  assert.equal(F.matchesDriverFilters(rec, { status: 'offline' }), false);
});
test('matchesDriverFilters: onlineOnly', () => {
  const rec = { online: { last_seen: new Date().toISOString() } };
  assert.equal(F.matchesDriverFilters(rec, { onlineOnly: true }), true);
  const rec2 = {};
  assert.equal(F.matchesDriverFilters(rec2, { onlineOnly: true }), false);
});
test('matchesDriverFilters: ratingMin', () => {
  const rec = { verification: { stars: 4.5 } };
  assert.equal(F.matchesDriverFilters(rec, { ratingMin: 4 }), true);
  assert.equal(F.matchesDriverFilters(rec, { ratingMin: 5 }), false);
});

/* ============ mergeDriversData ============ */
test('mergeDriversData: seeds from users (driver role only)', () => {
  const src = { users: [{ id: 'u1', name: 'D', role: 'driver', phone: 'p1', orders: 3 }] };
  const out = F.mergeDriversData(src);
  assert.equal(out.length, 1);
  assert.equal(out[0].user_id, 'u1');
  assert.equal(out[0].orders_count, 3);
});
test('mergeDriversData: ignores non-driver users', () => {
  const src = { users: [{ id: 'u1', role: 'client' }, { id: 'u2', role: 'driver' }] };
  const out = F.mergeDriversData(src);
  assert.equal(out.length, 1);
  assert.equal(out[0].user_id, 'u2');
});
test('mergeDriversData: links verification by phone', () => {
  const src = {
    users: [{ id: 'u1', role: 'driver', phone: 'p1' }],
    verifications: [{ phone: 'p1', status: 'approved', driver_name: 'Vasya' }],
  };
  const out = F.mergeDriversData(src);
  assert.equal(out[0].verification.status, 'approved');
  assert.equal(out[0].full_name, 'Vasya');
});
test('mergeDriversData: links wallet by driver_id', () => {
  const src = {
    users: [{ id: 'u1', role: 'driver' }],
    online: [{ id: 'd1', name: 'u1' }],
    wallets: [{ driver_id: 'd1', available_balance: 500 }],
  };
  const out = F.mergeDriversData(src);
  assert.equal(out[0].wallet.available, 500);
});
test('mergeDriversData: tolerates all-empty sources', () => {
  const out = F.mergeDriversData({});
  assert.equal(out.length, 0);
});

/* ============ Settings helpers ============ */
test('rubDisplay: round kopecks', () => {
  assert.equal(F.rubDisplay(500), '5');
  assert.equal(F.rubDisplay(12345), '123.45');
});
test('rubDisplay: non-finite -> empty', () => {
  assert.equal(F.rubDisplay('x'), '');
});
test('rubToKopecks: rubles -> kopecks', () => {
  assert.equal(F.rubToKopecks('5'), 500);
});
test('validateRubles: rejects non-integer', () => {
  assert.match(F.validateRubles('5.5'), /целое/);
});
test('validateRubles: rejects zero/negative', () => {
  assert.match(F.validateRubles('0'), /больше 0/);
});
test('validateRubles: rejects too large', () => {
  assert.match(F.validateRubles('200000'), /100 000/);
});
test('validateRubles: valid -> null', () => {
  assert.equal(F.validateRubles('1000'), null);
});
test('parseSettingValue: numeric', () => {
  assert.equal(F.parseSettingValue('42'), 42);
});
test('parseSettingValue: boolean true', () => {
  assert.equal(F.parseSettingValue('true'), true);
});
test('parseSettingValue: boolean false', () => {
  assert.equal(F.parseSettingValue('false'), false);
});
test('parseSettingValue: string fallback', () => {
  assert.equal(F.parseSettingValue('hello'), 'hello');
});
test('formatSettingValue: null -> empty', () => {
  assert.equal(F.formatSettingValue(null), '');
});

/* ============ debounce ============ */
test('debounce: coalesces rapid calls', async () => {
  let calls = 0;
  const fn = F.debounce(() => { calls++; }, 20);
  fn(); fn(); fn();
  await new Promise((r) => setTimeout(r, 40));
  assert.equal(calls, 1);
});

/* ============ sleep ============ */
test('sleep: resolves after delay', async () => {
  const t0 = Date.now();
  await F.sleep(15);
  assert.ok(Date.now() - t0 >= 10);
});
