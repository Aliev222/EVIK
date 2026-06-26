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
  patch(path, body, opts) { return this.request('PATCH',  path, { ...(opts || {}), body }); },
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
  return `<div class="state-container">
    <div class="loading-spinner"></div>
    <h3 class="state-title">${escapeHtml(label)}</h3>
  </div>`;
}

function EmptyState(title = 'Нет данных', description = 'На данный момент информация отсутствует', actionText = null, actionFn = null) {
  const id = actionFn ? 'empty-action-' + Math.random().toString(36).slice(2, 8) : null;
  if (actionFn && id) {
    setTimeout(() => {
      const el = document.getElementById(id);
      if (el) el.onclick = actionFn;
    }, 0);
  }
  return `<div class="state-container glass">
    <div class="state-icon-wrapper">
      ${svgIcon('folder-open')}
    </div>
    <h3 class="state-title">${escapeHtml(title)}</h3>
    <p class="state-description">${escapeHtml(description)}</p>
    ${actionText && actionFn ? `<div class="state-action"><button id="${id}" class="btn btn-primary">${svgIcon('plus')} ${escapeHtml(actionText)}</button></div>` : ''}
  </div>`;
}

function ErrorState(msg, retryFn) {
  const id = 'retry-' + Math.random().toString(36).slice(2, 8);
  setTimeout(() => {
    const el = document.getElementById(id);
    if (el && retryFn) el.onclick = retryFn;
  }, 0);
  return `<div class="state-container glass error-state">
    <div class="state-icon-wrapper">
      ${svgIcon('alert-triangle')}
    </div>
    <h3 class="state-title">Ошибка загрузки</h3>
    <p class="state-description">${escapeHtml(msg)}</p>
    <div class="state-action">
      <button id="${id}" class="btn btn-primary">${svgIcon('refresh-cw')} Повторить попытку</button>
    </div>
  </div>`;
}

function MissingEndpointState(title = 'Функция в разработке', description = 'Серверный endpoint для этого раздела находится в разработке и будет доступен в следующем обновлении.') {
  return `<div class="state-container">
    ${icon('code', 'state-icon')}
    <h3 class="state-title">${escapeHtml(title)}</h3>
    <p class="state-description">${escapeHtml(description)}</p>
  </div>`;
}

function KpiCard(label, value, trend = null, iconName = 'dollar-sign') {
  const trendHtml = trend ? `
    <div class="kpi-trend ${trend > 0 ? 'positive' : trend < 0 ? 'negative' : ''}">
      ${trend > 0 ? icon('trending-up', 'w-3 h-3') : trend < 0 ? icon('trending-down', 'w-3 h-3') : ''}
      ${Math.abs(trend)}%
    </div>` : '';

  return `<div class="kpi-card card-hover card-glow">
    <div class="kpi-header">
      <h4 class="kpi-label">${escapeHtml(label)}</h4>
      ${icon(iconName, 'kpi-icon')}
    </div>
    <div class="kpi-value">${value}</div>
    ${trendHtml}
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
      <div class="modal glass">
        <div class="modal-header">
          ${svgIcon('settings')}
          <span>${title}</span>
        </div>
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
function formatBigInt(n) {
  const v = Number(n);
  if (!Number.isFinite(v)) return '0';
  return new Intl.NumberFormat('ru-RU').format(Math.round(v));
}

function dashSkeleton() {
  const kpi = Array.from({ length: 8 }).map(() => `
    <div class="dash-kpi skeleton-card">
      <div class="sk-line sk-w40"></div>
      <div class="sk-line sk-w70 sk-tall"></div>
      <div class="sk-line sk-w30"></div>
    </div>`).join('');
  return `
    <div class="dash-root">
      <div class="dash-kpi-grid">${kpi}</div>
      <div class="dash-charts">
        <div class="dash-card skeleton-card" style="height:360px"></div>
        <div class="dash-card skeleton-card" style="height:360px"></div>
      </div>
      <div class="dash-charts">
        <div class="dash-card skeleton-card" style="height:320px"></div>
        <div class="dash-card skeleton-card" style="height:320px"></div>
      </div>
    </div>`;
}

function dashKpi(label, value, sub, iconName, tone) {
  return `<div class="dash-kpi ${tone ? 'tone-' + tone : ''}">
    <div class="dash-kpi-head">
      <span class="dash-kpi-label">${escapeHtml(label)}</span>
      <span class="dash-kpi-icon">${icon(iconName, 'kpi-icon')}</span>
    </div>
    <div class="dash-kpi-value">${escapeHtml(String(value))}</div>
    <div class="dash-kpi-sub">${sub || ''}</div>
  </div>`;
}

function renderLineChart(series, opts = {}) {
  if (!Array.isArray(series) || series.length === 0) {
    return `<div class="dash-empty">
      ${icon('bar-chart', 'state-icon')}
      <div class="dash-empty-title">Недостаточно данных для построения графика</div>
      <div class="dash-empty-sub">График появится после первых заказов.</div>
    </div>`;
  }
  const id = 'lc-' + Math.random().toString(36).slice(2, 8);
  const w = 720, h = 240, padL = 56, padR = 16, padT = 24, padB = 36;
  const data = series.map(p => ({ date: p.date, value: Number(p.amount) || 0 }));
  const maxRaw = Math.max(...data.map(p => p.value), 0);
  const max = maxRaw === 0 ? 1 : maxRaw;
  const stepX = data.length > 1 ? (w - padL - padR) / (data.length - 1) : 0;
  const yFor = v => padT + (h - padT - padB) * (1 - v / max);
  const pts = data.map((p, i) => ({ x: padL + i * stepX, y: yFor(p.value), v: p.value, d: p.date }));

  // smooth path (Catmull-Rom -> Bezier)
  let path = '';
  if (pts.length === 1) {
    path = `M ${pts[0].x} ${pts[0].y}`;
  } else {
    path = `M ${pts[0].x} ${pts[0].y}`;
    for (let i = 0; i < pts.length - 1; i++) {
      const p0 = pts[i - 1] || pts[i];
      const p1 = pts[i];
      const p2 = pts[i + 1];
      const p3 = pts[i + 2] || p2;
      const cp1x = p1.x + (p2.x - p0.x) / 6;
      const cp1y = p1.y + (p2.y - p0.y) / 6;
      const cp2x = p2.x - (p3.x - p1.x) / 6;
      const cp2y = p2.y - (p3.y - p1.y) / 6;
      path += ` C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${p2.x} ${p2.y}`;
    }
  }
  const areaPath = path + ` L ${pts[pts.length - 1].x} ${h - padB} L ${pts[0].x} ${h - padB} Z`;

  // y gridlines (4)
  const gridCount = 4;
  let grid = '';
  let yLabels = '';
  for (let i = 0; i <= gridCount; i++) {
    const yv = (max * (gridCount - i)) / gridCount;
    const y = yFor(yv);
    grid += `<line class="lc-grid" x1="${padL}" y1="${y}" x2="${w - padR}" y2="${y}" />`;
    const label = opts.money ? formatMoneyMinor(yv) : formatBigInt(yv);
    yLabels += `<text class="lc-ylabel" x="${padL - 8}" y="${y + 4}" text-anchor="end">${escapeHtml(label)}</text>`;
  }

  // x labels — first, middle, last
  const xIdxs = data.length <= 4
    ? data.map((_, i) => i)
    : [0, Math.floor((data.length - 1) / 2), data.length - 1];
  const xLabels = xIdxs.map(i => {
    const p = pts[i];
    const d = new Date(data[i].date);
    const label = isNaN(d.getTime()) ? data[i].date : d.toLocaleDateString('ru-RU', { day: '2-digit', month: 'short' });
    return `<text class="lc-xlabel" x="${p.x}" y="${h - 12}" text-anchor="middle">${escapeHtml(label)}</text>`;
  }).join('');

  // dots + hover targets
  const dots = pts.map((p, i) => `<circle class="lc-dot" cx="${p.x}" cy="${p.y}" r="3" data-i="${i}"></circle>`).join('');
  const hover = pts.map((p, i) => `<rect class="lc-hover" x="${p.x - stepX / 2}" y="${padT}" width="${stepX || w}" height="${h - padT - padB}" data-i="${i}"></rect>`).join('');

  const payload = JSON.stringify(data.map(p => ({
    d: p.date, v: p.value,
  })));

  setTimeout(() => {
    const root = document.getElementById(id);
    if (!root) return;
    const tip = root.querySelector('.lc-tip');
    const cursor = root.querySelector('.lc-cursor');
    const pointsData = JSON.parse(root.dataset.points);
    const dotsEls = Array.from(root.querySelectorAll('.lc-dot'));
    root.querySelectorAll('.lc-hover').forEach(r => {
      r.addEventListener('mouseenter', () => {
        const i = Number(r.dataset.i);
        const d = pointsData[i];
        const p = pts[i];
        dotsEls.forEach(el => el.classList.toggle('active', Number(el.dataset.i) === i));
        cursor.setAttribute('x1', p.x);
        cursor.setAttribute('x2', p.x);
        cursor.style.opacity = '1';
        const dt = new Date(d.d);
        const dateLabel = isNaN(dt.getTime()) ? d.d : dt.toLocaleDateString('ru-RU', { day: '2-digit', month: 'long' });
        const valLabel = opts.money ? formatMoneyMinor(d.v) : formatBigInt(d.v);
        tip.innerHTML = `<div class="lc-tip-date">${escapeHtml(dateLabel)}</div><div class="lc-tip-val">${escapeHtml(valLabel)}</div>`;
        tip.style.opacity = '1';
        const tipW = 160;
        let tx = p.x - tipW / 2;
        tx = Math.max(padL, Math.min(tx, w - padR - tipW));
        tip.style.left = (tx / w * 100) + '%';
        tip.style.top = Math.max(0, p.y - 56) + 'px';
      });
      r.addEventListener('mouseleave', () => {
        dotsEls.forEach(el => el.classList.remove('active'));
        cursor.style.opacity = '0';
        tip.style.opacity = '0';
      });
    });
  }, 0);

  return `<div class="lc-wrap" id="${id}" data-points='${escapeHtml(payload)}'>
    <svg class="lc-svg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
      <defs>
        <linearGradient id="${id}-grad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#A855F7" stop-opacity="0.35"/>
          <stop offset="100%" stop-color="#A855F7" stop-opacity="0"/>
        </linearGradient>
        <linearGradient id="${id}-stroke" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stop-color="#7C3AED"/>
          <stop offset="100%" stop-color="#A855F7"/>
        </linearGradient>
      </defs>
      ${grid}
      ${yLabels}
      <path class="lc-area" d="${areaPath}" fill="url(#${id}-grad)"/>
      <path class="lc-line" d="${path}" stroke="url(#${id}-stroke)" fill="none"/>
      <line class="lc-cursor" x1="0" y1="${padT}" x2="0" y2="${h - padB}"/>
      ${dots}
      ${xLabels}
      ${hover}
    </svg>
    <div class="lc-tip"></div>
  </div>`;
}

function dashRecentOrdersHtml(items) {
  if (!Array.isArray(items) || items.length === 0) {
    return `<div class="dash-empty">
      ${icon('inbox', 'state-icon')}
      <div class="dash-empty-title">Пока нет заказов</div>
      <div class="dash-empty-sub">Новые заказы появятся здесь автоматически.</div>
    </div>`;
  }
  const rows = items.map(o => `
    <tr data-id="${escapeHtml(o.order_id || '')}">
      <td class="mono">${shortId(o.order_id)}</td>
      <td>${escapeHtml(o.client_name || '—')}</td>
      <td>${escapeHtml(o.driver_name || '—')}</td>
      <td>${statusBadge(o.status, { completed:'badge-success', cancelled:'badge-danger', pending:'badge-warning' })}</td>
      <td>${escapeHtml(o.payment_method || '—')}</td>
      <td class="num">${formatMoneyMinor(o.price_total)}</td>
      <td class="num">${formatMoneyMinor(o.commission_amount)}</td>
      <td>${formatDate(o.created_at)}</td>
    </tr>`).join('');
  return `<div class="dash-table-wrap">
    <table class="glass-table dash-table">
      <thead><tr>
        <th>Order ID</th><th>Клиент</th><th>Водитель</th><th>Статус</th>
        <th>Оплата</th><th class="num">Сумма</th><th class="num">Комиссия</th><th>Создан</th>
      </tr></thead>
      <tbody>${rows}</tbody>
    </table>
  </div>`;
}

function dashPendingItem(label, count, route, iconName, danger) {
  const n = Number(count) || 0;
  const isZero = n === 0;
  const cls = isZero ? 'dash-pending-item is-zero' : (danger ? 'dash-pending-item is-danger' : 'dash-pending-item');
  return `<div class="${cls}" data-route="${escapeHtml(route)}">
    <div class="dash-pending-icon">${icon(iconName, 'kpi-icon')}</div>
    <div class="dash-pending-body">
      <div class="dash-pending-label">${escapeHtml(label)}</div>
      <div class="dash-pending-count">${formatBigInt(n)}</div>
    </div>
    <button class="btn btn-ghost btn-sm dash-pending-btn">Открыть →</button>
  </div>`;
}

async function pageDashboard(main) {
  main.innerHTML = dashSkeleton();
  const started = performance.now();
  let o;
  try {
    o = await api.get('/api/v1/admin/overview');
  } catch (e) {
    main.innerHTML = ErrorState(e.message, () => pageDashboard(main));
    return;
  }
  const elapsedMs = Math.round(performance.now() - started);
  const updatedAt = new Date().toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });

  // Render shell synchronously with overview data; recent orders loads after.
  const kpiBlocks = [
    dashKpi('GMV сегодня',       formatMoneyMinor(o.gmv_today),       `за месяц ${formatMoneyMinor(o.gmv_month)}`, 'dollar-sign'),
    dashKpi('Комиссия сегодня',  formatMoneyMinor(o.commission_today),`за месяц ${formatMoneyMinor(o.commission_month)}`, 'trending-up'),
    dashKpi('Выплаты сегодня',   formatMoneyMinor(o.payouts_today),   `за месяц ${formatMoneyMinor(o.payouts_month)}`, 'wallet'),
    dashKpi('Активные заказы',   formatBigInt(o.active_orders),       'идут прямо сейчас', 'inbox'),
    dashKpi('Онлайн водители',   formatBigInt(o.online_drivers),      `всего активных ${formatBigInt(o.active_drivers ?? 0)}`, 'users'),
    dashKpi('На модерации',      formatBigInt(o.pending_verifications), 'ожидают проверки', 'clock', (Number(o.pending_verifications) || 0) > 0 ? 'warn' : null),
    dashKpi('Ожидают выплаты',   formatMoneyMinor(o.payouts_pending),  'к перечислению водителям', 'arrow-up-down', (Number(o.payouts_pending) || 0) > 0 ? 'warn' : null),
    dashKpi('Failed payments',   formatBigInt(o.failed_payments),     `failed payouts: ${formatBigInt(o.failed_payouts ?? 0)}`, 'alert-triangle', (Number(o.failed_payments) || 0) + (Number(o.failed_payouts) || 0) > 0 ? 'danger' : null),
  ].join('');

  const hasGmv = Array.isArray(o.gmv_by_day) && o.gmv_by_day.length > 0;
  const hasCommission = Array.isArray(o.commission_by_day) && o.commission_by_day.length > 0;

  const pendingCounts = {
    moderation: Number(o.pending_verifications) || 0,
    payouts:    Number(o.payouts_pending) || 0,
    failedPay:  Number(o.failed_payments) || 0,
    failedPout: Number(o.failed_payouts) || 0,
  };

  const totalAttention = pendingCounts.moderation + (pendingCounts.payouts > 0 ? 1 : 0) + pendingCounts.failedPay + pendingCounts.failedPout;

  const healthOk = state.backendOk !== false && pendingCounts.failedPay === 0 && pendingCounts.failedPout === 0;
  const healthState = state.backendOk === false ? 'down' : (healthOk ? 'ok' : 'warn');
  const healthLabel = { ok: 'Все системы в норме', warn: 'Требует внимания', down: 'Нет связи с сервером' }[healthState];

  main.innerHTML = `
    <div class="dash-root">
      <header class="dash-header">
        <div>
          <h1 class="dash-title">Дашборд</h1>
          <p class="dash-subtitle">Ключевые показатели платформы Tow Truck</p>
        </div>
        <div class="dash-header-meta">
          <span class="dash-pill dash-pill-${state.backendOk === false ? 'err' : 'ok'}">
            <span class="dash-dot"></span>
            ${state.backendOk === false ? 'Нет связи' : 'Подключено'} · обновлено ${escapeHtml(updatedAt)}
          </span>
          <button class="btn btn-secondary btn-sm" id="dash-refresh">
            ${icon('refresh-cw', 'w-4 h-4')} Обновить
          </button>
        </div>
      </header>

      <section class="dash-kpi-grid">${kpiBlocks}</section>

      <section class="dash-charts">
        <div class="dash-card">
          <div class="dash-card-head">
            <div>
              <div class="dash-card-title">GMV за период</div>
              <div class="dash-card-sub">Оборот платформы, ${hasGmv ? o.gmv_by_day.length : 0} точек</div>
            </div>
            <div class="dash-card-figure">${formatMoneyMinor(o.gmv_month)}</div>
          </div>
          <div class="dash-chart">${renderLineChart(o.gmv_by_day, { money: true })}</div>
        </div>
        <div class="dash-card">
          <div class="dash-card-head">
            <div>
              <div class="dash-card-title">Комиссия за период</div>
              <div class="dash-card-sub">Заработок Tow Truck, ${hasCommission ? o.commission_by_day.length : 0} точек</div>
            </div>
            <div class="dash-card-figure">${formatMoneyMinor(o.commission_month)}</div>
          </div>
          <div class="dash-chart">${renderLineChart(o.commission_by_day, { money: true })}</div>
        </div>
      </section>

      <section class="dash-row-split">
        <div class="dash-card">
          <div class="dash-card-head">
            <div>
              <div class="dash-card-title">Последние заказы</div>
              <div class="dash-card-sub">10 самых свежих</div>
            </div>
            <button class="btn btn-ghost btn-sm" data-goto="orders">Все заказы →</button>
          </div>
          <div id="dash-recent">${LoadingState('Загрузка заказов...')}</div>
        </div>

        <div class="dash-card">
          <div class="dash-card-head">
            <div>
              <div class="dash-card-title">Требует внимания</div>
              <div class="dash-card-sub">${totalAttention > 0 ? formatBigInt(totalAttention) + ' задач(и)' : 'все обработано'}</div>
            </div>
          </div>
          <div class="dash-pending">
            ${dashPendingItem('Водители на модерации', pendingCounts.moderation, 'documents', 'file-text', pendingCounts.moderation > 0)}
            ${dashPendingItem('Запросы на выплаты',    pendingCounts.payouts > 0 ? 1 : 0, 'payouts', 'arrow-up-down', pendingCounts.payouts > 0)}
            ${dashPendingItem('Failed payments',       pendingCounts.failedPay, 'payments', 'credit-card', pendingCounts.failedPay > 0)}
            ${dashPendingItem('Failed payouts',        pendingCounts.failedPout, 'payouts', 'alert-triangle', pendingCounts.failedPout > 0)}
            ${dashPendingItem('Pending refunds',       0, 'refunds', 'rotate-ccw', false)}
          </div>
        </div>
      </section>

      <section class="dash-row-split">
        <div class="dash-card">
          <div class="dash-card-head">
            <div>
              <div class="dash-card-title">Состояние системы</div>
              <div class="dash-card-sub">${escapeHtml(healthLabel)}</div>
            </div>
            <span class="dash-pill dash-pill-${healthState === 'ok' ? 'ok' : (healthState === 'down' ? 'err' : 'warn')}">
              <span class="dash-dot"></span>
              ${escapeHtml(healthLabel)}
            </span>
          </div>
          <div class="dash-health">
            <div class="dash-health-row">
              <span class="dash-health-label">API сервер</span>
              <span class="dash-health-val">${state.backendOk === false ? 'недоступен' : 'отвечает за ' + elapsedMs + ' мс'}</span>
              <span class="dash-health-dot ${state.backendOk === false ? 'is-err' : 'is-ok'}"></span>
            </div>
            <div class="dash-health-row">
              <span class="dash-health-label">Платежи</span>
              <span class="dash-health-val">${pendingCounts.failedPay === 0 ? 'без ошибок' : formatBigInt(pendingCounts.failedPay) + ' failed'}</span>
              <span class="dash-health-dot ${pendingCounts.failedPay === 0 ? 'is-ok' : 'is-err'}"></span>
            </div>
            <div class="dash-health-row">
              <span class="dash-health-label">Выплаты</span>
              <span class="dash-health-val">${pendingCounts.failedPout === 0 ? 'без ошибок' : formatBigInt(pendingCounts.failedPout) + ' failed'}</span>
              <span class="dash-health-dot ${pendingCounts.failedPout === 0 ? 'is-ok' : 'is-err'}"></span>
            </div>
          </div>
        </div>

        <div class="dash-card">
          <div class="dash-card-head">
            <div>
              <div class="dash-card-title">Аудитория</div>
              <div class="dash-card-sub">по данным платформы</div>
            </div>
          </div>
          <div class="dash-audience">
            <div class="dash-audience-item">
              <div class="dash-audience-label">Пользователей</div>
              <div class="dash-audience-value">${formatBigInt(o.total_users ?? 0)}</div>
            </div>
            <div class="dash-audience-item">
              <div class="dash-audience-label">Клиентов</div>
              <div class="dash-audience-value">${formatBigInt(o.clients ?? 0)}</div>
            </div>
            <div class="dash-audience-item">
              <div class="dash-audience-label">Водителей</div>
              <div class="dash-audience-value">${formatBigInt(o.drivers ?? 0)}</div>
            </div>
            <div class="dash-audience-item">
              <div class="dash-audience-label">Средний рейтинг</div>
              <div class="dash-audience-value">${o.average_driver_stars ? Number(o.average_driver_stars).toFixed(2) : '—'}</div>
            </div>
            <div class="dash-audience-item">
              <div class="dash-audience-label">Отзывов сегодня</div>
              <div class="dash-audience-value">${formatBigInt(o.reviews_today ?? 0)}</div>
            </div>
            <div class="dash-audience-item">
              <div class="dash-audience-label">Расчёты с Tow Truck</div>
              <div class="dash-audience-value">${formatMoneyMinor(o.cash_debt_total ?? 0)}</div>
            </div>
          </div>
        </div>
      </section>
    </div>
  `;

  // Wire actions.
  const refreshBtn = document.getElementById('dash-refresh');
  if (refreshBtn) refreshBtn.onclick = () => pageDashboard(main);
  main.querySelectorAll('[data-goto]').forEach(el => {
    el.onclick = () => navigate('#/' + el.dataset.goto);
  });
  main.querySelectorAll('.dash-pending-item').forEach(el => {
    const r = el.dataset.route;
    if (!r) return;
    el.onclick = (e) => {
      if (e.target.closest('button') || el.classList.contains('is-zero')) {
        if (el.classList.contains('is-zero')) return;
      }
      navigate('#/' + r);
    };
  });

  // Lazy-load recent orders from existing endpoint.
  (async () => {
    const slot = document.getElementById('dash-recent');
    if (!slot) return;
    try {
      const data = await api.get('/api/v1/admin/orders', { query: { limit: 10, offset: 0 } });
      const items = (data && data.items) || [];
      slot.innerHTML = dashRecentOrdersHtml(items);
      slot.querySelectorAll('tbody tr').forEach(tr => {
        tr.style.cursor = 'pointer';
        tr.onclick = () => {
          const id = tr.dataset.id;
          if (id) openOrderDrawer(id);
        };
      });
    } catch (e) {
      slot.innerHTML = `<div class="dash-empty">
        ${icon('alert-triangle', 'state-icon')}
        <div class="dash-empty-title">Не удалось загрузить заказы</div>
        <div class="dash-empty-sub">${escapeHtml(e.message)}</div>
      </div>`;
    }
  })();
}

/* ---------- 7.2 Orders ---------- */
const ORDER_STATUS_BADGES = {
  searching:       'badge-warning',
  pending:         'badge-warning',
  accepted:        'badge-info',
  assigned:        'badge-info',
  en_route:        'badge-info',
  arrived:         'badge-info',
  loading:         'badge-primary',
  in_progress:     'badge-primary',
  completed:       'badge-success',
  cancelled:       'badge-danger',
  no_driver_found: 'badge-muted',
};

const ORDER_STATUS_LABELS = {
  searching: 'Поиск водителя',
  pending: 'Ожидает',
  accepted: 'Принят',
  assigned: 'Назначен',
  en_route: 'В пути',
  arrived: 'Прибыл',
  loading: 'Погрузка',
  in_progress: 'В работе',
  completed: 'Завершён',
  cancelled: 'Отменён',
  no_driver_found: 'Без водителя',
};

function orderStatusBadge(status) {
  if (!status) return `<span class="badge badge-muted">—</span>`;
  const cls = ORDER_STATUS_BADGES[status] || 'badge-muted';
  const label = ORDER_STATUS_LABELS[status] || status;
  return `<span class="badge ${cls}">${escapeHtml(label)}</span>`;
}

function paymentMethodBadge(method) {
  if (!method) return '—';
  const map = { cash: 'badge-warning', card: 'badge-info' };
  const labels = { cash: 'Наличные', card: 'Карта' };
  return `<span class="badge ${map[method] || 'badge-muted'}">${escapeHtml(labels[method] || method)}</span>`;
}

function paymentStatusBadge(s) {
  if (!s) return '—';
  const map = { paid: 'badge-success', captured: 'badge-success', failed: 'badge-danger', pending: 'badge-warning', refunded: 'badge-muted' };
  return `<span class="badge ${map[s] || 'badge-muted'}">${escapeHtml(s)}</span>`;
}

function finStatusBadge(s) {
  if (!s) return '—';
  const map = { completed: 'badge-success', settled: 'badge-success', failed: 'badge-danger', pending: 'badge-warning' };
  return `<span class="badge ${map[s] || 'badge-muted'}">${escapeHtml(s)}</span>`;
}

function isActiveStatus(s) {
  return ['searching','pending','accepted','assigned','en_route','arrived','loading','in_progress'].includes(s);
}

function ordersKpiAggregate(items) {
  const a = {
    total: items.length,
    active: 0, completed: 0, cancelled: 0, noDriver: 0,
    gmv: 0, commission: 0, payout: 0,
  };
  for (const o of items) {
    if (o.status === 'completed') a.completed++;
    else if (o.status === 'cancelled') a.cancelled++;
    else if (o.status === 'no_driver_found') a.noDriver++;
    else if (isActiveStatus(o.status)) a.active++;
    a.gmv += Number(o.price_total) || 0;
    a.commission += Number(o.commission_amount) || 0;
    a.payout += Number(o.driver_amount) || 0;
  }
  return a;
}

function ordersKpiStrip(items, totalKnown) {
  const a = ordersKpiAggregate(items);
  const t = (totalKnown != null) ? totalKnown : a.total;
  const cell = (label, value, tone) => `
    <div class="ord-kpi ${tone ? 'tone-' + tone : ''}">
      <div class="ord-kpi-label">${escapeHtml(label)}</div>
      <div class="ord-kpi-value">${value}</div>
    </div>`;
  return `<div class="ord-kpi-strip">
    ${cell('Всего заказов', formatBigInt(t))}
    ${cell('Активные', formatBigInt(a.active), a.active > 0 ? 'info' : null)}
    ${cell('Завершённые', formatBigInt(a.completed), a.completed > 0 ? 'success' : null)}
    ${cell('Отменённые', formatBigInt(a.cancelled), a.cancelled > 0 ? 'warn' : null)}
    ${cell('Без водителя', formatBigInt(a.noDriver), a.noDriver > 0 ? 'danger' : null)}
    ${cell('GMV (на странице)', formatMoneyMinor(a.gmv))}
    ${cell('Комиссия (на странице)', formatMoneyMinor(a.commission))}
    ${cell('К выплате (на странице)', formatMoneyMinor(a.payout))}
  </div>`;
}

const ORDERS_FILTER_KEYS = ['status','payment_method','payment_status','financial_status','driver_id','client_id','from','to'];

const ORDERS_FILTER_LABELS = {
  status: 'Статус',
  payment_method: 'Оплата',
  payment_status: 'Pay status',
  financial_status: 'Fin status',
  driver_id: 'Driver',
  client_id: 'Client',
  from: 'С',
  to: 'По',
};

function ordersActiveChips(f) {
  const items = ORDERS_FILTER_KEYS
    .filter(k => f[k] !== undefined && f[k] !== '' && f[k] !== null)
    .map(k => `<span class="ord-chip" data-clear="${k}">
      <span class="ord-chip-label">${escapeHtml(ORDERS_FILTER_LABELS[k])}:</span>
      <span class="ord-chip-value">${escapeHtml(String(f[k]))}</span>
      <span class="ord-chip-x">×</span>
    </span>`);
  if (items.length === 0) return '';
  return `<div class="ord-chips">
    ${items.join('')}
    <button class="btn btn-ghost btn-sm" id="ord-chips-reset">Сбросить всё</button>
  </div>`;
}

function ordersTableSkeleton(rows = 10) {
  const tr = Array.from({ length: rows }).map(() => `
    <tr class="ord-skel-row">
      ${Array.from({ length: 11 }).map(() => `<td><div class="sk-line"></div></td>`).join('')}
    </tr>`).join('');
  return `<div class="ord-table-wrap">
    <table class="ord-table"><tbody>${tr}</tbody></table>
  </div>`;
}

async function pageOrders(main) {
  const f = state.filters.orders || (state.filters.orders = { limit: 50, offset: 0 });

  function render() {
    main.innerHTML = `
      <div class="ord-root">
        <header class="ord-header">
          <div>
            <h1 class="dash-title">Заказы</h1>
            <p class="dash-subtitle">Управление всеми заказами платформы</p>
          </div>
          <div class="ord-header-meta">
            <span class="dash-pill dash-pill-ok" id="ord-total-pill">
              <span class="dash-dot"></span>
              Загрузка…
            </span>
            <button class="btn btn-secondary btn-sm" id="ord-refresh">
              ${icon('refresh-cw', 'w-4 h-4')} Обновить
            </button>
          </div>
        </header>

        <div id="ord-kpi-slot"></div>

        <div class="ord-filter-card">
          <div class="ord-filter-head">
            <div class="ord-filter-title">${icon('settings', 'kpi-icon')} Фильтры</div>
            <div class="ord-filter-actions">
              <button class="btn btn-primary btn-sm" id="ord-apply">Применить</button>
              <button class="btn btn-ghost btn-sm" id="ord-reset">Сбросить</button>
            </div>
          </div>
          <div class="ord-filter-grid">
            <label class="ord-field">
              <span>Статус заказа</span>
              <select name="status">
                <option value="">Все</option>
                <option value="searching">Поиск водителя</option>
                <option value="pending">Ожидает</option>
                <option value="accepted">Принят</option>
                <option value="assigned">Назначен</option>
                <option value="en_route">В пути</option>
                <option value="arrived">Прибыл</option>
                <option value="loading">Погрузка</option>
                <option value="in_progress">В работе</option>
                <option value="completed">Завершён</option>
                <option value="cancelled">Отменён</option>
                <option value="no_driver_found">Без водителя</option>
              </select>
            </label>
            <label class="ord-field">
              <span>Способ оплаты</span>
              <select name="payment_method">
                <option value="">Все</option>
                <option value="card">Карта</option>
                <option value="cash">Наличные</option>
              </select>
            </label>
            <label class="ord-field">
              <span>Payment Status</span>
              <select name="payment_status">
                <option value="">Все</option>
                <option value="pending">pending</option>
                <option value="paid">paid</option>
                <option value="captured">captured</option>
                <option value="failed">failed</option>
                <option value="refunded">refunded</option>
              </select>
            </label>
            <label class="ord-field">
              <span>Financial Status</span>
              <input name="financial_status" placeholder="например, settled" />
            </label>
            <label class="ord-field">
              <span>Driver ID</span>
              <input name="driver_id" placeholder="UUID водителя" />
            </label>
            <label class="ord-field">
              <span>Client ID</span>
              <input name="client_id" placeholder="UUID клиента" />
            </label>
            <label class="ord-field">
              <span>Период от</span>
              <input name="from" type="date" />
            </label>
            <label class="ord-field">
              <span>Период до</span>
              <input name="to" type="date" />
            </label>
          </div>
          <div id="ord-chips-slot"></div>
        </div>

        <div id="ord-results">${ordersTableSkeleton()}</div>
      </div>
    `;

    // Restore form values
    for (const k of ORDERS_FILTER_KEYS) {
      const el = main.querySelector(`[name="${k}"]`);
      if (el && f[k] !== undefined) el.value = f[k];
    }

    $('#ord-apply', main).onclick = () => {
      for (const k of ORDERS_FILTER_KEYS) {
        const el = main.querySelector(`[name="${k}"]`);
        const v = el && el.value;
        if (v) f[k] = v; else delete f[k];
      }
      f.offset = 0;
      loadOrders();
    };
    $('#ord-reset', main).onclick = () => {
      state.filters.orders = { limit: f.limit || 50, offset: 0 };
      render();
      loadOrders();
    };
    const refresh = $('#ord-refresh', main);
    if (refresh) refresh.onclick = () => loadOrders();

    refreshChips();
    loadOrders();
  }

  function refreshChips() {
    const slot = $('#ord-chips-slot', main);
    if (!slot) return;
    slot.innerHTML = ordersActiveChips(f);
    slot.querySelectorAll('[data-clear]').forEach(el => {
      el.onclick = () => {
        delete f[el.dataset.clear];
        const input = main.querySelector(`[name="${el.dataset.clear}"]`);
        if (input) input.value = '';
        f.offset = 0;
        refreshChips();
        loadOrders();
      };
    });
    const reset = $('#ord-chips-reset', main);
    if (reset) reset.onclick = () => $('#ord-reset', main).onclick();
  }

  async function loadOrders() {
    const slot = $('#ord-results', main);
    const pill = $('#ord-total-pill', main);
    if (pill) { pill.innerHTML = `<span class="dash-dot"></span> Загрузка…`; pill.className = 'dash-pill dash-pill-ok'; }
    slot.innerHTML = ordersTableSkeleton();
    let data;
    try {
      data = await api.get('/api/v1/admin/orders', { query: f });
    } catch (e) {
      slot.innerHTML = ErrorState(e.message, loadOrders);
      if (pill) { pill.innerHTML = `<span class="dash-dot"></span> Ошибка`; pill.className = 'dash-pill dash-pill-err'; }
      return;
    }
    const items = Array.isArray(data && data.items) ? data.items : [];
    const total = (data && Number(data.total)) || items.length;

    if (pill) {
      pill.innerHTML = `<span class="dash-dot"></span> Всего ${formatBigInt(total)} заказ(ов)`;
      pill.className = 'dash-pill dash-pill-ok';
    }
    const kpiSlot = $('#ord-kpi-slot', main);
    if (kpiSlot) kpiSlot.innerHTML = ordersKpiStrip(items, total);
    refreshChips();

    if (items.length === 0) {
      slot.innerHTML = `<div class="dash-card">
        <div class="dash-empty">
          ${icon('inbox', 'state-icon')}
          <div class="dash-empty-title">Заказы не найдены</div>
          <div class="dash-empty-sub">Попробуйте изменить фильтры или сбросить их.</div>
        </div>
      </div>`;
      return;
    }

    const rowsHtml = items.map(o => {
      const cliMain = o.client_name || o.client_phone || '—';
      const cliPhone = o.client_phone || '';
      const drvMain = o.driver_name || (o.driver_id ? '—' : 'Не назначен');
      const drvPhone = o.driver_phone || '';
      return `
        <tr data-id="${escapeHtml(o.order_id || '')}">
          <td class="mono ord-cell-id">
            <div class="ord-id-row">
              <span>${shortId(o.order_id)}</span>
              <button class="ord-icon-btn" data-copy="${escapeHtml(o.order_id || '')}" title="Скопировать ID">${icon('file-text', 'w-3 h-3')}</button>
            </div>
          </td>
          <td>
            <div class="ord-cell-primary">${escapeHtml(cliMain)}</div>
            ${cliPhone ? `<div class="ord-cell-mono">${escapeHtml(cliPhone)}</div>` : ''}
          </td>
          <td class="ord-cell-mono">${escapeHtml(cliPhone || '—')}</td>
          <td>
            <div class="ord-cell-primary">${escapeHtml(drvMain)}</div>
            ${drvPhone ? `<div class="ord-cell-mono">${escapeHtml(drvPhone)}</div>` : ''}
          </td>
          <td class="ord-cell-mono">—</td>
          <td>${orderStatusBadge(o.status)}</td>
          <td>${paymentMethodBadge(o.payment_method)}</td>
          <td>${paymentStatusBadge(o.payment_status)}</td>
          <td>${finStatusBadge(o.financial_status)}</td>
          <td class="num">${formatMoneyMinor(o.price_total)}</td>
          <td class="num">${formatMoneyMinor(o.commission_amount)}</td>
          <td class="num">${formatMoneyMinor(o.driver_amount)}</td>
          <td class="ord-cell-mono">${formatDate(o.created_at)}</td>
          <td class="ord-cell-mono">${formatDate(o.completed_at)}</td>
          <td class="ord-cell-actions">
            <button class="btn btn-ghost btn-sm" data-action="open">Открыть</button>
          </td>
        </tr>`;
    }).join('');

    const pager = Pagination(total, f.limit || 50, f.offset || 0, (off) => { f.offset = off; loadOrders(); });

    slot.innerHTML = `
      <div class="ord-table-card">
        <div class="ord-table-wrap">
          <table class="ord-table">
            <thead>
              <tr>
                <th>Order ID</th>
                <th>Клиент</th>
                <th>Телефон</th>
                <th>Водитель</th>
                <th>Автомобиль</th>
                <th>Статус</th>
                <th>Оплата</th>
                <th>Pay status</th>
                <th>Fin status</th>
                <th class="num">Итого</th>
                <th class="num">Комиссия</th>
                <th class="num">Водителю</th>
                <th>Создан</th>
                <th>Завершён</th>
                <th>Действия</th>
              </tr>
            </thead>
            <tbody>${rowsHtml}</tbody>
          </table>
        </div>
        ${pager ? `<div class="ord-pager">${pager}</div>` : ''}
      </div>`;

    // Wire row interactions
    slot.querySelectorAll('tbody tr').forEach(tr => {
      tr.onclick = (e) => {
        if (e.target.closest('[data-copy]') || e.target.closest('[data-action="open"]')) return;
        const id = tr.dataset.id; if (id) openOrderDrawer(id);
      };
    });
    slot.querySelectorAll('[data-action="open"]').forEach(b => {
      b.onclick = (e) => {
        e.stopPropagation();
        const id = b.closest('tr').dataset.id;
        if (id) openOrderDrawer(id);
      };
    });
    slot.querySelectorAll('[data-copy]').forEach(b => {
      b.onclick = (e) => {
        e.stopPropagation();
        copyToClipboard(b.dataset.copy);
      };
    });
  }

  render();
}

/* Order details drawer */
function orderDrawerSkeleton() {
  return `<div class="ord-drawer-skel">
    ${Array.from({ length: 5 }).map(() => `<div class="skeleton-card" style="height:120px; border-radius:18px;"></div>`).join('')}
  </div>`;
}

async function openOrderDrawer(orderId) {
  openDrawer('Заказ ' + shortId(orderId), orderDrawerSkeleton());
  let d;
  try {
    d = await api.get('/api/v1/admin/orders/' + encodeURIComponent(orderId));
  } catch (e) {
    openDrawer('Заказ ' + shortId(orderId), ErrorState(e.message, () => openOrderDrawer(orderId)));
    return;
  }
  const o = d.order || {};
  const pickup = d.pickup || null;
  const dropoff = d.dropoff || null;
  const fb = d.financial_breakdown || null;
  const tl = Array.isArray(d.timeline) ? d.timeline : [];
  const payment = d.payment || null;
  const walletTx = Array.isArray(d.wallet_transactions) ? d.wallet_transactions : [];
  const payouts = Array.isArray(d.payouts) ? d.payouts : [];
  const refunds = Array.isArray(d.refunds) ? d.refunds : [];

  const durationStr = (o.created_at && o.completed_at) ? (function () {
    const a = new Date(o.created_at).getTime();
    const b = new Date(o.completed_at).getTime();
    if (!isFinite(a) || !isFinite(b) || b <= a) return '—';
    const sec = Math.round((b - a) / 1000);
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
    return (h ? h + ' ч ' : '') + m + ' мин';
  })() : '—';

  const headTitle = `<div class="ord-drawer-head">
    <div>
      <div class="ord-drawer-id mono">${escapeHtml(o.order_id || orderId)}</div>
      <div class="ord-drawer-sub">${orderStatusBadge(o.status)}</div>
    </div>
    <button class="btn btn-secondary btn-sm" data-drawer-copy="${escapeHtml(o.order_id || orderId)}">${icon('file-text','w-3 h-3')} Копировать ID</button>
  </div>`;

  const generalKv = `
    <div class="ord-kv">
      <div class="ord-kv-row"><div class="ord-kv-k">Order ID</div><div class="ord-kv-v mono">${escapeHtml(o.order_id || orderId)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Статус</div><div class="ord-kv-v">${orderStatusBadge(o.status)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Создан</div><div class="ord-kv-v">${formatDate(o.created_at)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Завершён</div><div class="ord-kv-v">${formatDate(o.completed_at)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Отменён</div><div class="ord-kv-v">${formatDate(o.cancelled_at)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Тип эвакуатора</div><div class="ord-kv-v">${escapeHtml(d.tow_truck_type || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Длительность</div><div class="ord-kv-v">${escapeHtml(durationStr)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Расстояние</div><div class="ord-kv-v">—</div></div>
    </div>`;

  const clientKv = `
    <div class="ord-kv">
      <div class="ord-kv-row"><div class="ord-kv-k">Имя</div><div class="ord-kv-v">${escapeHtml(o.client_name || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Телефон</div><div class="ord-kv-v mono">${escapeHtml(o.client_phone || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Client ID</div><div class="ord-kv-v mono">${escapeHtml(o.client_id || '—')}</div></div>
    </div>`;

  const driverKv = o.driver_id ? `
    <div class="ord-kv">
      <div class="ord-kv-row"><div class="ord-kv-k">Имя</div><div class="ord-kv-v">${escapeHtml(o.driver_name || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Телефон</div><div class="ord-kv-v mono">${escapeHtml(o.driver_phone || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Driver ID</div><div class="ord-kv-v mono">${escapeHtml(o.driver_id || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Номер машины</div><div class="ord-kv-v">—</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Модель</div><div class="ord-kv-v">—</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Тип техники</div><div class="ord-kv-v">${escapeHtml(d.tow_truck_type || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Рейтинг</div><div class="ord-kv-v">—</div></div>
    </div>` : `<div class="ord-empty-section">Водитель не назначен</div>`;

  const fmtCoord = (p) => (p && Number.isFinite(p.lat) && Number.isFinite(p.lng)) ? (p.lat.toFixed(5) + ', ' + p.lng.toFixed(5)) : '—';

  const routeBlock = `
    <div class="ord-kv">
      <div class="ord-kv-row"><div class="ord-kv-k">Pickup адрес</div><div class="ord-kv-v">—</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Dropoff адрес</div><div class="ord-kv-v">—</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Pickup координаты</div><div class="ord-kv-v mono">${escapeHtml(fmtCoord(pickup))}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Dropoff координаты</div><div class="ord-kv-v mono">${escapeHtml(fmtCoord(dropoff))}</div></div>
    </div>`;

  const financeBlock = `
    <div class="ord-kv">
      <div class="ord-kv-row"><div class="ord-kv-k">Стоимость заказа</div><div class="ord-kv-v num">${formatMoneyMinor((fb && fb.total_amount) ?? o.price_total)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Комиссия платформы</div><div class="ord-kv-v num">${formatMoneyMinor((fb && fb.commission_amount) ?? o.commission_amount)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Выплата водителю</div><div class="ord-kv-v num">${formatMoneyMinor((fb && fb.driver_amount) ?? o.driver_amount)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Net платформе</div><div class="ord-kv-v num">${formatMoneyMinor(fb && fb.platform_net_amount)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Cash commission hold</div><div class="ord-kv-v num">${formatMoneyMinor(fb && fb.cash_commission_hold)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Способ оплаты</div><div class="ord-kv-v">${paymentMethodBadge(o.payment_method)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Payment Status</div><div class="ord-kv-v">${paymentStatusBadge(o.payment_status)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Financial Status</div><div class="ord-kv-v">${finStatusBadge(o.financial_status)}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Payment ID</div><div class="ord-kv-v mono">${escapeHtml((payment && payment.id) || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Provider</div><div class="ord-kv-v">${escapeHtml((payment && payment.provider) || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Provider payment ID</div><div class="ord-kv-v mono">${escapeHtml((payment && payment.provider_payment_id) || '—')}</div></div>
      <div class="ord-kv-row"><div class="ord-kv-k">Оплачен</div><div class="ord-kv-v">${formatDate(payment && payment.paid_at)}</div></div>
    </div>
    ${refunds.length ? `
      <div class="ord-subsection-title">Возвраты</div>
      <table class="ord-mini-table">
        <thead><tr><th>ID</th><th class="num">Сумма</th><th>Статус</th><th>Причина</th><th>Создан</th></tr></thead>
        <tbody>${refunds.map(r => `<tr>
          <td class="mono">${shortId(r.id)}</td>
          <td class="num">${formatMoneyMinor(r.amount)}</td>
          <td>${paymentStatusBadge(r.status)}</td>
          <td>${escapeHtml(r.reason || '—')}</td>
          <td class="mono">${formatDate(r.created_at)}</td>
        </tr>`).join('')}</tbody>
      </table>` : ''}
    ${walletTx.length ? `
      <div class="ord-subsection-title">Wallet транзакции водителя</div>
      <table class="ord-mini-table">
        <thead><tr><th>Тип</th><th>Напр.</th><th class="num">Сумма</th><th>Статус</th><th>Создан</th></tr></thead>
        <tbody>${walletTx.map(t => `<tr>
          <td>${escapeHtml(t.type || '—')}</td>
          <td>${escapeHtml(t.direction || '—')}</td>
          <td class="num">${formatMoneyMinor(t.amount)}</td>
          <td>${paymentStatusBadge(t.status)}</td>
          <td class="mono">${formatDate(t.created_at)}</td>
        </tr>`).join('')}</tbody>
      </table>` : ''}
    ${payouts.length ? `
      <div class="ord-subsection-title">Выплаты</div>
      <table class="ord-mini-table">
        <thead><tr><th>ID</th><th class="num">Сумма</th><th>Статус</th><th>Создан</th></tr></thead>
        <tbody>${payouts.map(p => `<tr>
          <td class="mono">${shortId(p.id)}</td>
          <td class="num">${formatMoneyMinor(p.amount)}</td>
          <td>${paymentStatusBadge(p.status)}</td>
          <td class="mono">${formatDate(p.created_at)}</td>
        </tr>`).join('')}</tbody>
      </table>` : ''}
  `;

  const timelineBlock = tl.length === 0
    ? `<div class="ord-empty-section">Нет событий timeline</div>`
    : `<div class="ord-timeline">
        ${tl.map((t, i) => {
          const cls = ORDER_STATUS_BADGES[t.status] || 'badge-muted';
          return `<div class="ord-tl-item">
            <div class="ord-tl-dot dot-${cls}"></div>
            ${i < tl.length - 1 ? '<div class="ord-tl-line"></div>' : ''}
            <div class="ord-tl-body">
              <div class="ord-tl-head">${orderStatusBadge(t.status)}</div>
              <div class="ord-tl-time">${formatDate(t.at)}</div>
            </div>
          </div>`;
        }).join('')}
      </div>`;

  const reviewBlock = `<div class="ord-empty-section">Отзыв отсутствует</div>`;

  const section = (id, title, iconName, body) => `
    <section class="ord-section">
      <div class="ord-section-head">
        <div class="ord-section-title">${icon(iconName, 'kpi-icon')}<span>${escapeHtml(title)}</span></div>
      </div>
      <div class="ord-section-body">${body}</div>
    </section>`;

  const body = `${headTitle}
    ${section('general', 'Общая информация', 'inbox', generalKv)}
    ${section('client', 'Клиент', 'user', clientKv)}
    ${section('driver', 'Водитель', 'users', driverKv)}
    ${section('route', 'Маршрут', 'map-pin', routeBlock)}
    ${section('finance', 'Финансы', 'wallet', financeBlock)}
    ${section('timeline', 'Timeline статусов', 'clock', timelineBlock)}
    ${section('review', 'Отзыв клиента', 'star', reviewBlock)}
  `;

  openDrawer('Заказ ' + shortId(orderId), body);

  document.querySelectorAll('#drawer-root [data-drawer-copy]').forEach(el => {
    el.onclick = () => copyToClipboard(el.dataset.drawerCopy);
  });
}

/* ---------- 7.3 Drivers ---------- */
const DRIVERS_VIEW_KEY = 'admin_drivers_view';
const STALE_THRESHOLD_MS = 2 * 60 * 1000; // 2 minutes

const driversPageState = {
  map: null,
  markersLayer: null,
  markersById: new Map(),
  autoRefreshId: null,
  filters: null,
  unmount: null,
};

function driverStatusBadge(status) {
  if (!status) return `<span class="badge badge-muted">—</span>`;
  const map = {
    online:  { cls: 'badge-success', label: 'Онлайн' },
    free:    { cls: 'badge-success', label: 'Свободен' },
    available: { cls: 'badge-success', label: 'Свободен' },
    busy:    { cls: 'badge-primary', label: 'На заказе' },
    on_order:{ cls: 'badge-primary', label: 'На заказе' },
    offline: { cls: 'badge-muted',   label: 'Оффлайн' },
    blocked: { cls: 'badge-danger',  label: 'Заблокирован' },
    stale:   { cls: 'badge-warning', label: 'Связь потеряна' },
  };
  const m = map[String(status).toLowerCase()] || { cls: 'badge-muted', label: status };
  return `<span class="badge ${m.cls}">${escapeHtml(m.label)}</span>`;
}

function documentsBadge(status) {
  if (!status) return `<span class="badge badge-muted">—</span>`;
  const map = {
    approved: { cls: 'badge-success', label: 'Approved' },
    pending:  { cls: 'badge-warning', label: 'Pending' },
    rejected: { cls: 'badge-danger',  label: 'Rejected' },
    blocked:  { cls: 'badge-danger',  label: 'Blocked' },
  };
  const m = map[String(status).toLowerCase()] || { cls: 'badge-muted', label: status };
  return `<span class="badge ${m.cls}">${escapeHtml(m.label)}</span>`;
}

function taxBadge(status) {
  if (!status) return `<span class="badge badge-muted">—</span>`;
  const map = {
    verified: { cls: 'badge-success', label: 'Verified' },
    pending:  { cls: 'badge-warning', label: 'Pending' },
    rejected: { cls: 'badge-danger',  label: 'Rejected' },
  };
  const m = map[String(status).toLowerCase()] || { cls: 'badge-muted', label: status };
  return `<span class="badge ${m.cls}">${escapeHtml(m.label)}</span>`;
}

function isOnlineStatus(s) {
  if (!s) return false;
  const v = String(s).toLowerCase();
  return v === 'online' || v === 'free' || v === 'available';
}
function isBusyStatus(s) {
  if (!s) return false;
  const v = String(s).toLowerCase();
  return v === 'busy' || v === 'on_order';
}
function isBlockedStatus(s) {
  if (!s) return false;
  const v = String(s).toLowerCase();
  return v === 'blocked';
}
function isStale(lastSeenIso) {
  if (!lastSeenIso) return true;
  const t = Date.parse(lastSeenIso);
  if (!isFinite(t)) return true;
  return (Date.now() - t) > STALE_THRESHOLD_MS;
}

function timeAgo(iso) {
  if (!iso) return '—';
  const t = Date.parse(iso);
  if (!isFinite(t)) return '—';
  const sec = Math.max(0, Math.round((Date.now() - t) / 1000));
  if (sec < 60) return sec + ' сек назад';
  if (sec < 3600) return Math.floor(sec / 60) + ' мин назад';
  if (sec < 86400) return Math.floor(sec / 3600) + ' ч назад';
  return Math.floor(sec / 86400) + ' дн назад';
}

// Merge drivers data from multiple endpoints. Returns a map keyed by a stable
// driver key (driver_id from online > phone > user_id). Missing endpoints are
// tolerated; sources.errors holds which ones failed.
function mergeDriversData(sources) {
  const byPhone = new Map();
  const byUserId = new Map();
  const byDriverId = new Map();

  // 1) Seed with users (only role=driver). Key by user_id and phone.
  for (const u of (sources.users || [])) {
    if (String(u.role).toLowerCase() !== 'driver') continue;
    const rec = {
      driver_id: '',
      user_id: u.id || '',
      full_name: u.name || '',
      phone: u.phone || '',
      role: u.role || '',
      user_status: u.status || '',
      orders_count: Number(u.orders) || 0,
      verification: null,
      online: null,
      wallet: null,
      tax: null,
      active_order_id: '',
    };
    if (rec.user_id) byUserId.set(rec.user_id, rec);
    if (rec.phone) byPhone.set(rec.phone, rec);
  }

  // 2) Driver verifications — match by phone first. Keep most recent approved
  //    or any single record.
  for (const v of (sources.verifications || [])) {
    const key = v.phone && byPhone.has(v.phone) ? v.phone : null;
    let rec;
    if (key) {
      rec = byPhone.get(key);
    } else {
      rec = {
        driver_id: '',
        user_id: '',
        full_name: v.driver_name || '',
        phone: v.phone || '',
        role: 'driver',
        user_status: '',
        orders_count: Number(v.orders) || 0,
        verification: null,
        online: null,
        wallet: null,
        tax: null,
        active_order_id: '',
      };
      if (rec.phone) byPhone.set(rec.phone, rec);
    }
    // Prefer approved over other statuses; else keep first.
    const cur = rec.verification;
    if (!cur || (String(v.status).toLowerCase() === 'approved' && String(cur.status).toLowerCase() !== 'approved')) {
      rec.verification = v;
    }
    if (!rec.full_name && v.driver_name) rec.full_name = v.driver_name;
  }

  // 3) Online drivers — id=driver_id, name=user_id. Link via user_id.
  for (const o of (sources.online || [])) {
    let rec = (o.name && byUserId.get(o.name)) || null;
    if (!rec) {
      rec = {
        driver_id: o.id || '',
        user_id: o.name || '',
        full_name: '',
        phone: '',
        role: 'driver',
        user_status: '',
        orders_count: 0,
        verification: null,
        online: null,
        wallet: null,
        tax: null,
        active_order_id: '',
      };
      if (rec.user_id) byUserId.set(rec.user_id, rec);
    }
    rec.online = o;
    if (o.id) rec.driver_id = o.id;
    if (rec.driver_id) byDriverId.set(rec.driver_id, rec);
  }

  // Ensure all records that don't have driver_id are still indexed somewhere.
  // 4) Wallets — sources.wallets is an array of rows [id, driver_id, available,
  //    pending, debt, currency, updated_at]. Link by driver_id.
  for (const row of (sources.wallets || [])) {
    if (!Array.isArray(row) || row.length < 6) continue;
    const drvId = row[1];
    if (!drvId) continue;
    const rec = byDriverId.get(drvId);
    if (!rec) continue; // wallet without known driver in this batch — skip
    rec.wallet = {
      id: row[0],
      driver_id: drvId,
      available: Number(row[2]) || 0,
      pending: Number(row[3]) || 0,
      debt: Number(row[4]) || 0,
      currency: row[5] || 'RUB',
      updated_at: row[6] || '',
    };
  }

  // 5) Tax profiles — link by driver_id.
  for (const taxProfile of (sources.taxProfiles || [])) {
    if (!taxProfile.driver_id) continue;
    const rec = byDriverId.get(taxProfile.driver_id);
    if (!rec) continue;
    rec.tax = {
      driver_id: taxProfile.driver_id,
      inn: taxProfile.inn,
      taxpayer_type: taxProfile.taxpayer_type,
      verification_status: taxProfile.verification_status,
      created_at: taxProfile.created_at,
      updated_at: taxProfile.updated_at,
    };
  }

  // 6) Orders — active order per driver. Look at non-final statuses for each driver.
  const activeStatuses = new Set(['searching','pending','accepted','assigned','en_route','arrived','loading','in_progress']);
  for (const ord of (sources.orders || [])) {
    if (!ord.driver_id) continue;
    const rec = byDriverId.get(ord.driver_id);
    if (!rec) continue;
    if (activeStatuses.has(ord.status) && !rec.active_order_id) {
      rec.active_order_id = ord.order_id || '';
    }
  }

  // Collect unique records.
  const all = new Map();
  for (const r of byUserId.values()) {
    const key = r.driver_id || r.user_id || r.phone;
    if (key) all.set(key, r);
  }
  for (const r of byPhone.values()) {
    const key = r.driver_id || r.user_id || r.phone;
    if (key && !all.has(key)) all.set(key, r);
  }
  for (const r of byDriverId.values()) {
    const key = r.driver_id || r.user_id || r.phone;
    if (key && !all.has(key)) all.set(key, r);
  }
  return Array.from(all.values());
}

function effectiveDriverStatus(rec) {
  if (rec.online) {
    if (isStale(rec.online.last_seen)) return 'stale';
    return rec.online.status || 'online';
  }
  if (isBlockedStatus(rec.user_status)) return 'blocked';
  return 'offline';
}

function aggregateDriversKpi(records) {
  const a = { total: 0, online: 0, busy: 0, free: 0, moderation: 0, taxPending: 0, blocked: 0, ratingSum: 0, ratingCount: 0 };
  for (const r of records) {
    a.total++;
    const eff = effectiveDriverStatus(r);
    if (eff === 'blocked') a.blocked++;
    else if (isBusyStatus(eff)) a.busy++;
    else if (isOnlineStatus(eff)) a.free++;
    if (r.online && !isStale(r.online.last_seen)) a.online++;
    const vstatus = r.verification && String(r.verification.status).toLowerCase();
    if (vstatus === 'pending') a.moderation++;
    const taxStatus = r.tax && String(r.tax.verification_status).toLowerCase();
    if (taxStatus === 'pending') a.taxPending++;
    if (r.verification && r.verification.stars > 0) {
      a.ratingSum += Number(r.verification.stars) || 0;
      a.ratingCount++;
    }
  }
  const avg = a.ratingCount ? (a.ratingSum / a.ratingCount) : null;
  return { ...a, avgRating: avg };
}

function driversKpiCell(label, value, tone) {
  return `<div class="ord-kpi ${tone ? 'tone-' + tone : ''}">
    <div class="ord-kpi-label">${escapeHtml(label)}</div>
    <div class="ord-kpi-value">${value}</div>
  </div>`;
}

function driversKpiStrip(a) {
  return `<div class="ord-kpi-strip drv-kpi-strip">
    ${driversKpiCell('Всего водителей', formatBigInt(a.total))}
    ${driversKpiCell('Онлайн', formatBigInt(a.online), a.online > 0 ? 'success' : null)}
    ${driversKpiCell('На заказе', formatBigInt(a.busy), a.busy > 0 ? 'info' : null)}
    ${driversKpiCell('Свободны', formatBigInt(a.free), a.free > 0 ? 'success' : null)}
    ${driversKpiCell('На модерации', formatBigInt(a.moderation), a.moderation > 0 ? 'warn' : null)}
    ${driversKpiCell('Tax pending', formatBigInt(a.taxPending), a.taxPending > 0 ? 'warn' : null)}
    ${driversKpiCell('Заблокированы', formatBigInt(a.blocked), a.blocked > 0 ? 'danger' : null)}
    ${driversKpiCell('Средний рейтинг', a.avgRating != null ? a.avgRating.toFixed(2) : '—')}
  </div>`;
}

function driversTableSkeleton(rows = 10) {
  const tr = Array.from({ length: rows }).map(() => `
    <tr class="ord-skel-row">
      ${Array.from({ length: 10 }).map(() => `<td><div class="sk-line"></div></td>`).join('')}
    </tr>`).join('');
  return `<div class="ord-table-wrap"><table class="ord-table"><tbody>${tr}</tbody></table></div>`;
}

function matchesDriverFilters(rec, f) {
  const eff = effectiveDriverStatus(rec);
  const q = (f.search || '').trim().toLowerCase();
  if (q) {
    const blob = [
      rec.full_name, rec.phone, rec.driver_id, rec.user_id,
      rec.verification && rec.verification.plate,
      rec.verification && rec.verification.vehicle,
    ].filter(Boolean).join(' ').toLowerCase();
    if (!blob.includes(q)) return false;
  }
  if (f.status && f.status !== 'all') {
    if (f.status === 'online' && !isOnlineStatus(eff)) return false;
    if (f.status === 'offline' && eff !== 'offline') return false;
    if (f.status === 'busy' && !isBusyStatus(eff)) return false;
    if (f.status === 'blocked' && eff !== 'blocked') return false;
  }
  if (f.docs && f.docs !== 'all') {
    const vs = (rec.verification && String(rec.verification.status).toLowerCase()) || 'missing';
    if (f.docs === 'missing' && rec.verification) return false;
    if (f.docs !== 'missing' && vs !== f.docs) return false;
  }
  if (f.tax && f.tax !== 'all') {
    const taxStatus = (rec.tax && String(rec.tax.verification_status).toLowerCase()) || 'missing';
    if (f.tax === 'missing' && rec.tax) return false;
    if (f.tax !== 'missing' && taxStatus !== f.tax) return false;
  }
  if (f.onlineOnly && !(rec.online && !isStale(rec.online.last_seen))) return false;
  if (f.hasOrder && !rec.active_order_id) return false;
  return true;
}

function driverChip(label, value, key) {
  return `<span class="ord-chip" data-clear-drv="${key}">
    <span class="ord-chip-label">${escapeHtml(label)}:</span>
    <span class="ord-chip-value">${escapeHtml(value)}</span>
    <span class="ord-chip-x">×</span>
  </span>`;
}

function driversActiveChips(f) {
  const chips = [];
  if (f.search) chips.push(driverChip('Поиск', f.search, 'search'));
  if (f.status && f.status !== 'all') chips.push(driverChip('Статус', f.status, 'status'));
  if (f.docs && f.docs !== 'all') chips.push(driverChip('Документы', f.docs, 'docs'));
  if (f.tax && f.tax !== 'all') chips.push(driverChip('Tax', f.tax, 'tax'));
  if (f.onlineOnly) chips.push(driverChip('Только онлайн', 'да', 'onlineOnly'));
  if (f.hasOrder) chips.push(driverChip('С активным заказом', 'да', 'hasOrder'));
  if (chips.length === 0) return '';
  return `<div class="ord-chips">${chips.join('')}<button class="btn btn-ghost btn-sm" id="drv-chips-reset">Сбросить всё</button></div>`;
}

async function pageDrivers(main) {
  // Cleanup map / timers from any previous pageDrivers instance.
  if (driversPageState.unmount) {
    try { driversPageState.unmount(); } catch (_) {}
  }

  const initialView = (() => {
    try { return localStorage.getItem(DRIVERS_VIEW_KEY) || 'table'; } catch (_) { return 'table'; }
  })();
  if (!driversPageState.filters) {
    driversPageState.filters = { search: '', status: 'all', docs: 'all', tax: 'all', onlineOnly: false, hasOrder: false, view: initialView };
  } else {
    driversPageState.filters.view = initialView;
  }

  const state = driversPageState;
  const sources = { users: [], online: [], verifications: [], wallets: [], orders: [], errors: {} };
  let records = [];

  main.innerHTML = `
    <div class="ord-root drv-root">
      <header class="ord-header">
        <div>
          <h1 class="dash-title">Водители</h1>
          <p class="dash-subtitle">Управление водителями, статусами и геолокацией</p>
        </div>
        <div class="ord-header-meta">
          <span class="dash-pill dash-pill-ok" id="drv-total-pill"><span class="dash-dot"></span> Загрузка…</span>
          <span class="dash-pill dash-pill-ok" id="drv-online-pill"><span class="dash-dot"></span> Онлайн: —</span>
          <button class="btn btn-secondary btn-sm" id="drv-refresh">${icon('refresh-cw','w-4 h-4')} Обновить</button>
        </div>
      </header>

      <div id="drv-kpi-slot"></div>

      <div class="drv-toolbar">
        <div class="drv-view-switcher">
          <button class="drv-view-btn" data-view="table">${icon('inbox','w-4 h-4')} Таблица</button>
          <button class="drv-view-btn" data-view="map">${icon('map-pin','w-4 h-4')} Карта</button>
        </div>
        <div id="drv-partial-warn"></div>
      </div>

      <div class="ord-filter-card drv-filter-card">
        <div class="ord-filter-head">
          <div class="ord-filter-title">${icon('settings','kpi-icon')} Фильтры</div>
          <div class="ord-filter-actions">
            <button class="btn btn-primary btn-sm" id="drv-apply">Применить</button>
            <button class="btn btn-ghost btn-sm" id="drv-reset">Сбросить</button>
          </div>
        </div>
        <div class="ord-filter-grid">
          <label class="ord-field"><span>Поиск</span><input name="search" placeholder="имя / телефон / ID / номер" /></label>
          <label class="ord-field"><span>Статус</span>
            <select name="status">
              <option value="all">Все</option>
              <option value="online">Онлайн / Свободен</option>
              <option value="busy">На заказе</option>
              <option value="offline">Оффлайн</option>
              <option value="blocked">Заблокирован</option>
            </select>
          </label>
          <label class="ord-field"><span>Документы</span>
            <select name="docs">
              <option value="all">Все</option>
              <option value="approved">Approved</option>
              <option value="pending">Pending</option>
              <option value="rejected">Rejected</option>
              <option value="blocked">Blocked</option>
              <option value="missing">Без заявки</option>
            </select>
          </label>
          <label class="ord-field"><span>Tax status</span>
            <select name="tax">
              <option value="all">Все</option>
              <option value="verified">Verified</option>
              <option value="pending">Pending</option>
              <option value="rejected">Rejected</option>
              <option value="missing">Без профиля</option>
            </select>
          </label>
          <label class="ord-field drv-checkbox"><input type="checkbox" name="onlineOnly" /><span>Только онлайн</span></label>
          <label class="ord-field drv-checkbox"><input type="checkbox" name="hasOrder" /><span>С активным заказом</span></label>
        </div>
        <div id="drv-chips-slot"></div>
      </div>

      <div id="drv-view-slot">${driversTableSkeleton()}</div>
    </div>
  `;

  // Restore filter values.
  for (const k of ['search','status','docs','tax']) {
    const el = main.querySelector(`[name="${k}"]`);
    if (el) el.value = state.filters[k];
  }
  for (const k of ['onlineOnly','hasOrder']) {
    const el = main.querySelector(`[name="${k}"]`);
    if (el) el.checked = !!state.filters[k];
  }
  highlightViewSwitch();

  $('#drv-refresh', main).onclick = () => loadAll();
  $('#drv-apply', main).onclick = () => {
    state.filters.search = main.querySelector('[name="search"]').value.trim();
    state.filters.status = main.querySelector('[name="status"]').value;
    state.filters.docs = main.querySelector('[name="docs"]').value;
    state.filters.tax = main.querySelector('[name="tax"]').value;
    state.filters.onlineOnly = !!main.querySelector('[name="onlineOnly"]').checked;
    state.filters.hasOrder = !!main.querySelector('[name="hasOrder"]').checked;
    renderCurrentView();
    renderChips();
  };
  $('#drv-reset', main).onclick = () => {
    state.filters = { search: '', status: 'all', docs: 'all', tax: 'all', onlineOnly: false, hasOrder: false, view: state.filters.view };
    for (const k of ['search','status','docs','tax']) main.querySelector(`[name="${k}"]`).value = (k === 'search' ? '' : 'all');
    for (const k of ['onlineOnly','hasOrder']) main.querySelector(`[name="${k}"]`).checked = false;
    renderCurrentView();
    renderChips();
  };
  main.querySelectorAll('.drv-view-btn').forEach(b => {
    b.onclick = () => {
      state.filters.view = b.dataset.view;
      try { localStorage.setItem(DRIVERS_VIEW_KEY, b.dataset.view); } catch (_) {}
      highlightViewSwitch();
      renderCurrentView();
    };
  });

  function highlightViewSwitch() {
    main.querySelectorAll('.drv-view-btn').forEach(b => {
      b.classList.toggle('is-active', b.dataset.view === state.filters.view);
    });
  }

  function renderChips() {
    const slot = $('#drv-chips-slot', main);
    if (!slot) return;
    slot.innerHTML = driversActiveChips(state.filters);
    slot.querySelectorAll('[data-clear-drv]').forEach(el => {
      el.onclick = () => {
        const k = el.dataset.clearDrv;
        if (k === 'search') { state.filters.search = ''; const i = main.querySelector('[name="search"]'); if (i) i.value = ''; }
        else if (k === 'status') { state.filters.status = 'all'; main.querySelector('[name="status"]').value = 'all'; }
        else if (k === 'docs') { state.filters.docs = 'all'; main.querySelector('[name="docs"]').value = 'all'; }
        else if (k === 'tax') { state.filters.tax = 'all'; main.querySelector('[name="tax"]').value = 'all'; }
        else if (k === 'onlineOnly') { state.filters.onlineOnly = false; main.querySelector('[name="onlineOnly"]').checked = false; }
        else if (k === 'hasOrder') { state.filters.hasOrder = false; main.querySelector('[name="hasOrder"]').checked = false; }
        renderChips();
        renderCurrentView();
      };
    });
    const reset = $('#drv-chips-reset', main);
    if (reset) reset.onclick = () => $('#drv-reset', main).onclick();
  }

  function renderPartialWarn() {
    const warns = [];
    if (sources.errors.users) warns.push('пользователи');
    if (sources.errors.online) warns.push('online');
    if (sources.errors.verifications) warns.push('верификации');
    if (sources.errors.wallets) warns.push('кошельки');
    if (sources.errors.orders) warns.push('заказы');
    if (sources.errors.tax) warns.push('налоги');
    const slot = $('#drv-partial-warn', main);
    if (!slot) return;
    if (warns.length === 0) { slot.innerHTML = ''; return; }
    slot.innerHTML = `<span class="drv-warn">${icon('alert-triangle','w-3 h-3')} Часть данных недоступна: ${escapeHtml(warns.join(', '))}</span>`;
  }

  async function safeGet(name, path, query) {
    try {
      const r = await api.get(path, { query });
      sources.errors[name] = null;
      return r;
    } catch (e) {
      sources.errors[name] = e.message || 'error';
      return null;
    }
  }

  async function loadAll() {
    $('#drv-view-slot', main).innerHTML = driversTableSkeleton();
    const [u, o, v, w, ords, taxProfiles] = await Promise.all([
      safeGet('users', '/api/v1/admin/users', { limit: 200 }),
      safeGet('online', '/api/v1/admin/drivers-online', { limit: 200 }),
      safeGet('verifications', '/api/v1/admin/driver-verifications', { limit: 200 }),
      safeGet('wallets', '/api/v1/admin/finance/wallets'),
      safeGet('orders', '/api/v1/admin/orders', { limit: 200 }),
      safeGet('taxProfiles', '/api/v1/admin/tax-profiles', { limit: 200 }),
    ]);

    sources.users = (u && u.items) || [];
    sources.online = (o && o.items) || [];
    sources.verifications = (v && v.items) || [];
    sources.wallets = (w && Array.isArray(w.rows)) ? w.rows : [];
    sources.orders = (ords && ords.items) || [];
    sources.taxProfiles = (taxProfiles && taxProfiles.items) || [];

    records = mergeDriversData(sources);
    refreshHeaderPills();
    refreshKpi();
    renderPartialWarn();
    renderCurrentView();
    renderChips();
  }

  function refreshHeaderPills() {
    const totalP = $('#drv-total-pill', main);
    const onlineP = $('#drv-online-pill', main);
    const onlineCount = records.filter(r => r.online && !isStale(r.online.last_seen)).length;
    if (totalP) totalP.innerHTML = `<span class="dash-dot"></span> Всего ${formatBigInt(records.length)} водителей`;
    if (onlineP) {
      onlineP.innerHTML = `<span class="dash-dot"></span> Онлайн: ${formatBigInt(onlineCount)}`;
      onlineP.className = 'dash-pill dash-pill-' + (onlineCount > 0 ? 'ok' : 'warn');
    }
  }

  function refreshKpi() {
    const slot = $('#drv-kpi-slot', main);
    if (slot) slot.innerHTML = driversKpiStrip(aggregateDriversKpi(records));
  }

  function renderCurrentView() {
    if (state.filters.view === 'map') renderMapView();
    else renderTableView();
  }

  function renderTableView() {
    // Tear down map if active.
    teardownMap();

    const filtered = records.filter(r => matchesDriverFilters(r, state.filters));
    const slot = $('#drv-view-slot', main);
    if (filtered.length === 0) {
      slot.innerHTML = `<div class="dash-card"><div class="dash-empty">
        ${icon('users','state-icon')}
        <div class="dash-empty-title">Водители не найдены</div>
        <div class="dash-empty-sub">Попробуйте изменить фильтры.</div>
      </div></div>`;
      return;
    }

    const rowsHtml = filtered.map(r => driverTableRow(r)).join('');
    slot.innerHTML = `
      <div class="ord-table-card">
        <div class="ord-table-wrap">
          <table class="ord-table drv-table">
            <thead>
              <tr>
                <th>Водитель</th>
                <th>Статус</th>
                <th>Документы</th>
                <th>Tax</th>
                <th>Машина</th>
                <th>Рейтинг</th>
                <th>Заказы</th>
                <th class="num">Баланс</th>
                <th>Последняя активность</th>
                <th>Действия</th>
              </tr>
            </thead>
            <tbody>${rowsHtml}</tbody>
          </table>
        </div>
      </div>`;
    slot.querySelectorAll('tbody tr').forEach(tr => {
      tr.onclick = (e) => {
        if (e.target.closest('[data-drv-copy]') || e.target.closest('[data-action="open-driver"]')) return;
        const key = tr.dataset.key;
        const rec = findRecordByKey(key);
        if (rec) openDriverDrawer(rec);
      };
    });
    slot.querySelectorAll('[data-action="open-driver"]').forEach(b => {
      b.onclick = (e) => {
        e.stopPropagation();
        const rec = findRecordByKey(b.dataset.key);
        if (rec) openDriverDrawer(rec);
      };
    });
    slot.querySelectorAll('[data-drv-copy]').forEach(b => {
      b.onclick = (e) => { e.stopPropagation(); copyToClipboard(b.dataset.drvCopy); };
    });
  }

  function recordKey(r) { return r.driver_id || r.user_id || r.phone || ''; }
  function findRecordByKey(key) { return records.find(r => recordKey(r) === key); }

  function driverTableRow(r) {
    const key = recordKey(r);
    const eff = effectiveDriverStatus(r);
    const v = r.verification;
    const phone = r.phone || (v && v.phone) || '';
    const name = r.full_name || (v && v.driver_name) || '—';
    const plate = (v && v.plate) || '—';
    const vehicle = (v && v.vehicle) || '—';
    const vtype = (v && v.vehicle_type) || '—';
    const stars = v && v.stars > 0 ? v.stars.toFixed(2) : '—';
    const ordersCount = r.orders_count || (v && v.orders) || 0;
    const w = r.wallet;
    return `
      <tr data-key="${escapeHtml(key)}">
        <td>
          <div class="ord-cell-primary">${escapeHtml(name)}</div>
          <div class="ord-cell-mono">${escapeHtml(phone || '—')}</div>
          <div class="ord-cell-mono">${shortId(r.driver_id || r.user_id)}</div>
        </td>
        <td>${driverStatusBadge(eff)}</td>
        <td>${documentsBadge(v && v.status)}</td>
        <td>${taxBadge(r.tax && r.tax.verification_status)}</td>
        <td>
          <div class="ord-cell-primary">${escapeHtml(plate)}</div>
          <div class="ord-cell-mono">${escapeHtml(vehicle)} · ${escapeHtml(vtype)}</div>
        </td>
        <td>
          <div class="ord-cell-primary">${stars}</div>
          <div class="ord-cell-mono">${formatBigInt(ordersCount)} закз.</div>
        </td>
        <td>
          ${r.active_order_id ? `<div class="ord-cell-primary mono">${shortId(r.active_order_id)}</div><div class="ord-cell-mono">актив.</div>` : `<div class="ord-cell-mono">—</div>`}
        </td>
        <td class="num">
          ${w ? `<div class="ord-cell-primary">${formatMoneyMinor(w.available)}</div>
            <div class="ord-cell-mono">pending ${formatMoneyMinor(w.pending)} · debt ${formatMoneyMinor(w.debt)}</div>` : `<div class="ord-cell-mono">—</div>`}
        </td>
        <td class="ord-cell-mono">${r.online ? escapeHtml(timeAgo(r.online.last_seen)) : '—'}</td>
        <td class="ord-cell-actions">
          <button class="btn btn-ghost btn-sm" data-action="open-driver" data-key="${escapeHtml(key)}">Открыть</button>
          <button class="ord-icon-btn" data-drv-copy="${escapeHtml(r.driver_id || r.user_id)}" title="Скопировать ID">${icon('file-text','w-3 h-3')}</button>
        </td>
      </tr>`;
  }

  /* ---- Map view ---- */
  function teardownMap() {
    if (driversPageState.autoRefreshId) {
      clearInterval(driversPageState.autoRefreshId);
      driversPageState.autoRefreshId = null;
    }
    if (driversPageState.map) {
      try { driversPageState.map.remove(); } catch (_) {}
      driversPageState.map = null;
      driversPageState.markersLayer = null;
      driversPageState.markersById = new Map();
    }
  }

  function renderMapView() {
    const slot = $('#drv-view-slot', main);
    slot.innerHTML = `
      <div class="drv-map-card">
        <div class="drv-map-toolbar">
          <div class="drv-map-legend">
            <span class="drv-legend-item"><span class="drv-legend-dot is-free"></span>Свободен</span>
            <span class="drv-legend-item"><span class="drv-legend-dot is-busy"></span>На заказе</span>
            <span class="drv-legend-item"><span class="drv-legend-dot is-stale"></span>Stale</span>
            <span class="drv-legend-item"><span class="drv-legend-dot is-blocked"></span>Заблокирован</span>
          </div>
          <div class="drv-map-controls">
            <label class="drv-checkbox"><input type="checkbox" id="drv-map-stale" ${state.filters.showStale === false ? '' : 'checked'} /><span>Показывать stale</span></label>
            <label class="drv-checkbox"><input type="checkbox" id="drv-map-auto" /><span>Авто-обновление 10с</span></label>
            <button class="btn btn-ghost btn-sm" id="drv-map-fit">${icon('map-pin','w-3 h-3')} Все водители</button>
            <button class="btn btn-secondary btn-sm" id="drv-map-refresh">${icon('refresh-cw','w-3 h-3')} Обновить</button>
          </div>
        </div>
        <div id="drv-map" class="drv-map-canvas"></div>
        <div id="drv-map-empty" class="drv-map-empty" style="display:none;">
          ${icon('users','state-icon')}
          <div class="dash-empty-title">Нет водителей на линии</div>
          <div class="dash-empty-sub">Online-водители появятся, когда выйдут в смену.</div>
        </div>
      </div>`;

    if (typeof L === 'undefined') {
      slot.innerHTML = `<div class="dash-card"><div class="dash-empty">
        ${icon('alert-triangle','state-icon')}
        <div class="dash-empty-title">Карта недоступна</div>
        <div class="dash-empty-sub">Не удалось загрузить Leaflet с CDN. Проверьте сеть.</div>
      </div></div>`;
      return;
    }

    const mapEl = $('#drv-map', main);
    const map = L.map(mapEl, { zoomControl: true, preferCanvas: true }).setView([55.751244, 37.618423], 5);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap',
    }).addTo(map);
    const markersLayer = L.layerGroup().addTo(map);
    driversPageState.map = map;
    driversPageState.markersLayer = markersLayer;
    driversPageState.markersById = new Map();

    drawMarkers();

    $('#drv-map-fit', main).onclick = () => fitAll();
    $('#drv-map-refresh', main).onclick = () => loadAll();
    $('#drv-map-stale', main).onchange = (e) => {
      state.filters.showStale = e.target.checked;
      drawMarkers();
    };
    $('#drv-map-auto', main).onchange = (e) => {
      if (driversPageState.autoRefreshId) {
        clearInterval(driversPageState.autoRefreshId);
        driversPageState.autoRefreshId = null;
      }
      if (e.target.checked) {
        driversPageState.autoRefreshId = setInterval(async () => {
          const o = await safeGet('online', '/api/v1/admin/drivers-online', { limit: 200 });
          sources.online = (o && o.items) || [];
          records = mergeDriversData(sources);
          refreshHeaderPills();
          refreshKpi();
          drawMarkers();
        }, 10000);
      }
    };

    // Schedule fit after layout settles (Leaflet quirk inside flex containers).
    setTimeout(() => { try { map.invalidateSize(); fitAll(); } catch (_) {} }, 60);
  }

  function classifyMarker(rec) {
    if (effectiveDriverStatus(rec) === 'blocked') return 'is-blocked';
    if (isStale(rec.online && rec.online.last_seen)) return 'is-stale';
    if (isBusyStatus(rec.online && rec.online.status)) return 'is-busy';
    return 'is-free';
  }

  function buildIcon(cls) {
    return L.divIcon({
      className: 'drv-marker',
      html: `<div class="drv-pin ${cls}"><div class="drv-pin-dot"></div></div>`,
      iconSize: [28, 28],
      iconAnchor: [14, 14],
    });
  }

  function popupHtml(rec) {
    const v = rec.verification;
    const o = rec.online || {};
    return `<div class="drv-popup">
      <div class="drv-popup-title">${escapeHtml(rec.full_name || (v && v.driver_name) || '—')}</div>
      <div class="drv-popup-row"><span>Телефон</span><span class="mono">${escapeHtml(rec.phone || '—')}</span></div>
      <div class="drv-popup-row"><span>Номер машины</span><span>${escapeHtml((v && v.plate) || '—')}</span></div>
      <div class="drv-popup-row"><span>Модель</span><span>${escapeHtml((v && v.vehicle) || '—')}</span></div>
      <div class="drv-popup-row"><span>Статус</span><span>${driverStatusBadge(effectiveDriverStatus(rec))}</span></div>
      <div class="drv-popup-row"><span>Текущий заказ</span><span class="mono">${rec.active_order_id ? shortId(rec.active_order_id) : '—'}</span></div>
      <div class="drv-popup-row"><span>Обновлено</span><span>${escapeHtml(timeAgo(o.last_seen))}</span></div>
      <div class="drv-popup-row"><span>Координаты</span><span class="mono">${(typeof o.lat === 'number' ? o.lat.toFixed(5) : '—')}, ${(typeof o.lng === 'number' ? o.lng.toFixed(5) : '—')}</span></div>
      <div class="drv-popup-actions">
        <button class="btn btn-primary btn-sm" data-drv-popup-key="${escapeHtml(recordKey(rec))}">Открыть профиль</button>
      </div>
    </div>`;
  }

  function drawMarkers() {
    if (!driversPageState.map || !driversPageState.markersLayer) return;
    driversPageState.markersLayer.clearLayers();
    driversPageState.markersById.clear();

    const showStale = state.filters.showStale !== false;
    const online = records.filter(r => r.online && typeof r.online.lat === 'number' && typeof r.online.lng === 'number');
    const visible = online.filter(r => showStale || !isStale(r.online.last_seen));

    const emptyEl = $('#drv-map-empty', main);
    if (visible.length === 0) {
      if (emptyEl) emptyEl.style.display = 'flex';
      return;
    } else {
      if (emptyEl) emptyEl.style.display = 'none';
    }

    for (const r of visible) {
      const cls = classifyMarker(r);
      const m = L.marker([r.online.lat, r.online.lng], { icon: buildIcon(cls) });
      m.bindPopup(popupHtml(r), { maxWidth: 280 });
      m.on('popupopen', () => {
        const popup = m.getPopup();
        if (!popup) return;
        const el = popup.getElement();
        if (!el) return;
        const btn = el.querySelector('[data-drv-popup-key]');
        if (btn) btn.onclick = () => {
          const rec = findRecordByKey(btn.dataset.drvPopupKey);
          if (rec) openDriverDrawer(rec);
        };
      });
      m.addTo(driversPageState.markersLayer);
      driversPageState.markersById.set(recordKey(r), m);
    }
  }

  function fitAll() {
    if (!driversPageState.map || driversPageState.markersById.size === 0) return;
    const bounds = L.latLngBounds(Array.from(driversPageState.markersById.values()).map(m => m.getLatLng()));
    driversPageState.map.fitBounds(bounds.pad(0.2), { animate: true });
  }

  /* ---- Lifecycle ---- */
  driversPageState.unmount = () => {
    teardownMap();
    if (driversPageState.autoRefreshId) {
      clearInterval(driversPageState.autoRefreshId);
      driversPageState.autoRefreshId = null;
    }
  };

  // Watch for route change to cleanup.
  const cleanupRouteWatch = () => {
    if (state.filters && document.body.getAttribute('data-route') !== 'drivers') {
      if (driversPageState.unmount) driversPageState.unmount();
      driversPageState.unmount = null;
      window.removeEventListener('hashchange', cleanupRouteWatch);
    }
  };
  window.addEventListener('hashchange', cleanupRouteWatch);

  await loadAll();
}

/* Driver details drawer */
function driverDrawerSection(title, iconName, body) {
  return `<section class="ord-section">
    <div class="ord-section-head">
      <div class="ord-section-title">${icon(iconName,'kpi-icon')}<span>${escapeHtml(title)}</span></div>
    </div>
    <div class="ord-section-body">${body}</div>
  </section>`;
}

function openDriverDrawer(rec) {
  const v = rec.verification || null;
  const o = rec.online || null;
  const w = rec.wallet || null;
  const driverId = rec.driver_id || '';
  const userId = rec.user_id || '';
  const phone = rec.phone || (v && v.phone) || '';
  const name = rec.full_name || (v && v.driver_name) || '—';

  const head = `<div class="ord-drawer-head">
    <div>
      <div class="ord-drawer-id">${escapeHtml(name)}</div>
      <div class="ord-drawer-sub">
        ${driverStatusBadge(effectiveDriverStatus(rec))}
        <span class="ord-cell-mono" style="margin-left:8px;">${escapeHtml(phone || '—')}</span>
      </div>
    </div>
    <div style="display:flex; gap:6px;">
      ${driverId ? `<button class="btn btn-secondary btn-sm" data-drv-copy="${escapeHtml(driverId)}">${icon('file-text','w-3 h-3')} Copy ID</button>` : ''}
      ${phone ? `<button class="btn btn-secondary btn-sm" data-drv-copy="${escapeHtml(phone)}">${icon('file-text','w-3 h-3')} Copy phone</button>` : ''}
    </div>
  </div>`;

  const profile = `<div class="ord-kv">
    <div class="ord-kv-row"><div class="ord-kv-k">Имя</div><div class="ord-kv-v">${escapeHtml(name)}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Телефон</div><div class="ord-kv-v mono">${escapeHtml(phone || '—')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">User ID</div><div class="ord-kv-v mono">${escapeHtml(userId || '—')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Driver ID</div><div class="ord-kv-v mono">${escapeHtml(driverId || '—')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Город</div><div class="ord-kv-v">${escapeHtml((v && v.city) || '—')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Заявка подана</div><div class="ord-kv-v">${formatDate(v && v.submitted_at)}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Последняя активность</div><div class="ord-kv-v">${o ? escapeHtml(timeAgo(o.last_seen)) + ' · ' + formatDate(o.last_seen) : '—'}</div></div>
  </div>`;

  const vehicle = v ? `<div class="ord-kv">
    <div class="ord-kv-row"><div class="ord-kv-k">Номер машины</div><div class="ord-kv-v">${escapeHtml(v.plate || '—')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Модель</div><div class="ord-kv-v">${escapeHtml(v.vehicle || '—')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Тип техники</div><div class="ord-kv-v">${escapeHtml(v.vehicle_type || '—')}</div></div>
  </div>` : `<div class="ord-empty-section">Машина не привязана</div>`;

  const docs = v ? `<div class="ord-kv">
    <div class="ord-kv-row"><div class="ord-kv-k">Статус</div><div class="ord-kv-v">${documentsBadge(v.status)}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Risk</div><div class="ord-kv-v">${escapeHtml(v.risk || '—')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Сигналы</div><div class="ord-kv-v">${(v.signals && v.signals.length) ? v.signals.map(s => `<span class="badge badge-muted">${escapeHtml(s)}</span>`).join(' ') : '—'}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Документы</div><div class="ord-kv-v">${(v.documents && v.documents.length) ? v.documents.map(d => `<a class="drv-doc-link" href="${escapeHtml(d)}" target="_blank" rel="noopener">Документ</a>`).join(' · ') : '—'}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Причина модерации</div><div class="ord-kv-v">${escapeHtml((v.decision_reason || '') || '—')}</div></div>
  </div>` : `<div class="ord-empty-section">Заявка на верификацию не подана</div>`;

  const tax = `<div class="ord-empty-section">Источник данных недоступен · endpoint <code>/admin/tax-profiles</code> отсутствует</div>`;

  const wallet = w ? `<div class="ord-kv">
    <div class="ord-kv-row"><div class="ord-kv-k">Available balance</div><div class="ord-kv-v num">${formatMoneyMinor(w.available)}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Pending balance</div><div class="ord-kv-v num">${formatMoneyMinor(w.pending)}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Расчёты с Tow Truck</div><div class="ord-kv-v num">${formatMoneyMinor(w.debt)}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Валюта</div><div class="ord-kv-v">${escapeHtml(w.currency || 'RUB')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Обновлён</div><div class="ord-kv-v">${formatDate(w.updated_at)}</div></div>
  </div>` : `<div class="ord-empty-section">Кошелёк не найден</div>`;

  const orders = `<div class="ord-kv">
    <div class="ord-kv-row"><div class="ord-kv-k">Активный заказ</div><div class="ord-kv-v mono">${rec.active_order_id ? `<a href="#/orders" data-drv-goto-order="${escapeHtml(rec.active_order_id)}">${shortId(rec.active_order_id)}</a>` : '—'}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Всего заказов</div><div class="ord-kv-v">${formatBigInt(rec.orders_count || (v && v.orders) || 0)}</div></div>
  </div>
  ${driverId ? `<div style="margin-top:8px;"><button class="btn btn-ghost btn-sm" data-drv-orders="${escapeHtml(driverId)}">Открыть заказы водителя →</button></div>` : ''}`;

  const location = o ? `<div class="ord-kv">
    <div class="ord-kv-row"><div class="ord-kv-k">Lat</div><div class="ord-kv-v mono">${(typeof o.lat === 'number' ? o.lat.toFixed(5) : '—')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Lng</div><div class="ord-kv-v mono">${(typeof o.lng === 'number' ? o.lng.toFixed(5) : '—')}</div></div>
    <div class="ord-kv-row"><div class="ord-kv-k">Последнее обновление</div><div class="ord-kv-v">${escapeHtml(timeAgo(o.last_seen))} · ${formatDate(o.last_seen)}</div></div>
  </div>
  <div style="margin-top:8px;"><button class="btn btn-ghost btn-sm" data-drv-show-map="${escapeHtml(recordKey(rec))}">Показать на карте →</button></div>` : `<div class="ord-empty-section">Водитель не в сети</div>`;

  const body = `${head}
    ${driverDrawerSection('Профиль','user',profile)}
    ${driverDrawerSection('Машина','inbox',vehicle)}
    ${driverDrawerSection('Документы','file-text',docs)}
    ${driverDrawerSection('Налоги','receipt',tax)}
    ${driverDrawerSection('Кошелёк','wallet',wallet)}
    ${driverDrawerSection('Заказы','shopping-cart',orders)}
    ${driverDrawerSection('Геолокация','map-pin',location)}
  `;

  openDrawer('Водитель · ' + shortId(driverId || userId || phone), body);

  document.querySelectorAll('#drawer-root [data-drv-copy]').forEach(b => {
    b.onclick = () => copyToClipboard(b.dataset.drvCopy);
  });
  document.querySelectorAll('#drawer-root [data-drv-orders]').forEach(b => {
    b.onclick = () => {
      // Pre-seed the global app filters consumed by pageOrders.
      state.filters = state.filters || {};
      state.filters.orders = Object.assign({}, state.filters.orders || {}, { driver_id: b.dataset.drvOrders, limit: 50, offset: 0 });
      closeDrawer();
      navigate('#/orders');
    };
  });
  document.querySelectorAll('#drawer-root [data-drv-show-map]').forEach(b => {
    b.onclick = () => {
      driversPageState.filters.view = 'map';
      try { localStorage.setItem(DRIVERS_VIEW_KEY, 'map'); } catch (_) {}
      closeDrawer();
      navigate('#/drivers');
      setTimeout(() => {
        const m = driversPageState.markersById && driversPageState.markersById.get(b.dataset.drvShowMap);
        if (m && driversPageState.map) {
          driversPageState.map.setView(m.getLatLng(), 14);
          m.openPopup();
        }
      }, 400);
    };
  });
  document.querySelectorAll('#drawer-root [data-drv-goto-order]').forEach(a => {
    a.onclick = (e) => {
      e.preventDefault();
      closeDrawer();
      navigate('#/orders');
      setTimeout(() => openOrderDrawer(a.dataset.drvGotoOrder), 200);
    };
  });
}

/* ---------- 7.4 Documents / Moderation ---------- */
async function pageDocuments(main) {
  main.innerHTML = LoadingState();
  try {
    const data = await api.get('/api/v1/admin/driver-verifications', { query: { limit: 100 } });
    const items = data.items || [];
    if (items.length === 0) { main.innerHTML = EmptyState('Нет заявок на верификацию'); return; }
    main.innerHTML = `<div class="table-wrap glass">
      <div class="table-header">
        <h3>${svgIcon('file-text')} Документы на модерации</h3>
        <div class="table-meta">Всего заявок: ${items.length}</div>
      </div>
      <table class="glass-table">
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
    <button class="btn btn-success" id="vbtn-approve">Одобрить</button>
    <button class="btn btn-warning" id="vbtn-changes">Запросить правки</button>
    <button class="btn btn-danger"  id="vbtn-reject">Отклонить</button>
    <button class="btn btn-danger"  id="vbtn-block">Заблокировать</button>`;
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
    <div class="service-areas-layout">
      <div class="service-areas-header glass">
        <div class="header-content">
          <div class="header-title">
            ${svgIcon('map-pin')}
            <h1>Сервисные зоны</h1>
          </div>
          <p class="header-description">Управление зонами обслуживания и проверка покрытия</p>
        </div>
        <div class="header-actions">
          <button class="btn btn-secondary" id="sa-add-focus">
            ${svgIcon('plus')}
            Добавить зону
          </button>
        </div>
      </div>

      <div class="service-areas-grid">
        <div class="card glass zones-management">
          <div class="card-header">
            <div class="card-title">
              ${svgIcon('list')}
              Управление зонами
            </div>
          </div>
          <div class="card-body">
            <div class="add-city-form">
              <div class="form-group">
                <label>Название города</label>
                <input id="sa-city-name" type="text" placeholder="Махачкала" />
              </div>
              <button class="btn btn-primary" id="sa-city-add">
                ${svgIcon('plus')}
                Добавить город
              </button>
              <p class="muted">Координаты определяются автоматически через Nominatim (OpenStreetMap).</p>
            </div>
            <div id="sa-city-list"></div>
          </div>
        </div>

        <div class="card glass point-checker">
          <div class="card-header">
            <div class="card-title">
              ${svgIcon('search')}
              Проверка покрытия
            </div>
          </div>
          <div class="card-body">
            <div class="check-form">
              <div class="coordinate-inputs">
                <div class="form-group">
                  <label>Широта (Latitude)</label>
                  <input name="lat" type="number" step="0.0001" placeholder="55.7558" />
                </div>
                <div class="form-group">
                  <label>Долгота (Longitude)</label>
                  <input name="lng" type="number" step="0.0001" placeholder="37.6173" />
                </div>
              </div>
              <button class="btn btn-primary" id="sa-check">
                ${svgIcon('map-pin')}
                Проверить точку
              </button>
            </div>
            <div id="sa-result"></div>
          </div>
        </div>
      </div>
    </div>`;
  $('#sa-check').onclick = async () => {
    const lat = $('[name="lat"]', main).value;
    const lng = $('[name="lng"]', main).value;
    if (!lat || !lng) { toast('Укажите lat и lng', 'warning'); return; }
    const res = $('#sa-result');
    res.innerHTML = LoadingState('Проверяем покрытие...');
    try {
      const r = await api.get('/api/v1/service-areas/check', { query: { lat, lng } });
      const isInServiceArea = r.allowed;
      const areaName = r.service_area && r.service_area.name ? r.service_area.name : null;
      res.innerHTML = `
        <div class="check-result glass ${isInServiceArea ? 'success' : 'warning'}">
          <div class="result-header">
            ${isInServiceArea ? svgIcon('check-circle') : svgIcon('alert-circle')}
            <h4>${isInServiceArea ? 'Точка в зоне обслуживания' : 'Точка вне зоны обслуживания'}</h4>
          </div>
          <div class="result-details">
            <div class="coordinate-display">
              <span class="label">Координаты:</span>
              <span class="value">${lat}, ${lng}</span>
            </div>
            ${areaName ? `
              <div class="coordinate-display">
                <span class="label">Зона обслуживания:</span>
                <span class="value">${escapeHtml(areaName)}</span>
              </div>
            ` : ''}
          </div>
          <div class="result-raw">
            <details>
              <summary>Подробная информация</summary>
              <pre class="json-display">${escapeHtml(JSON.stringify(r, null, 2))}</pre>
            </details>
          </div>
        </div>`;
    } catch (e) { res.innerHTML = ErrorState(e.message); }
  };

  // ----- City (service area) management -----
  const cityList = $('#sa-city-list', main);

  async function loadCities() {
    cityList.innerHTML = LoadingState('Загрузка городов...');
    try {
      const data = await api.get('/api/v1/admin/cities');
      const cities = (data && data.cities) || [];
      if (cities.length === 0) { cityList.innerHTML = EmptyState('Города ещё не добавлены'); return; }
      cityList.innerHTML = `<div class="table-wrap"><table>
        <thead><tr><th>Город</th><th>slug</th><th>Статус</th><th></th></tr></thead>
        <tbody>${cities.map(c => `<tr class="no-hover">
          <td>${escapeHtml(c.name)}</td>
          <td>${escapeHtml(c.slug || '—')}</td>
          <td>${c.is_active ? 'Активна' : 'Отключена'}</td>
          <td>
            <button class="btn btn-secondary" data-city-toggle="${escapeHtml(c.id)}" data-active="${c.is_active}">${c.is_active ? 'Отключить' : 'Включить'}</button>
            <button class="btn btn-danger" data-city-del="${escapeHtml(c.id)}">Удалить</button>
          </td></tr>`).join('')}</tbody>
      </table></div>`;

      cityList.querySelectorAll('[data-city-toggle]').forEach(btn => {
        btn.onclick = async () => {
          const id = btn.dataset.cityToggle;
          const next = btn.dataset.active !== 'true';
          try { await api.patch(`/api/v1/admin/cities/${encodeURIComponent(id)}`, { is_active: next }); toast('Статус обновлён', 'success'); loadCities(); }
          catch (e) { toast(e.message, 'error'); }
        };
      });
      cityList.querySelectorAll('[data-city-del]').forEach(btn => {
        btn.onclick = async () => {
          const id = btn.dataset.cityDel;
          if (!confirm('Удалить город?')) return;
          try { await api.del(`/api/v1/admin/cities/${encodeURIComponent(id)}`); toast('Город удалён', 'success'); loadCities(); }
          catch (e) { toast(e.message, 'error'); }
        };
      });
    } catch (e) { cityList.innerHTML = ErrorState(e.message); }
  }

  $('#sa-add-focus').onclick = () => { const i = $('#sa-city-name', main); if (i) i.focus(); };

  $('#sa-city-add').onclick = async () => {
    const input = $('#sa-city-name', main);
    const name = (input.value || '').trim();
    if (!name) { toast('Укажите название города', 'warning'); return; }
    const btn = $('#sa-city-add');
    btn.disabled = true;
    try {
      await api.post('/api/v1/admin/cities', { name });
      toast('Город добавлен', 'success');
      input.value = '';
      loadCities();
    } catch (e) { toast(e.message, 'error'); }
    finally { btn.disabled = false; }
  };

  loadCities();
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
        <button class="btn btn-success" id="po-appr">Одобрить</button>
        <button class="btn btn-danger"  id="po-rej">Отклонить</button>
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
    <div class="filter-bar glass">
      <div class="filter-header">
        ${svgIcon('filter')}
        <span>Фильтры возвратов</span>
      </div>
      <div class="filter-content">
        <div class="form-group"><label>Статус</label><input name="status" /></div>
        <div class="form-group"><label>Payment ID</label><input name="payment_id" /></div>
        <div class="form-group"><label>Order ID</label><input name="order_id" /></div>
        <div class="form-group"><label>С</label><input name="from" type="date" /></div>
        <div class="form-group"><label>По</label><input name="to" type="date" /></div>
        <div class="filter-actions">
          <button class="btn btn-primary" id="rf-apply">
            ${svgIcon('search')}
            Применить
          </button>
          <button class="btn btn-secondary" id="rf-new">
            ${svgIcon('plus')}
            Создать возврат
          </button>
        </div>
      </div>
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
        <button class="btn btn-secondary" id="rp-dl">Скачать CSV</button>
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
    <div class="filter-bar glass">
      <div class="filter-header">
        ${svgIcon('filter')}
        <span>Фильтры пользователей</span>
      </div>
      <div class="filter-content">
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
    if (rows.length === 0) { tbl.innerHTML = `<div class="table-wrap glass">${EmptyState('Пользователи не найдены')}</div>`; return; }
    tbl.innerHTML = `<div class="table-wrap glass">
      <div class="table-header">
        <h3>${svgIcon('users')} Пользователи</h3>
        <div class="table-meta">Найдено: ${rows.length} из ${all.length}</div>
      </div>
      <table class="glass-table">
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
  const main = $('.main-content');
  if (!main) return;
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

// Alias used throughout pages; defers to icon() defined below.
function svgIcon(name, className = 'nav-item-icon') { return icon(name, className); }

// Icon helper function for Lucide icons
function icon(name, className = 'nav-item-icon') {
  const icons = {
    'dashboard': '<path d="M3 3h7v9H3zm11 0h7v5h-7zm0 9h7v5h-7zM3 16h7v5H3z"/>',
    'shopping-cart': '<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 0 0 2 1.61h9.72a2 2 0 0 0 2-1.61L23 6H6"/>',
    'users': '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    'file-text': '<path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14,2 14,8 20,8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><line x1="10" y1="9" x2="8" y2="9"/>',
    'receipt': '<path d="M4 2v20l4-4 4 4 4-4 4 4V2H4z"/>',
    'map': '<polygon points="1,6 1,22 8,18 16,22 23,18 23,2 16,6 8,2"/>',
    'credit-card': '<rect x="1" y="4" width="22" height="16" rx="2" ry="2"/><line x1="1" y1="10" x2="23" y2="10"/>',
    'trending-down': '<polyline points="23,18 13.5,8.5 8.5,13.5 1,6"/><polyline points="17,18 23,18 23,12"/>',
    'wallet': '<path d="M21 12V7a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v5m18 0v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-5m18 0H3m12 3h.01"/>',
    'arrow-up-down': '<path d="M21 16V8a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2z"/><polyline points="7,10 12,15 17,10"/>',
    'repeat': '<path d="m17 1 4 4-4 4"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><path d="m7 23-4-4 4-4"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>',
    'rotate-ccw': '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>',
    'bar-chart': '<line x1="12" y1="20" x2="12" y2="10"/><line x1="18" y1="20" x2="18" y2="4"/><line x1="6" y1="20" x2="6" y2="16"/>',
    'star': '<polygon points="12,2 15.09,8.26 22,9.27 17,14.14 18.18,21.02 12,17.77 5.82,21.02 7,14.14 2,9.27 8.91,8.26"/>',
    'user': '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
    'map-pin': '<path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/>',
    'settings': '<circle cx="12" cy="12" r="3"/><path d="M12 1v6m0 6v6m11-7h-6m-6 0H1m15.5-3.5L19 9l-4.5-4.5M4.5 15.5L9 19l-4.5-4.5"/>',
    'refresh-cw': '<path d="m3 12 3-3 3 3"/><path d="M6 9V2a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v7"/><path d="m15 12 3 3-3 3"/><path d="M18 15v7a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2v-7"/>',
    'log-out': '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16,17 21,12 16,7"/><line x1="21" y1="12" x2="9" y2="12"/>',
    'moon': '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>',
    'sun': '<circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>',
    'inbox': '<polyline points="22,12 16,12 14,15 10,15 8,12 2,12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
    'alert-triangle': '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="m12 17 .01 0"/>',
    'code': '<polyline points="16,18 22,12 16,6"/><polyline points="8,6 2,12 8,18"/>',
    'trending-up': '<polyline points="23,6 13.5,15.5 8.5,10.5 1,18"/><polyline points="17,6 23,6 23,12"/>',
    'dollar-sign': '<line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>',
    'clock': '<circle cx="12" cy="12" r="10"/><polyline points="12,6 12,12 16,14"/>',
  };
  return `<svg class="${className}" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24">${icons[name] || ''}</svg>`;
}

function renderShell() {
  const groups = {};
  for (const r of ROUTES) {
    (groups[r.group] = groups[r.group] || []).push(r);
  }

  const routeIcons = {
    'dashboard': 'dashboard',
    'orders': 'shopping-cart',
    'drivers': 'users',
    'documents': 'file-text',
    'tax-profiles': 'receipt',
    'service-areas': 'map',
    'payments': 'credit-card',
    'payouts': 'trending-down',
    'wallets': 'wallet',
    'transactions': 'arrow-up-down',
    'subscriptions': 'repeat',
    'refunds': 'rotate-ccw',
    'reports': 'bar-chart',
    'reviews': 'star',
    'users': 'user',
    'online-map': 'map-pin',
    'settings': 'settings'
  };

  const groupHtml = Object.entries(groups).map(([g, items]) => `
    <div class="nav-section">
      <div class="nav-section-title">${escapeHtml(g)}</div>
      ${items.map(r => `<button class="nav-item ${state.route.name === r.id ? 'active' : ''}" data-route="${r.id}">
        ${icon(routeIcons[r.id] || 'file-text')}
        ${escapeHtml(r.title)}
      </button>`).join('')}
    </div>`).join('');

  const title = (ROUTES.find(r => r.id === state.route.name) || ROUTES[0]).title;
  const isDark = document.body.getAttribute('data-theme') === 'dark';
  document.body.setAttribute('data-route', state.route.name);

  $('#app').innerHTML = `
    <div class="app-layout">
      <aside class="sidebar glass">
        <div class="brand">
          <div class="brand-logo">T</div>
          <div class="brand-text">
            <div class="brand-title">Tow Truck</div>
            <div class="brand-subtitle">Admin Panel</div>
          </div>
        </div>
        ${groupHtml}
      </aside>
      <header class="header">
        <div class="header-left">
          <h1 class="page-title">${escapeHtml(title)}</h1>
          <p class="page-subtitle">Управление платформой</p>
        </div>
        <div class="header-right">
          <div class="header-status" id="backend-status">
            <div class="status-dot"></div>
            <span>Сервер</span>
          </div>
          <button class="btn btn-ghost btn-sm" id="theme-btn">
            ${isDark ? icon('sun', 'w-4 h-4') : icon('moon', 'w-4 h-4')}
          </button>
          <button class="btn btn-secondary btn-sm" id="refresh-btn">
            ${icon('refresh-cw', 'w-4 h-4')}
            Обновить
          </button>
          <button class="btn btn-ghost btn-sm" id="logout-btn">
            ${icon('log-out', 'w-4 h-4')}
            Выйти
          </button>
        </div>
      </header>
      <main class="main-content"></main>
    </div>`;

  // Event listeners
  $$('.nav-item').forEach(item => {
    item.onclick = (e) => {
      e.preventDefault();
      navigate('#/' + item.dataset.route);
    };
  });

  $('#refresh-btn').onclick = () => renderApp();
  $('#logout-btn').onclick = () => logout();
  $('#theme-btn').onclick = toggleTheme;
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
