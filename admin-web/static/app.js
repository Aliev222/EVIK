/* ============================================================
 * Tow Truck Admin — app.js
 * Sections:
 *   1. State
 *   2. Utils
 *   3. API client
 *   4. Auth
 *   5. Router
 *   6. Components
 *   7. Pages (17)
 *   8. Bootstrap
 * ============================================================ */

'use strict';

/* ============================================================
 * 1. STATE
 * ============================================================ */
const state = {
  token: null,
  user: null,
  route: { name: 'dashboard', params: {} },
  backendOk: null,
  loading: false,
  // per-page slices
  data: {},
  filters: {},
};

const ROUTES = [
  { id: 'dashboard',     title: 'Дашборд',                 group: 'Операции' },
  { id: 'orders',        title: 'Заказы',                  group: 'Операции' },
  { id: 'drivers',       title: 'Водители',                group: 'Операции' },
  { id: 'documents',     title: 'Документы / Модерация',   group: 'Операции' },
  { id: 'tax-profiles',  title: 'Налоговые профили',       group: 'Операции' },
  { id: 'service-areas', title: 'Зоны работы',             group: 'Операции' },
  { id: 'payments',      title: 'Платежи',                 group: 'Финансы'  },
  { id: 'payouts',       title: 'Выплаты',                 group: 'Финансы'  },
  { id: 'wallets',       title: 'Кошельки',                group: 'Финансы'  },
  { id: 'transactions',  title: 'Транзакции',              group: 'Финансы'  },
  { id: 'subscriptions', title: 'Подписки',                group: 'Финансы'  },
  { id: 'refunds',       title: 'Возвраты',                group: 'Финансы'  },
  { id: 'reports',       title: 'Отчёты / Экспорт',        group: 'Финансы'  },
  { id: 'reviews',       title: 'Отзывы',                  group: 'Система'  },
  { id: 'users',         title: 'Пользователи',            group: 'Система'  },
  { id: 'online-map',    title: 'Online водители',         group: 'Система'  },
  { id: 'settings',      title: 'Настройки',               group: 'Система'  },
];

/* ============================================================
 * 2. UTILS
 * ============================================================ */
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

function escapeHtml(s) {
  if (s === null || s === undefined) return '';
  return String(s)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function formatMoneyMinor(amount, currency = '₽') {
  if (amount === null || amount === undefined || amount === '') return '—';
  const n = Number(amount);
  if (!Number.isFinite(n)) return String(amount);
  const rub = n / 100;
  return new Intl.NumberFormat('ru-RU', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
    .format(rub) + ' ' + currency;
}

function formatDate(s) {
  if (!s) return '—';
  const d = new Date(s);
  if (isNaN(d.getTime())) return String(s);
  return d.toLocaleString('ru-RU', { dateStyle: 'short', timeStyle: 'short' });
}

function formatDateOnly(s) {
  if (!s) return '—';
  const d = new Date(s);
  if (isNaN(d.getTime())) return String(s);
  return d.toLocaleDateString('ru-RU');
}

function statusBadge(value, map = {}) {
  if (!value) return `<span class="badge badge-muted">—</span>`;
  const cls = map[value] || 'badge-muted';
  return `<span class="badge ${cls}">${escapeHtml(value)}</span>`;
}

function buildQuery(params) {
  const usp = new URLSearchParams();
  for (const [k, v] of Object.entries(params || {})) {
    if (v === undefined || v === null || v === '') continue;
    usp.set(k, String(v));
  }
  const s = usp.toString();
  return s ? '?' + s : '';
}

function debounce(fn, wait = 300) {
  let t;
  return function (...args) {
    clearTimeout(t);
    t = setTimeout(() => fn.apply(this, args), wait);
  };
}

async function copyToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text);
    toast('Скопировано', 'success');
  } catch (_) {
    toast('Не удалось скопировать', 'error');
  }
}

function shortId(id) {
  if (!id) return '—';
  return String(id).slice(0, 8);
}

/* ============================================================
 * 3. API CLIENT
 * ============================================================ */
const api = {
  baseHeaders() {
    const h = { 'Content-Type': 'application/json' };
    if (state.token) h['Authorization'] = 'Bearer ' + state.token;
    return h;
  },
  async request(method, path, { body, query, raw } = {}) {
    const url = path + (query ? buildQuery(query) : '');
    let res;
    try {
      res = await fetch(url, {
        method,
        headers: this.baseHeaders(),
        body: body !== undefined ? JSON.stringify(body) : undefined,
      });
    } catch (e) {
      state.backendOk = false;
      renderBackendStatus();
      throw new Error('Ошибка сети: ' + e.message);
    }
    state.backendOk = true;
    renderBackendStatus();
    if (res.status === 401) {
      logout();
      throw new Error('Неавторизован - войдите снова');
    }
    if (raw) return res;
    let data = null;
    const text = await res.text();
    if (text) {
      try { data = JSON.parse(text); } catch (_) { data = { _raw: text }; }
    }
    if (!res.ok) {
      const msg = (data && (data.error || data.message)) || res.statusText || ('HTTP ' + res.status);
      const err = new Error(msg);
      err.status = res.status;
      err.body = data;
      throw err;
    }
    return data;
  },
  get(path, opts)    { return this.request('GET',    path, opts); },
  post(path, body, opts)  { return this.request('POST',   path, { ...(opts || {}), body }); },
  put(path, body, opts)   { return this.request('PUT',    path, { ...(opts || {}), body }); },
  del(path, opts)    { return this.request('DELETE', path, opts); },
};

/* ============================================================
 * 4. AUTH
 * ============================================================ */
function loadToken() {
  try { state.token = localStorage.getItem('admin_token') || null; } catch (_) {}
}
function saveToken(t) {
  state.token = t;
  try { if (t) localStorage.setItem('admin_token', t); else localStorage.removeItem('admin_token'); } catch (_) {}
}
function logout() {
  saveToken(null);
  state.user = null;
  renderApp();
}
async function login(username, password) {
  const data = await api.post('/api/v1/auth/admin/login', { username, password });
  const token = data.access_token || data.token || (data.tokens && data.tokens.access_token);
  if (!token) throw new Error('Сервер не вернул токен доступа');
  saveToken(token);
  state.user = data.user || { username };
}

/* ============================================================
 * 5. ROUTER
 * ============================================================ */
function parseHash() {
  const raw = (location.hash || '#/dashboard').replace(/^#\/?/, '');
  const [name, ...rest] = raw.split('/');
  const knownIds = ROUTES.map(r => r.id);
  if (!knownIds.includes(name)) return { name: 'dashboard', params: {} };
  const params = {};
  if (name === 'orders' && rest[0]) params.orderId = rest[0];
  return { name, params };
}
function navigate(hash) {
  if (location.hash === hash) {
    routeChanged();
  } else {
    location.hash = hash;
  }
}
function routeChanged() {
  state.route = parseHash();
  renderApp();
}

/* ============================================================
 * 6. COMPONENTS
 * ============================================================ */
function LoadingState(label = 'Загрузка...') {
  return `<div class="state"><div class="spinner"></div>${escapeHtml(label)}</div>`;
}
function EmptyState(label = 'Нет данных') {
  return `<div class="state">${escapeHtml(label)}</div>`;
}
function ErrorState(msg, retryFn) {
  const id = 'retry-' + Math.random().toString(36).slice(2, 8);
  setTimeout(() => {
    const el = document.getElementById(id);
    if (el && retryFn) el.onclick = retryFn;
  }, 0);
  return `<div class="state error"><strong>Ошибка:</strong> ${escapeHtml(msg)}<div style="margin-top:12px"><button id="${id}" class="btn btn-sm">Повторить попытку</button></div></div>`;
}
function MissingEndpointState(label = 'Серверный endpoint отсутствует') {
  return `<div class="state missing"><strong>${escapeHtml(label)}</strong><div style="margin-top:8px">Этот раздел будет доступен после реализации соответствующего API на сервере.</div></div>`;
}

function KpiCard(label, value, sub) {
  return `<div class="kpi">
    <div class="kpi-label">${escapeHtml(label)}</div>
    <div class="kpi-value">${value}</div>
    ${sub ? `<div class="kpi-sub">${escapeHtml(sub)}</div>` : ''}
  </div>`;
}

function Pagination(total, limit, offset, onChange) {
  if (!total || total <= limit) return '';
  const page = Math.floor(offset / limit) + 1;
  const totalPages = Math.ceil(total / limit);
  const id = 'pg-' + Math.random().toString(36).slice(2, 8);
  setTimeout(() => {
    const prev = document.getElementById(id + '-prev');
    const next = document.getElementById(id + '-next');
    if (prev) prev.onclick = () => { if (offset > 0) onChange(Math.max(0, offset - limit)); };
    if (next) next.onclick = () => { if (page < totalPages) onChange(offset + limit); };
  }, 0);
  return `<div class="pagination">
    <span>Всего: ${total} · Стр. ${page} из ${totalPages}</span>
    <div class="row" style="flex:0 0 auto">
      <button id="${id}-prev" class="btn btn-sm" ${page <= 1 ? 'disabled' : ''}>← Назад</button>
      <button id="${id}-next" class="btn btn-sm" ${page >= totalPages ? 'disabled' : ''}>Далее →</button>
    </div>
  </div>`;
}

function openDrawer(title, body, footer = '') {
  const root = $('#drawer-root');
  root.innerHTML = `
    <div class="drawer-backdrop" data-close></div>
    <div class="drawer">
      <div class="drawer-header">
        <div class="drawer-title">${title}</div>
        <button class="btn btn-ghost btn-sm" data-close>✕</button>
      </div>
      <div class="drawer-body">${body}</div>
      ${footer ? `<div class="drawer-footer">${footer}</div>` : ''}
    </div>`;
  $$('[data-close]', root).forEach(el => el.onclick = closeDrawer);
}
function closeDrawer() { $('#drawer-root').innerHTML = ''; }

function openModal(title, body, footerButtons) {
  const root = $('#modal-root');
  const id = 'm-' + Math.random().toString(36).slice(2, 8);
  const btns = (footerButtons || []).map((b, i) => `<button class="btn ${b.cls || ''}" id="${id}-b${i}">${escapeHtml(b.label)}</button>`).join('');
  root.innerHTML = `
    <div class="modal-backdrop">
      <div class="modal">
        <div class="modal-header">${title}</div>
        <div class="modal-body" id="${id}-body">${body}</div>
        <div class="modal-footer">${btns}</div>
      </div>
    </div>`;
  (footerButtons || []).forEach((b, i) => {
    const el = document.getElementById(id + '-b' + i);
    if (el) el.onclick = () => b.onClick({ getInput: (name) => { const x = document.querySelector(`#${id}-body [name="${name}"]`); return x ? x.value : ''; }, close: closeModal });
  });
}
function closeModal() { $('#modal-root').innerHTML = ''; }

function confirmDialog(message, onConfirm) {
  openModal('Подтверждение', `<p>${escapeHtml(message)}</p>`, [
    { label: 'Отмена', onClick: ({ close }) => close() },
    { label: 'Подтвердить', cls: 'btn-primary', onClick: ({ close }) => { close(); onConfirm(); } },
  ]);
}

function toast(message, kind = 'info') {
  const root = $('#toast-root');
  const el = document.createElement('div');
  el.className = 'toast ' + (kind || '');
  el.textContent = message;
  root.appendChild(el);
  setTimeout(() => { el.remove(); }, 4000);
}

/* ============================================================
 * 7. PAGES
 * ============================================================ */

/* ---------- 7.1 Dashboard ---------- */
async function pageDashboard(main) {
  main.innerHTML = LoadingState('Загрузка дашборда...');
  try {
    const o = await api.get('/api/v1/admin/overview');
    main.innerHTML = `
      <div class="kpi-grid">
        ${KpiCard('GMV сегодня',     formatMoneyMinor(o.gmv_today))}
        ${KpiCard('GMV месяц',       formatMoneyMinor(o.gmv_month))}
        ${KpiCard('Комиссия сегодня',formatMoneyMinor(o.commission_today))}
        ${KpiCard('Комиссия месяц',  formatMoneyMinor(o.commission_month))}
        ${KpiCard('Выплаты сегодня', formatMoneyMinor(o.payouts_today))}
        ${KpiCard('Выплаты месяц',   formatMoneyMinor(o.payouts_month))}
        ${KpiCard('Ожидают выплаты', formatMoneyMinor(o.payouts_pending))}
        ${KpiCard('Failed payments', String(o.failed_payments ?? 0))}
        ${KpiCard('Failed payouts',  String(o.failed_payouts ?? 0))}
        ${KpiCard('Доход подписок (день)', formatMoneyMinor(o.subscriptions_revenue_today))}
        ${KpiCard('Расчёты с Tow Truck',   formatMoneyMinor(o.cash_debt_total))}
        ${KpiCard('Online водители', String(o.online_drivers ?? 0))}
        ${KpiCard('На модерации',    String(o.pending_verifications ?? 0))}
        ${KpiCard('Активные заказы', String(o.active_orders ?? 0))}
      </div>
      <div class="row" style="align-items:stretch">
        <div class="card" style="flex:1 1 320px">
          <div class="card-header"><div class="card-title">GMV по дням</div></div>
          ${renderBarChart(o.gmv_by_day)}
        </div>
        <div class="card" style="flex:1 1 320px">
          <div class="card-header"><div class="card-title">Комиссия по дням</div></div>
          ${renderBarChart(o.commission_by_day)}
        </div>
      </div>
    `;
  } catch (e) {
    main.innerHTML = ErrorState(e.message, () => pageDashboard(main));
  }
}

function renderBarChart(series) {
  if (!Array.isArray(series) || series.length === 0) return EmptyState('Нет данных за период');
  const w = 600, h = 160, pad = 24;
  const max = Math.max(1, ...series.map(p => Number(p.amount) || 0));
  const bw = (w - pad * 2) / series.length - 2;
  let bars = '';
  series.forEach((p, i) => {
    const v = Number(p.amount) || 0;
    const bh = ((h - pad * 2) * v) / max;
    const x = pad + i * ((w - pad * 2) / series.length);
    const y = h - pad - bh;
    bars += `<rect class="chart-bar" x="${x}" y="${y}" width="${bw}" height="${bh}"><title>${escapeHtml(p.date)}: ${formatMoneyMinor(v)}</title></rect>`;
  });
  return `<svg class="chart" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
    <line class="chart-axis" x1="${pad}" y1="${h-pad}" x2="${w-pad}" y2="${h-pad}" />
    ${bars}
  </svg>`;
}

/* ---------- 7.2 Orders ---------- */
async function pageOrders(main) {
  const f = state.filters.orders || (state.filters.orders = { limit: 50, offset: 0 });
  main.innerHTML = `
    <div class="filter-bar">
      <div class="form-group"><label>Статус</label>
        <select name="status">
          <option value="">Все</option>
          <option value="pending">pending</option>
          <option value="assigned">assigned</option>
          <option value="en_route">en_route</option>
          <option value="arrived">arrived</option>
          <option value="loading">loading</option>
          <option value="completed">completed</option>
          <option value="cancelled">cancelled</option>
        </select>
      </div>
      <div class="form-group"><label>Способ оплаты</label>
        <select name="payment_method">
          <option value="">Все</option>
          <option value="cash">cash</option>
          <option value="card">card</option>
        </select>
      </div>
      <div class="form-group"><label>Финансовый статус</label>
        <input name="financial_status" placeholder="financial_status" />
      </div>
      <div class="form-group"><label>Driver ID</label><input name="driver_id" /></div>
      <div class="form-group"><label>Client ID</label><input name="client_id" /></div>
      <div class="form-group"><label>С</label><input name="from" type="date" /></div>
      <div class="form-group"><label>По</label><input name="to" type="date" /></div>
      <button class="btn btn-primary" id="orders-apply">Применить</button>
      <button class="btn" id="orders-reset">Сбросить</button>
    </div>
    <div id="orders-table">${LoadingState()}</div>
  `;
  // restore values
  for (const k of ['status','payment_method','financial_status','driver_id','client_id','from','to']) {
    const el = main.querySelector(`[name="${k}"]`);
    if (el && f[k] !== undefined) el.value = f[k];
  }
  $('#orders-apply', main).onclick = () => {
    for (const k of ['status','payment_method','financial_status','driver_id','client_id','from','to']) {
      f[k] = main.querySelector(`[name="${k}"]`).value;
    }
    f.offset = 0;
    loadOrders();
  };
  $('#orders-reset', main).onclick = () => { state.filters.orders = { limit: 50, offset: 0 }; pageOrders(main); };
  loadOrders();

  async function loadOrders() {
    const tbl = $('#orders-table', main);
    tbl.innerHTML = LoadingState();
    try {
      const data = await api.get('/api/v1/admin/orders', { query: f });
      const items = data.items || [];
      if (items.length === 0) { tbl.innerHTML = `<div class="table-wrap">${EmptyState('Заказы не найдены')}</div>`; return; }
      tbl.innerHTML = `<div class="table-wrap"><table>
        <thead><tr>
          <th>Order ID</th><th>Клиент</th><th>Водитель</th><th>Статус</th>
          <th>Оплата</th><th>Pay status</th><th>Fin status</th>
          <th class="num">Итого</th><th class="num">Комиссия</th><th class="num">Водителю</th>
          <th>Создан</th><th>Завершён</th>
        </tr></thead>
        <tbody>
          ${items.map(o => `
            <tr data-id="${escapeHtml(o.order_id)}">
              <td class="mono">${shortId(o.order_id)}</td>
              <td>${escapeHtml(o.client_name || '—')}<div class="muted mono">${escapeHtml(o.client_phone || '')}</div></td>
              <td>${escapeHtml(o.driver_name || '—')}<div class="muted mono">${escapeHtml(o.driver_phone || '')}</div></td>
              <td>${statusBadge(o.status, { completed:'badge-success', cancelled:'badge-danger', pending:'badge-warning' })}</td>
              <td>${escapeHtml(o.payment_method || '—')}</td>
              <td>${statusBadge(o.payment_status, { paid:'badge-success', failed:'badge-danger' })}</td>
              <td>${escapeHtml(o.financial_status || '—')}</td>
              <td class="num">${formatMoneyMinor(o.price_total)}</td>
              <td class="num">${formatMoneyMinor(o.commission_amount)}</td>
              <td class="num">${formatMoneyMinor(o.driver_amount)}</td>
              <td>${formatDate(o.created_at)}</td>
              <td>${formatDate(o.completed_at)}</td>
            </tr>`).join('')}
        </tbody>
      </table>
      ${Pagination(data.total || items.length, f.limit, f.offset, (off) => { f.offset = off; loadOrders(); })}
      </div>`;
      $$('tbody tr', tbl).forEach(tr => tr.onclick = () => openOrderDrawer(tr.dataset.id));
    } catch (e) {
      tbl.innerHTML = ErrorState(e.message, loadOrders);
    }
  }
}

async function openOrderDrawer(orderId) {
  openDrawer('Заказ ' + shortId(orderId), LoadingState());
  try {
    const d = await api.get('/api/v1/admin/orders/' + encodeURIComponent(orderId));
    const o = d.order || {};
    const body = `
      <div class="drawer-section">
        <h3>Заказ</h3>
        <div class="kv">
          <div class="k">ID</div><div class="mono">${escapeHtml(o.order_id || orderId)}</div>
          <div class="k">Статус</div><div>${statusBadge(o.status)}</div>
          <div class="k">Создан</div><div>${formatDate(o.created_at)}</div>
          <div class="k">Завершён</div><div>${formatDate(o.completed_at)}</div>
          <div class="k">Тип эвакуатора</div><div>${escapeHtml(d.tow_truck_type || '—')}</div>
        </div>
      </div>
      <div class="drawer-section">
        <h3>Маршрут</h3>
        <div class="kv">
          <div class="k">Pickup</div><div>${d.pickup ? `${d.pickup.lat}, ${d.pickup.lng}` : '—'}</div>
          <div class="k">Dropoff</div><div>${d.dropoff ? `${d.dropoff.lat}, ${d.dropoff.lng}` : '—'}</div>
        </div>
      </div>
      <div class="drawer-section">
        <h3>Клиент</h3>
        <div class="kv">
          <div class="k">Имя</div><div>${escapeHtml(o.client_name || '—')}</div>
          <div class="k">Телефон</div><div class="mono">${escapeHtml(o.client_phone || '—')}</div>
          <div class="k">ID</div><div class="mono">${escapeHtml(o.client_id || '—')}</div>
        </div>
      </div>
      <div class="drawer-section">
        <h3>Водитель</h3>
        <div class="kv">
          <div class="k">Имя</div><div>${escapeHtml(o.driver_name || '—')}</div>
          <div class="k">Телефон</div><div class="mono">${escapeHtml(o.driver_phone || '—')}</div>
          <div class="k">ID</div><div class="mono">${escapeHtml(o.driver_id || '—')}</div>
        </div>
      </div>
      <div class="drawer-section">
        <h3>Статус timeline</h3>
        ${(d.timeline || []).length === 0 ? `<div class="muted">—</div>` : `<table><tbody>
          ${(d.timeline || []).map(t => `<tr class="no-hover"><td>${formatDate(t.at)}</td><td>${statusBadge(t.status)}</td></tr>`).join('')}
        </tbody></table>`}
      </div>
      <div class="drawer-section">
        <h3>Платёж</h3>
        ${d.payment ? `<div class="kv">
          <div class="k">ID</div><div class="mono">${escapeHtml(d.payment.id)}</div>
          <div class="k">Метод</div><div>${escapeHtml(d.payment.payment_method)}</div>
          <div class="k">Provider</div><div>${escapeHtml(d.payment.provider)} <span class="muted mono">${escapeHtml(d.payment.provider_payment_id || '')}</span></div>
          <div class="k">Сумма</div><div class="num">${formatMoneyMinor(d.payment.amount)}</div>
          <div class="k">Статус</div><div>${statusBadge(d.payment.status)}</div>
          <div class="k">Оплачен</div><div>${formatDate(d.payment.paid_at)}</div>
        </div>` : `<div class="muted">Нет данных</div>`}
      </div>
      <div class="drawer-section">
        <h3>Wallet транзакции</h3>
        ${(d.wallet_transactions || []).length === 0 ? `<div class="muted">—</div>` : `<table><thead><tr><th>Тип</th><th>Напр.</th><th class="num">Сумма</th><th>Статус</th></tr></thead><tbody>
          ${d.wallet_transactions.map(t => `<tr class="no-hover"><td>${escapeHtml(t.type)}</td><td>${escapeHtml(t.direction)}</td><td class="num">${formatMoneyMinor(t.amount)}</td><td>${statusBadge(t.status)}</td></tr>`).join('')}
        </tbody></table>`}
      </div>
      <div class="drawer-section">
        <h3>Выплаты</h3>
        ${(d.payouts || []).length === 0 ? `<div class="muted">—</div>` : `<table><thead><tr><th>ID</th><th class="num">Сумма</th><th>Статус</th></tr></thead><tbody>
          ${d.payouts.map(p => `<tr class="no-hover"><td class="mono">${shortId(p.id)}</td><td class="num">${formatMoneyMinor(p.amount)}</td><td>${statusBadge(p.status)}</td></tr>`).join('')}
        </tbody></table>`}
      </div>
      <div class="drawer-section">
        <h3>Возвраты</h3>
        ${(d.refunds || []).length === 0 ? `<div class="muted">—</div>` : `<table><thead><tr><th>ID</th><th class="num">Сумма</th><th>Статус</th><th>Причина</th></tr></thead><tbody>
          ${d.refunds.map(r => `<tr class="no-hover"><td class="mono">${shortId(r.id)}</td><td class="num">${formatMoneyMinor(r.amount)}</td><td>${statusBadge(r.status)}</td><td>${escapeHtml(r.reason || '')}</td></tr>`).join('')}
        </tbody></table>`}
      </div>
      <div class="drawer-section">
        <h3>Финансовая разбивка</h3>
        ${d.financial_breakdown ? `<div class="kv">
          <div class="k">Итого</div><div class="num">${formatMoneyMinor(d.financial_breakdown.total_amount)}</div>
          <div class="k">Комиссия</div><div class="num">${formatMoneyMinor(d.financial_breakdown.commission_amount)}</div>
          <div class="k">Водителю</div><div class="num">${formatMoneyMinor(d.financial_breakdown.driver_amount)}</div>
          <div class="k">Cash commission hold</div><div class="num">${formatMoneyMinor(d.financial_breakdown.cash_commission_hold)}</div>
          <div class="k">Net платформе</div><div class="num">${formatMoneyMinor(d.financial_breakdown.platform_net_amount)}</div>
        </div>` : `<div class="muted">—</div>`}
      </div>`;
    openDrawer('Заказ ' + shortId(orderId), body);
  } catch (e) {
    openDrawer('Заказ ' + shortId(orderId), ErrorState(e.message));
  }
}

/* ---------- 7.3 Drivers ---------- */
async function pageDrivers(main) {
  main.innerHTML = LoadingState();
  try {
    const data = await api.get('/api/v1/admin/users', { query: { limit: 200 } });
    const drivers = (data.items || []).filter(u => String(u.role).toLowerCase() === 'driver');
    if (drivers.length === 0) { main.innerHTML = EmptyState('Водители не найдены'); return; }
    main.innerHTML = `<div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>Имя</th><th>Телефон</th><th>Заказов</th><th>Статус</th></tr></thead>
      <tbody>
        ${drivers.map(u => `<tr class="no-hover">
          <td class="mono">${shortId(u.id)}</td>
          <td>${escapeHtml(u.name || '—')}</td>
          <td class="mono">${escapeHtml(u.phone || '')}</td>
          <td class="num">${u.orders ?? 0}</td>
          <td>${statusBadge(u.status)}</td>
        </tr>`).join('')}
      </tbody>
    </table></div>
    <p class="muted" style="margin-top:8px">Источник данных: <code>/api/v1/admin/users</code>. Подробные поля водителя (документы, машина) — см. вкладку «Документы».</p>`;
  } catch (e) {
    main.innerHTML = ErrorState(e.message, () => pageDrivers(main));
  }
}

/* ---------- 7.4 Documents / Moderation ---------- */
async function pageDocuments(main) {
  main.innerHTML = LoadingState();
  try {
    const data = await api.get('/api/v1/admin/driver-verifications', { query: { limit: 100 } });
    const items = data.items || [];
    if (items.length === 0) { main.innerHTML = EmptyState('Нет заявок на верификацию'); return; }
    main.innerHTML = `<div class="table-wrap"><table>
      <thead><tr>
        <th>ID</th><th>Имя</th><th>Телефон</th><th>Город</th>
        <th>Гос. номер</th><th>Машина</th><th>Тип</th>
        <th>Статус</th><th>Подана</th>
      </tr></thead>
      <tbody>
        ${items.map(v => `<tr data-id="${escapeHtml(v.id)}">
          <td class="mono">${shortId(v.id)}</td>
          <td>${escapeHtml(v.driver_name || '—')}</td>
          <td class="mono">${escapeHtml(v.phone || '')}</td>
          <td>${escapeHtml(v.city || '—')}</td>
          <td class="mono">${escapeHtml(v.plate || '—')}</td>
          <td>${escapeHtml(v.vehicle || '—')}</td>
          <td>${escapeHtml(v.vehicle_type || '—')}</td>
          <td>${statusBadge(v.status, { approved:'badge-success', rejected:'badge-danger', pending:'badge-warning', blocked:'badge-danger' })}</td>
          <td>${formatDate(v.submitted_at)}</td>
        </tr>`).join('')}
      </tbody>
    </table></div>`;
    $$('tbody tr', main).forEach(tr => tr.onclick = () => openVerificationDrawer(items.find(v => v.id === tr.dataset.id)));
  } catch (e) {
    main.innerHTML = ErrorState(e.message, () => pageDocuments(main));
  }
}

function openVerificationDrawer(v) {
  if (!v) return;
  const docs = (v.documents || []).map(d => `<li><a href="${escapeHtml(d)}" target="_blank" rel="noopener">${escapeHtml(d)}</a></li>`).join('');
  const signals = (v.signals || []).map(s => `<span class="badge badge-warning">${escapeHtml(s)}</span>`).join(' ');
  const body = `
    <div class="drawer-section"><h3>Водитель</h3>
      <div class="kv">
        <div class="k">Имя</div><div>${escapeHtml(v.driver_name || '—')}</div>
        <div class="k">Телефон</div><div class="mono">${escapeHtml(v.phone || '—')}</div>
        <div class="k">Город</div><div>${escapeHtml(v.city || '—')}</div>
        <div class="k">Звёзды</div><div>${v.stars ?? '—'}</div>
        <div class="k">Заказы</div><div>${v.orders ?? 0}</div>
      </div>
    </div>
    <div class="drawer-section"><h3>Транспорт</h3>
      <div class="kv">
        <div class="k">Гос. номер</div><div class="mono">${escapeHtml(v.plate || '—')}</div>
        <div class="k">Модель</div><div>${escapeHtml(v.vehicle || '—')}</div>
        <div class="k">Тип</div><div>${escapeHtml(v.vehicle_type || '—')}</div>
      </div>
    </div>
    <div class="drawer-section"><h3>Документы</h3>${docs ? `<ul>${docs}</ul>` : '<div class="muted">—</div>'}</div>
    ${signals ? `<div class="drawer-section"><h3>Сигналы</h3>${signals}</div>` : ''}
    ${v.decision_reason ? `<div class="drawer-section"><h3>Причина решения</h3><div>${escapeHtml(v.decision_reason)}</div></div>` : ''}`;
  const footer = `
    <button class="btn btn-success" id="vbtn-approve">Approve</button>
    <button class="btn btn-warning" id="vbtn-changes">Request changes</button>
    <button class="btn btn-danger"  id="vbtn-reject">Reject</button>
    <button class="btn btn-danger"  id="vbtn-block">Block</button>`;
  openDrawer('Верификация ' + shortId(v.id), body, footer);
  $('#vbtn-approve').onclick  = () => moderationApproveModal(v.id);
  $('#vbtn-changes').onclick  = () => moderationReasonModal(v.id, 'request-changes', 'Запросить правки');
  $('#vbtn-reject').onclick   = () => moderationReasonModal(v.id, 'reject', 'Отклонить заявку');
  $('#vbtn-block').onclick    = () => moderationReasonModal(v.id, 'block', 'Заблокировать водителя');
}

function moderationApproveModal(id) {
  openModal('Approve заявки', `
    <div class="form-group"><label>Причина / комментарий</label><textarea name="reason" placeholder="минимум 8 символов"></textarea></div>
    <div class="form-group"><label>Гос. номер</label><input name="vehicle_plate" /></div>
    <div class="form-group"><label>Модель</label><input name="vehicle_model" /></div>
    <div class="form-group"><label>Тип</label>
      <select name="vehicle_type">
        <option value="winch">winch</option>
        <option value="platform">platform</option>
        <option value="manipulator">manipulator</option>
      </select>
    </div>`, [
    { label: 'Отмена', onClick: ({ close }) => close() },
    { label: 'Approve', cls: 'btn-success', onClick: async ({ getInput, close }) => {
      const body = {
        reason: getInput('reason'),
        vehicle_plate: getInput('vehicle_plate'),
        vehicle_model: getInput('vehicle_model'),
        vehicle_type:  getInput('vehicle_type'),
      };
      try {
        await api.post(`/api/v1/admin/moderation/driver-verifications/${encodeURIComponent(id)}/approve`, body);
        toast('Заявка одобрена', 'success');
        close(); closeDrawer(); pageDocuments($('.main'));
      } catch (e) { toast(e.message, 'error'); }
    }},
  ]);
}

function moderationReasonModal(id, action, title) {
  openModal(title, `<div class="form-group"><label>Причина (мин. 8 символов)</label><textarea name="reason"></textarea></div>`, [
    { label: 'Отмена', onClick: ({ close }) => close() },
    { label: 'Подтвердить', cls: 'btn-danger', onClick: async ({ getInput, close }) => {
      const reason = (getInput('reason') || '').trim();
      if (reason.length < 8) { toast('Причина должна быть не короче 8 символов', 'warning'); return; }
      try {
        await api.post(`/api/v1/admin/moderation/driver-verifications/${encodeURIComponent(id)}/${action}`, { reason });
        toast('Готово', 'success');
        close(); closeDrawer(); pageDocuments($('.main'));
      } catch (e) { toast(e.message, 'error'); }
    }},
  ]);
}

/* ---------- 7.5 Tax Profiles (missing) ---------- */
function pageTaxProfiles(main) {
  main.innerHTML = `
    <div class="card">
      <div class="card-header"><div class="card-title">Налоговые профили</div></div>
      ${MissingEndpointState('Backend endpoint /api/v1/admin/tax-profiles отсутствует')}
      <p class="muted" style="margin-top:8px">Доступны только per-driver endpoints: <code>GET/PUT /api/v1/drivers/{driverID}/tax-profile</code>. Списка всех налоговых профилей и admin verify/reject пока нет.</p>
    </div>`;
}

/* ---------- 7.6 Service Areas (CRUD missing, check works) ---------- */
function pageServiceAreas(main) {
  main.innerHTML = `
    <div class="card mb-16">
      <div class="card-header"><div class="card-title">Список зон</div></div>
      ${MissingEndpointState('Backend CRUD endpoint /api/v1/admin/service-areas отсутствует')}
    </div>
    <div class="card">
      <div class="card-header"><div class="card-title">Проверка точки</div></div>
      <div class="row">
        <div class="form-group" style="max-width:160px"><label>Lat</label><input name="lat" type="number" step="0.0001" /></div>
        <div class="form-group" style="max-width:160px"><label>Lng</label><input name="lng" type="number" step="0.0001" /></div>
        <button class="btn btn-primary" id="sa-check">Проверить</button>
      </div>
      <div id="sa-result" class="mb-12"></div>
    </div>`;
  $('#sa-check').onclick = async () => {
    const lat = $('[name="lat"]', main).value;
    const lng = $('[name="lng"]', main).value;
    if (!lat || !lng) { toast('Укажите lat и lng', 'warning'); return; }
    const res = $('#sa-result');
    res.innerHTML = LoadingState('Проверка...');
    try {
      const r = await api.get('/api/v1/service-areas/check', { query: { lat, lng } });
      res.innerHTML = `<pre class="card mono" style="white-space:pre-wrap">${escapeHtml(JSON.stringify(r, null, 2))}</pre>`;
    } catch (e) { res.innerHTML = ErrorState(e.message); }
  };
}

/* ---------- Helpers for finance report-shaped tabs ---------- */
async function loadFinanceReport(reportType, container) {
  container.innerHTML = LoadingState(`Загрузка отчёта "${reportType}"...`);
  try {
    const data = await api.get('/api/v1/admin/finance/' + reportType);
    const rows = data.rows || [];
    if (rows.length === 0) {
      container.innerHTML = EmptyState(`Нет данных в отчёте "${reportType}"`);
      return null;
    }
    const header = rows[0] || [];
    const body = rows.slice(1);
    if (header.length === 0) {
      container.innerHTML = EmptyState('Отчёт пуст - нет заголовков');
      return null;
    }
    container.innerHTML = `<div class="table-wrap"><table>
      <thead><tr>${header.map(h => `<th>${escapeHtml(h)}</th>`).join('')}</tr></thead>
      <tbody>${body.map(r => `<tr class="no-hover">${r.map(c => `<td>${escapeHtml(c || '—')}</td>`).join('')}</tr>`).join('')}</tbody>
    </table></div>
    <div style="margin-top:8px" class="muted">Записей: ${body.length}</div>`;
    return { header, body };
  } catch (e) {
    console.error(`Finance report ${reportType} error:`, e);
    container.innerHTML = ErrorState(`Ошибка загрузки отчёта "${reportType}": ${e.message}`, () => loadFinanceReport(reportType, container));
    return null;
  }
}

/* ---------- 7.7 Payments ---------- */
function pagePayments(main) {
  main.innerHTML = `
    <div class="card mb-16">
      <div class="card-header"><div class="card-title">Платежи</div></div>
      <p style="margin:0">Источник данных: отчёт сервера. Структурированные фильтры пока не поддерживаются.</p>
    </div>
    <div id="rep"></div>`;
  loadFinanceReport('payments', $('#rep', main));
}

/* ---------- 7.8 Payouts ---------- */
async function pagePayouts(main) {
  main.innerHTML = `
    <p class="muted mb-12">Источник: отчёт <code>/api/v1/admin/finance/payouts</code>. Approve/Reject — по ID через кнопки ниже.</p>
    <div id="rep" class="mb-16"></div>
    <div class="card">
      <div class="card-header"><div class="card-title">Действия по payout</div></div>
      <div class="row">
        <div class="form-group" style="flex:1 1 240px"><label>Payout ID</label><input name="pid" /></div>
        <button class="btn btn-success" id="po-appr">Approve</button>
        <button class="btn btn-danger"  id="po-rej">Reject…</button>
      </div>
    </div>`;
  loadFinanceReport('payouts', $('#rep', main));
  $('#po-appr', main).onclick = async () => {
    const pid = $('[name="pid"]', main).value.trim();
    if (!pid) { toast('Укажите Payout ID', 'warning'); return; }
    confirmDialog('Approve payout ' + pid + '?', async () => {
      try { await api.post(`/api/v1/admin/finance/payouts/${encodeURIComponent(pid)}/approve`, {}); toast('Approved', 'success'); loadFinanceReport('payouts', $('#rep', main)); }
      catch (e) { toast(e.message, 'error'); }
    });
  };
  $('#po-rej', main).onclick = () => {
    const pid = $('[name="pid"]', main).value.trim();
    if (!pid) { toast('Укажите Payout ID', 'warning'); return; }
    openModal('Reject payout', `<div class="form-group"><label>Причина (мин. 8 символов)</label><textarea name="reason"></textarea></div>`, [
      { label: 'Отмена', onClick: ({ close }) => close() },
      { label: 'Reject', cls: 'btn-danger', onClick: async ({ getInput, close }) => {
        const reason = (getInput('reason') || '').trim();
        if (reason.length < 8) { toast('Минимум 8 символов', 'warning'); return; }
        try { await api.post(`/api/v1/admin/finance/payouts/${encodeURIComponent(pid)}/reject`, { reason }); toast('Rejected', 'success'); close(); loadFinanceReport('payouts', $('#rep', main)); }
        catch (e) { toast(e.message, 'error'); }
      }},
    ]);
  };
}

/* ---------- 7.9 Wallets ---------- */
function pageWallets(main) {
  main.innerHTML = `
    <div class="card mb-16">
      <div class="card-header"><div class="card-title">Кошельки водителей</div></div>
      <p style="margin:0">Балансы и задолженности по комиссии. Поле «Расчёты с Tow Truck» показывает долг водителя.</p>
    </div>
    <div id="rep"></div>`;
  loadFinanceReport('wallets', $('#rep', main));
}

/* ---------- 7.10 Transactions ---------- */
function pageTransactions(main) {
  main.innerHTML = `
    <div class="card mb-16">
      <div class="card-header"><div class="card-title">Транзакции по кошелькам</div></div>
      <p style="margin:0">Все операции по кошелькам водителей: доходы, удержания, выплаты.</p>
    </div>
    <div id="rep"></div>`;
  loadFinanceReport('transactions', $('#rep', main));
}

/* ---------- 7.11 Subscriptions ---------- */
function pageSubscriptions(main) {
  main.innerHTML = `
    <div class="card mb-16">
      <div class="card-header"><div class="card-title">Подписки водителей</div></div>
      <p style="margin:0">Подписки водителей на премиум-функции. Подписка не обязательна для работы в сервисе.</p>
    </div>
    <div id="rep"></div>`;
  loadFinanceReport('subscriptions', $('#rep', main));
}

/* ---------- 7.12 Refunds ---------- */
async function pageRefunds(main) {
  const f = state.filters.refunds || (state.filters.refunds = { limit: 50, offset: 0 });
  main.innerHTML = `
    <div class="filter-bar">
      <div class="form-group"><label>Статус</label><input name="status" /></div>
      <div class="form-group"><label>Payment ID</label><input name="payment_id" /></div>
      <div class="form-group"><label>Order ID</label><input name="order_id" /></div>
      <div class="form-group"><label>С</label><input name="from" type="date" /></div>
      <div class="form-group"><label>По</label><input name="to" type="date" /></div>
      <button class="btn btn-primary" id="rf-apply">Применить</button>
      <button class="btn btn-success" id="rf-new">Создать refund</button>
    </div>
    <div id="rf-table">${LoadingState()}</div>`;
  for (const k of ['status','payment_id','order_id','from','to']) {
    if (f[k]) main.querySelector(`[name="${k}"]`).value = f[k];
  }
  $('#rf-apply', main).onclick = () => {
    for (const k of ['status','payment_id','order_id','from','to']) f[k] = main.querySelector(`[name="${k}"]`).value;
    f.offset = 0; load();
  };
  $('#rf-new', main).onclick = () => createRefundModal(load);
  load();
  async function load() {
    const tbl = $('#rf-table', main);
    tbl.innerHTML = LoadingState();
    try {
      const data = await api.get('/api/v1/admin/finance/refunds', { query: f });
      const items = data.items || [];
      if (items.length === 0) { tbl.innerHTML = `<div class="table-wrap">${EmptyState()}</div>`; return; }
      tbl.innerHTML = `<div class="table-wrap"><table>
        <thead><tr><th>Refund ID</th><th>Payment ID</th><th class="num">Сумма</th><th>Статус</th><th>Provider Refund</th><th>Создан</th></tr></thead>
        <tbody>${items.map(r => `<tr class="no-hover">
          <td class="mono">${shortId(r.refund_id)}</td>
          <td class="mono">${shortId(r.payment_id)}</td>
          <td class="num">${formatMoneyMinor(r.amount)}</td>
          <td>${statusBadge(r.status, { succeeded:'badge-success', failed:'badge-danger' })}</td>
          <td class="mono">${escapeHtml(r.provider_refund_id || '—')}</td>
          <td>${formatDate(r.created_at)}</td>
        </tr>`).join('')}</tbody></table>
        ${Pagination(data.total || items.length, f.limit, f.offset, (off) => { f.offset = off; load(); })}</div>`;
    } catch (e) { tbl.innerHTML = ErrorState(e.message, load); }
  }
}

function createRefundModal(onDone) {
  openModal('Создать refund', `
    <div class="form-group"><label>Payment ID</label><input name="payment_id" /></div>
    <div class="form-group"><label>Сумма (копейки)</label><input name="amount" type="number" min="1" /></div>
    <div class="form-group"><label>Причина</label><textarea name="reason"></textarea></div>
    <p class="muted">Внимание: возврат у провайдера может быть частичным/локальным — зависит от backend.</p>
  `, [
    { label: 'Отмена', onClick: ({ close }) => close() },
    { label: 'Создать', cls: 'btn-primary', onClick: async ({ getInput, close }) => {
      const body = { payment_id: getInput('payment_id').trim(), amount: Number(getInput('amount')), reason: getInput('reason') };
      if (!body.payment_id || !body.amount) { toast('Заполните payment_id и сумму', 'warning'); return; }
      try { await api.post('/api/v1/admin/finance/refunds', body); toast('Refund создан', 'success'); close(); onDone(); }
      catch (e) { toast(e.message, 'error'); }
    }},
  ]);
}

/* ---------- 7.13 Reports / Export ---------- */
function pageReports(main) {
  const types = ['orders','payments','payouts','wallets','transactions','subscriptions','commissions','cash-debts'];
  main.innerHTML = `
    <div class="card">
      <div class="card-header"><div class="card-title">Экспорт CSV</div></div>
      <div class="row">
        <div class="form-group" style="max-width:240px"><label>Тип отчёта</label>
          <select name="type">${types.map(t => `<option>${t}</option>`).join('')}</select>
        </div>
        <button class="btn btn-primary" id="rp-dl">Скачать CSV</button>
      </div>
      <p class="muted" style="margin-top:8px">Endpoint: <code>POST /api/v1/admin/finance/export?type=…</code>. Поддерживается также <code>GET /api/v1/admin/finance/{type}</code> для просмотра в таблице (вкладки Финансы).</p>
    </div>`;
  $('#rp-dl', main).onclick = async () => {
    const t = $('[name="type"]', main).value;
    try {
      const res = await api.request('POST', '/api/v1/admin/finance/export', { query: { type: t }, raw: true });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = `${t}.csv`; a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch (e) { toast(e.message, 'error'); }
  };
}

/* ---------- 7.14 Reviews ---------- */
async function pageReviews(main) {
  main.innerHTML = LoadingState();
  try {
    const data = await api.get('/api/v1/admin/reviews', { query: { limit: 100 } });
    const items = data.items || [];
    if (items.length === 0) { main.innerHTML = EmptyState(); return; }
    main.innerHTML = `<p class="muted mb-12">Read-only — действий модерации в backend нет.</p>
    <div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>Order</th><th>Клиент</th><th>Водитель</th><th>★</th><th>Комментарий</th><th>Создан</th></tr></thead>
      <tbody>${items.map(r => `<tr class="no-hover">
        <td class="mono">${shortId(r.id)}</td>
        <td class="mono">${shortId(r.order_id)}</td>
        <td>${escapeHtml(r.client_name || r.client_id || '—')}</td>
        <td>${escapeHtml(r.driver_name || r.driver_id || '—')}</td>
        <td>${r.stars ?? '—'}</td>
        <td>${escapeHtml(r.text || '')}</td>
        <td>${formatDate(r.created_at)}</td>
      </tr>`).join('')}</tbody>
    </table></div>`;
  } catch (e) { main.innerHTML = ErrorState(e.message, () => pageReviews(main)); }
}

/* ---------- 7.15 Users ---------- */
async function pageUsers(main) {
  main.innerHTML = `
    <div class="filter-bar">
      <div class="form-group"><label>Роль</label>
        <select name="role">
          <option value="">Все</option>
          <option value="client">client</option>
          <option value="driver">driver</option>
          <option value="admin">admin</option>
        </select>
      </div>
      <div class="form-group" style="flex:1 1 240px"><label>Поиск</label><input name="search" placeholder="имя или телефон" /></div>
    </div>
    <div id="usr-table">${LoadingState()}</div>`;
  let all = [];
  try {
    const data = await api.get('/api/v1/admin/users', { query: { limit: 200 } });
    all = data.items || [];
  } catch (e) {
    $('#usr-table', main).innerHTML = ErrorState(e.message);
    return;
  }
  function render() {
    const role = $('[name="role"]', main).value;
    const q = $('[name="search"]', main).value.toLowerCase().trim();
    let rows = all;
    if (role) rows = rows.filter(u => String(u.role).toLowerCase() === role);
    if (q) rows = rows.filter(u => (u.name || '').toLowerCase().includes(q) || (u.phone || '').toLowerCase().includes(q));
    const tbl = $('#usr-table', main);
    if (rows.length === 0) { tbl.innerHTML = `<div class="table-wrap">${EmptyState()}</div>`; return; }
    tbl.innerHTML = `<div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>Телефон</th><th>Имя</th><th>Роль</th><th>Заказов</th><th>Статус</th></tr></thead>
      <tbody>${rows.map(u => `<tr class="no-hover">
        <td class="mono">${shortId(u.id)}</td>
        <td class="mono">${escapeHtml(u.phone || '')}</td>
        <td>${escapeHtml(u.name || '—')}</td>
        <td>${escapeHtml(u.role || '—')}</td>
        <td class="num">${u.orders ?? 0}</td>
        <td>${statusBadge(u.status)}</td>
      </tr>`).join('')}</tbody></table></div>`;
  }
  $('[name="role"]', main).onchange = render;
  $('[name="search"]', main).oninput = debounce(render, 200);
  render();
}

/* ---------- 7.16 Online Map ---------- */
async function pageOnlineMap(main) {
  main.innerHTML = LoadingState();
  try {
    const data = await api.get('/api/v1/admin/drivers-online', { query: { limit: 200 } });
    const items = data.items || [];
    if (items.length === 0) { main.innerHTML = EmptyState('Нет водителей онлайн'); return; }
    main.innerHTML = `<p class="muted mb-12">Карта-провайдер в admin-web не подключён — показаны координаты в виде таблицы.</p>
    <div class="table-wrap"><table>
      <thead><tr><th>ID</th><th>Имя</th><th>Lat</th><th>Lng</th><th>Машина</th><th>Статус</th><th>Last seen</th></tr></thead>
      <tbody>${items.map(d => `<tr class="no-hover">
        <td class="mono">${shortId(d.id)}</td>
        <td>${escapeHtml(d.name || '—')}</td>
        <td class="mono">${d.lat}</td>
        <td class="mono">${d.lng}</td>
        <td>${escapeHtml(d.vehicle || '—')}</td>
        <td>${statusBadge(d.status, { online:'badge-success', busy:'badge-warning' })}</td>
        <td>${formatDate(d.last_seen)}</td>
      </tr>`).join('')}</tbody>
    </table></div>`;
  } catch (e) { main.innerHTML = ErrorState(e.message, () => pageOnlineMap(main)); }
}

/* ---------- 7.17 Settings (missing) ---------- */
function pageSettings(main) {
  main.innerHTML = `
    <div class="card">
      <div class="card-header"><div class="card-title">Настройки</div></div>
      ${MissingEndpointState('Backend settings endpoint отсутствует')}
      <p class="muted" style="margin-top:8px">В будущем здесь будут: процент комиссии, режим выплат, таймаут оффера, лимит раундов диспетчеризации, дефолтные зоны, цена подписки.</p>
    </div>`;
}

/* ============================================================
 * Render dispatch
 * ============================================================ */
const PAGE_FN = {
  'dashboard':     pageDashboard,
  'orders':        pageOrders,
  'drivers':       pageDrivers,
  'documents':     pageDocuments,
  'tax-profiles':  pageTaxProfiles,
  'service-areas': pageServiceAreas,
  'payments':      pagePayments,
  'payouts':       pagePayouts,
  'wallets':       pageWallets,
  'transactions':  pageTransactions,
  'subscriptions': pageSubscriptions,
  'refunds':       pageRefunds,
  'reports':       pageReports,
  'reviews':       pageReviews,
  'users':         pageUsers,
  'online-map':    pageOnlineMap,
  'settings':      pageSettings,
};

function renderApp() {
  if (!state.token) { renderLogin(); return; }
  renderShell();
  const main = $('.main');
  const fn = PAGE_FN[state.route.name] || pageDashboard;
  try { fn(main); }
  catch (e) { main.innerHTML = ErrorState(e.message); }
}

function renderLogin() {
  $('#app').innerHTML = `
    <div class="login-screen">
      <form class="login-card" id="login-form">
        <h1>Tow Truck Admin</h1>
        <div class="sub">Войдите для управления платформой</div>
        <div class="form-group"><label>Логин</label><input name="username" autocomplete="username" required /></div>
        <div class="form-group"><label>Пароль</label><input name="password" type="password" autocomplete="current-password" required /></div>
        <div id="login-err" class="state error" style="display:none;padding:8px 0"></div>
        <button class="btn btn-primary btn-lg" type="submit">Войти</button>
      </form>
    </div>`;
  $('#login-form').onsubmit = async (e) => {
    e.preventDefault();
    const u = e.target.username.value;
    const p = e.target.password.value;
    const err = $('#login-err');
    err.style.display = 'none';
    try { await login(u, p); renderApp(); }
    catch (ex) { err.textContent = ex.message; err.style.display = 'block'; }
  };
}

function renderShell() {
  const groups = {};
  for (const r of ROUTES) {
    (groups[r.group] = groups[r.group] || []).push(r);
  }
  const groupHtml = Object.entries(groups).map(([g, items]) => `
    <div class="sidebar-group">
      <div class="sidebar-group-title">${escapeHtml(g)}</div>
      ${items.map(r => `<a class="sidebar-link ${state.route.name === r.id ? 'active' : ''}" href="#/${r.id}">${escapeHtml(r.title)}</a>`).join('')}
    </div>`).join('');
  const title = (ROUTES.find(r => r.id === state.route.name) || ROUTES[0]).title;
  $('#app').innerHTML = `
    <div class="layout">
      <aside class="sidebar">
        <div class="sidebar-brand">Tow Truck<div class="brand-sub">Admin Panel</div></div>
        ${groupHtml}
      </aside>
      <header class="topbar">
        <div class="row" style="flex:0 0 auto;gap:12px">
          <button class="btn btn-ghost btn-sm menu-toggle" id="menu-toggle">☰</button>
          <div class="topbar-title">${escapeHtml(title)}</div>
        </div>
        <div class="topbar-actions">
          <span class="backend-status" id="backend-status"><span class="dot"></span><span>сервер</span></span>
          <button class="btn btn-sm" id="theme-btn">🌙 Тёмная</button>
          <button class="btn btn-sm" id="refresh-btn">↻ Обновить</button>
          <button class="btn btn-sm" id="logout-btn">Выйти</button>
        </div>
      </header>
      <section class="main"></section>
    </div>`;
  $('#refresh-btn').onclick = () => renderApp();
  $('#logout-btn').onclick = () => logout();
  $('#theme-btn').onclick = toggleTheme;
  $('#menu-toggle').onclick = () => $('.sidebar').classList.toggle('open');
  renderBackendStatus();
}

function renderBackendStatus() {
  const el = document.getElementById('backend-status');
  if (!el) return;
  el.classList.remove('ok', 'err');
  if (state.backendOk === true) el.classList.add('ok');
  else if (state.backendOk === false) el.classList.add('err');
  el.lastElementChild.textContent = state.backendOk === false ? 'нет связи' : (state.backendOk === true ? 'подключен' : 'сервер');
}

function toggleTheme() {
  const body = document.body;
  const btn = $('#theme-btn');
  const isDark = body.getAttribute('data-theme') === 'dark';
  body.setAttribute('data-theme', isDark ? 'light' : 'dark');
  btn.textContent = isDark ? '🌙 Тёмная' : '☀️ Светлая';
  try { localStorage.setItem('admin_theme', isDark ? 'light' : 'dark'); } catch (_) {}
}

/* ============================================================
 * 8. BOOTSTRAP
 * ============================================================ */
window.addEventListener('hashchange', routeChanged);
window.addEventListener('DOMContentLoaded', () => {
  loadToken();
  loadTheme();
  state.route = parseHash();
  renderApp();
});

function loadTheme() {
  try {
    const saved = localStorage.getItem('admin_theme') || 'light';
    document.body.setAttribute('data-theme', saved);
  } catch (_) {}
}
