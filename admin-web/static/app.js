const state = {
  activeTab: "dashboard",
  moderationFilter: "all",
  selectedCaseId: null,
  config: null,
  source: "loading",
  overview: null,
  overviewError: null,
  verifications: [],
  users: [],
  reviews: [],
  onlineDrivers: [],
  recentOrders: [],
  recentPayments: [],
  recentPayouts: [],
  recentErrors: { orders: null, payments: null, payouts: null },
  charts: { gmv: null, commission: null },

  driversFilters: { search: "", presence: "all", verification: "all", blocked: "all" },
  documentsFilters: { search: "", status: "all", risk: "all" },

  // Phase 4 — Orders
  orders: [],
  ordersTotal: 0,
  ordersError: null,
  ordersLoading: false,
  ordersFilters: {
    search: "",
    status: "all",
    payment_method: "all",
    financial_status: "all",
    from: "",
    to: "",
    page: 1,
  },

  // Phase 4 — Payments (rows from finance report)
  payments: [],
  paymentsError: null,
  paymentsLoading: false,
  paymentsFilters: {
    search: "",
    status: "all",
    purpose: "all",
    payment_method: "all",
    from: "",
    to: "",
    page: 1,
  },

  // Phase 5 — Payouts (rows from finance report)
  payouts: [],
  payoutsError: null,
  payoutsLoading: false,
  payoutsFilters: { search: "", status: "all", from: "", to: "", page: 1 },

  // Phase 5 — Wallets (rows from finance report)
  wallets: [],
  walletsError: null,
  walletsLoading: false,
  walletsFilters: { search: "", debt: "all", page: 1 },

  // Phase 5 — Wallet transactions (rows from finance report)
  transactions: [],
  transactionsError: null,
  transactionsLoading: false,
  transactionsFilters: {
    search: "",
    type: "all",
    direction: "all",
    status: "all",
    from: "",
    to: "",
    page: 1,
  },
};

const ADMIN_PAGE_SIZE = 25;

const pageMeta = {
  dashboard: ["Дашборд", "KPI, обороты и операционный статус EVIK"],
  drivers: ["Водители", "Список, фильтры, документы, кошельки и выплаты"],
  documents: ["Документы", "Модерация документов водителей"],
  orders: ["Заказы", "Все заказы платформы с финансовой разбивкой"],
  payments: ["Платежи", "Платежи клиентов через провайдеров"],
  payouts: ["Выплаты", "Выплаты водителям и расчёты"],
  wallets: ["Кошельки", "Балансы водителей и расчёты с Tow Truck"],
  transactions: ["Транзакции", "История транзакций кошельков"],
  subscriptions: ["Подписки", "Подписки водителей"],
  refunds: ["Возвраты", "Возвраты по платежам"],
  reports: ["Отчёты", "Выгрузка финансовых отчётов"],
  moderation: ["Модерация", "Проверка водителей, документов и рисков"],
  users: ["Пользователи", "Клиенты, водители, блокировки и активность"],
  reviews: ["Отзывы", "Оценки клиентов и звезды водителей"],
  map: ["Карта водителей", "Водители онлайн и на смене"],
  settings: ["Настройки", "Подключение локального сайта к серверу приложения"],
};

const sectionsComingSoon = {
  subscriptions: "Раздел подписок будет подключён на следующем этапе.",
  refunds: "Раздел возвратов будет подключён на следующем этапе.",
  reports: "Раздел отчётов будет подключён на следующем этапе.",
};

const tokenStorageKey = "evik_admin_access_token";
const apiUrlStorageKey = "evik_admin_api_url";
const promapsKeyStorageKey = "evik_promaps_api_key";
const adminUserIDStorageKey = "evik_admin_user_id";
const promapsMapInstances = new Map();
const towTruckIcon = "images/vehicles/truck.png";
const towTruckLoadedIcon = "images/vehicles/truck_loaded.png";
const mapLibreScriptUrl = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js";
const mapLibreCssUrl = "https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css";
let mapLibreLoadPromise = null;

// Функции для иконок водителей
function getDriverStatusColor(status) {
  switch (status) {
    case 'online': return '#10b981'; // Зеленый - свободен
    case 'busy': return '#3b82f6'; // Синий - везет клиента
    case 'to_pickup': return '#10b981'; // Зеленый - едет к клиенту
    case 'to_destination': return '#3b82f6'; // Синий - везет машину
    default: return '#f59e0b'; // Оранжевый - ожидает
  }
}

function getDriverIconPath(status) {
  return status === "busy" || status === "to_destination"
    ? towTruckLoadedIcon
    : towTruckIcon;
}

window.addEventListener("error", (event) => {
  const message = event?.message || "JavaScript error";
  console.error(message, event?.error);
  showToast(`Ошибка интерфейса: ${message}`);
});

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initAdminWeb);
} else {
  initAdminWeb();
}

async function initAdminWeb() {
  bindNavigation();
  bindSettings();
  bindRefresh();
  setTab(state.activeTab);
  await loadConfig();
  await loadAll();
}

function bindNavigation() {
  document.addEventListener("click", (event) => {
    const navButton = event.target.closest(".nav-item[data-tab]");
    if (navButton) {
      event.preventDefault();
      setTab(navButton.dataset.tab);
      return;
    }

    const tabLink = event.target.closest("[data-tab-link]");
    if (tabLink) {
      event.preventDefault();
      setTab(tabLink.dataset.tabLink);
      return;
    }

    const segmentButton = event.target.closest(".segment[data-filter]");
    if (segmentButton) {
      event.preventDefault();
      state.moderationFilter = segmentButton.dataset.filter;
      document.querySelectorAll(".segment").forEach((item) => item.classList.remove("active"));
      segmentButton.classList.add("active");
      renderModeration();
    }
  });

  document.getElementById("users-search")?.addEventListener("input", renderUsers);
}

function bindSettings() {
  document.getElementById("login-admin-button")?.addEventListener("click", loginAdmin);

  document.getElementById("save-settings-button")?.addEventListener("click", async () => {
    const apiUrl = document.getElementById("api-url-input").value.trim();
    const token = document.getElementById("admin-token-input").value.trim();
    const promapsKey = document.getElementById("promaps-key-input").value.trim();
    const adminUserID = document.getElementById("admin-user-id-input").value.trim();

    if (apiUrl) localStorage.setItem(apiUrlStorageKey, apiUrl.replace(/\/$/, ""));
    if (token) localStorage.setItem(tokenStorageKey, token.replace(/^Bearer\s+/i, ""));
    if (promapsKey) localStorage.setItem(promapsKeyStorageKey, promapsKey);
    if (adminUserID) localStorage.setItem(adminUserIDStorageKey, adminUserID);

    showToast("Настройки сохранены. Обновляю данные.");
    await loadConfig();
    await loadAll();
  });

  document.getElementById("clear-token-button")?.addEventListener("click", async () => {
    localStorage.removeItem(tokenStorageKey);
    document.getElementById("admin-token-input").value = "";
    showToast("Токен очищен.");
    await loadAll();
  });
}

function bindRefresh() {
  document.getElementById("refresh-button")?.addEventListener("click", loadAll);
}

async function loadConfig() {
  const response = await fetch("/admin-api/config");
  state.config = await response.json();

  const savedUrl = localStorage.getItem(apiUrlStorageKey);
  if (savedUrl && !savedUrl.includes("localhost") && !savedUrl.includes("127.0.0.1")) {
    state.config.api_base_url = savedUrl;
  }
  const savedPromapsKey = localStorage.getItem(promapsKeyStorageKey);
  if (savedPromapsKey) {
    state.config.promaps_api_key = savedPromapsKey;
  } else {
    // Default ProMaps key
    state.config.promaps_api_key = "pk_live_d44618284239626c98dc23cd909b2b6eff001df7cdecbc5";
  }

  document.getElementById("api-base-label").textContent = state.config.api_base_url;
  document.getElementById("api-url-input").value = state.config.api_base_url;
  document.getElementById("admin-token-input").value = localStorage.getItem(tokenStorageKey) || "";
  document.getElementById("admin-user-id-input").value = localStorage.getItem(adminUserIDStorageKey) || "admin";
  document.getElementById("promaps-key-input").value = state.config.promaps_api_key || "";
}

async function loginAdmin() {
  const adminUserID = document.getElementById("admin-user-id-input").value.trim() || "admin";
  const password = document.getElementById("admin-password-input").value;
  if (!password) {
    showToast("Введите admin password из ADMIN_PASSWORD.");
    return;
  }
  localStorage.setItem(adminUserIDStorageKey, adminUserID);

  try {
    const response = await fetch("/api/v1/auth/admin/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...backendTargetHeaders(),
      },
      body: JSON.stringify({
        user_id: adminUserID,
        password,
      }),
    });
    if (!response.ok) throw new Error(`API ${response.status}`);
    const payload = await response.json();
    const token = payload?.tokens?.access_token;
    if (!token) throw new Error("access token missing");
    localStorage.setItem(tokenStorageKey, token);
    document.getElementById("admin-token-input").value = token;
    showToast("Admin token получен. Загружаю реальные данные.");
    await loadAll();
  } catch (error) {
    console.error("admin login failed", error);
    showToast("Не удалось войти как admin. Проверьте backend URL.");
  }
}

async function loadAll() {
  setSource("loading");

  const [
    overview,
    verifications,
    users,
    reviews,
    onlineDrivers,
    recentOrders,
    recentPayments,
    recentPayouts,
  ] = await Promise.all([
    getAdminData("overview"),
    getAdminData("driver-verifications"),
    getAdminData("users"),
    getAdminData("reviews"),
    getAdminData("drivers-online"),
    getAdminPath("/api/v1/admin/orders?limit=5"),
    getAdminPath("/api/v1/admin/finance/payments"),
    getAdminPath("/api/v1/admin/finance/payouts"),
  ]);

  state.overview = normalizeOverview(overview.data);
  state.overviewError = overview.source === "error" ? overview.error || new Error("overview unavailable") : null;
  state.verifications = normalizeItems(verifications.data);
  state.users = normalizeItems(users.data);
  state.reviews = normalizeItems(reviews.data);
  state.onlineDrivers = normalizeItems(onlineDrivers.data);

  state.recentOrders = recentOrders.source === "api" ? (recentOrders.data?.items ?? []).slice(0, 5) : [];
  state.recentErrors.orders = recentOrders.source === "error" ? recentOrders.error : null;

  state.recentPayments = recentPayments.source === "api" ? rowsToObjects(recentPayments.data?.rows).slice(0, 5) : [];
  state.recentErrors.payments = recentPayments.source === "error" ? recentPayments.error : null;

  state.recentPayouts = recentPayouts.source === "api" ? rowsToObjects(recentPayouts.data?.rows).slice(0, 5) : [];
  state.recentErrors.payouts = recentPayouts.source === "error" ? recentPayouts.error : null;

  const anyError = [overview, verifications, users, reviews, onlineDrivers, recentOrders, recentPayments, recentPayouts]
    .some((item) => item.source === "error");
  state.source = anyError ? "error" : "api";

  if (!state.selectedCaseId && state.verifications.length > 0) {
    state.selectedCaseId = state.verifications[0].id;
  }

  setSource(state.source);
  renderAll();
}

/**
 * rowsToObjects converts the `{ rows: [["col1","col2",...], [...], ...] }`
 * shape returned by AdminFinanceReport into a list of {col: value} objects.
 * First row is treated as the header.
 */
function rowsToObjects(rows) {
  if (!Array.isArray(rows) || rows.length < 2) return [];
  const header = rows[0];
  const out = [];
  for (let i = 1; i < rows.length; i += 1) {
    const row = rows[i];
    if (!Array.isArray(row)) continue;
    const obj = {};
    for (let j = 0; j < header.length; j += 1) {
      obj[header[j]] = row[j];
    }
    out.push(obj);
  }
  return out;
}

async function getAdminData(resource) {
  return getAdminPath(`/api/v1/admin/${resource}`);
}

async function getAdminPath(path) {
  try {
    const response = await fetch(path, { headers: authHeaders() });
    if (!response.ok) throw new Error(`API ${response.status}`);
    return { source: "api", data: await response.json() };
  } catch (error) {
    console.error(`Admin API failed for ${path}`, error);
    return { source: "error", data: emptyAdminPayloadFor(path), error };
  }
}

function emptyAdminPayloadFor(path) {
  if (path.endsWith("/overview")) return {};
  if (path.includes("/finance/")) return { rows: [] };
  return { items: [] };
}

function authHeaders() {
  const token = localStorage.getItem(tokenStorageKey);
  const headers = backendTargetHeaders();
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

function backendTargetHeaders() {
  const headers = {};
  if (state.config?.api_base_url) headers["X-Evik-Api-Base-Url"] = state.config.api_base_url;
  return headers;
}

function normalizeOverview(data) {
  return data || {};
}

function normalizeItems(data) {
  if (Array.isArray(data)) return data;
  if (Array.isArray(data?.items)) return data.items;
  if (Array.isArray(data?.drivers)) return data.drivers;
  if (Array.isArray(data?.users)) return data.users;
  if (Array.isArray(data?.reviews)) return data.reviews;
  return [];
}

function renderAll() {
  renderOverview();
  renderModeration();
  renderUsers();
  renderReviews();
  renderDriverMaps();
  renderDrivers();
  renderDocuments();
  renderOrders();
  renderPayments();
  renderPayouts();
  renderWallets();
  renderTransactions();
}

function setTab(tab) {
  if (!pageMeta[tab]) return;

  state.activeTab = tab;
  document.querySelectorAll(".nav-item").forEach((item) => {
    item.classList.toggle("active", item.dataset.tab === tab);
  });
  document.querySelectorAll(".tab-panel").forEach((panel) => {
    panel.classList.toggle("active", panel.id === `tab-${tab}`);
  });

  const [title, subtitle] = pageMeta[tab];
  document.getElementById("page-title").textContent = title;
  document.getElementById("page-subtitle").textContent = subtitle;

  if (tab === "map" || tab === "dashboard") {
    window.setTimeout(renderDriverMaps, 80);
  }

  if (sectionsComingSoon[tab]) {
    renderComingSoon(tab);
  }

  if (tab === "orders") {
    if (state.orders.length === 0 && !state.ordersLoading) loadOrders();
    renderOrders();
  }
  if (tab === "payments") {
    if (state.payments.length === 0 && !state.paymentsLoading) loadPayments();
    renderPayments();
  }
  if (tab === "payouts") {
    if (state.payouts.length === 0 && !state.payoutsLoading) loadPayouts();
    renderPayouts();
  }
  if (tab === "wallets") {
    if (state.wallets.length === 0 && !state.walletsLoading) loadWallets();
    renderWallets();
  }
  if (tab === "transactions") {
    if (state.transactions.length === 0 && !state.transactionsLoading) loadTransactions();
    renderTransactions();
  }
}

function setSource(source) {
  const pill = document.getElementById("data-source-pill");
  pill.classList.remove("error", "ok", "loading");
  if (source === "loading") {
    pill.textContent = "Проверка API";
    pill.classList.add("loading");
    return;
  }
  if (source === "error") {
    pill.textContent = "Ошибка API";
    pill.classList.add("error");
    return;
  }
  pill.textContent = "API подключён";
  pill.classList.add("ok");
}

function renderOverview() {
  const overview = state.overview || {};
  renderDashboardState();
  renderKPICards(overview);
  renderDashboardCharts(overview);
  renderRecentOrders();
  renderRecentPayments();
  renderRecentPayouts();

  document.getElementById("pending-count-label").textContent = `${pendingCount()} в очереди`;
  document.getElementById("online-count-label").textContent = `${state.onlineDrivers.length} на смене`;
  document.getElementById("dashboard-moderation-list").innerHTML = state.verifications
    .slice(0, 4)
    .map(renderCaseCard)
    .join("") || empty("Заявок нет");

  renderMap(document.getElementById("dashboard-mini-map"), state.onlineDrivers, false);
}

function renderDashboardState() {
  const slot = document.getElementById("dashboard-state");
  if (!slot) return;
  if (state.overviewError) {
    slot.innerHTML = renderErrorState({
      message: "Не удалось получить /admin/overview. KPI и графики недоступны.",
      retryId: "dashboard-retry",
    });
    slot.querySelector("[data-retry]")?.addEventListener("click", () => loadAll());
    return;
  }
  slot.innerHTML = "";
}

// KPI cards — 11 metrics per spec. Money values come from backend in kopecks.
function renderKPICards(overview) {
  const cards = [
    { title: "Оборот (GMV) сегодня",        value: formatMoney(overview.gmv_today, { minor: true }),
      sub: `за месяц: ${formatMoney(overview.gmv_month, { minor: true })}`, tone: "primary" },
    { title: "Комиссия Tow Truck сегодня",  value: formatMoney(overview.commission_today, { minor: true }),
      sub: `за месяц: ${formatMoney(overview.commission_month, { minor: true })}`, tone: "accent" },
    { title: "Выплаты водителям сегодня",   value: formatMoney(overview.payouts_today, { minor: true }),
      sub: `за месяц: ${formatMoney(overview.payouts_month, { minor: true })}`, tone: "info" },
    { title: "Ожидают выплаты",             value: formatMoney(overview.payouts_pending, { minor: true }),
      sub: "Created / processing / manual review", tone: "warn" },
    { title: "Failed payments",             value: numberOr(overview.failed_payments),
      sub: "За всё время", tone: "danger" },
    { title: "Failed payouts",              value: numberOr(overview.failed_payouts),
      sub: "За всё время", tone: "danger" },
    { title: "Активные водители",           value: numberOr(overview.active_drivers),
      sub: "Status: online / busy", tone: "ok" },
    { title: "Водители онлайн",             value: numberOr(overview.online_drivers),
      sub: `Активных заказов: ${numberOr(overview.active_orders)}`, tone: "ok" },
    { title: "Ожидают модерации",           value: numberOr(overview.pending_verifications ?? overview.pending_moderations),
      sub: "Документы водителей", tone: "warn" },
    { title: "Доход от подписок",           value: formatMoney(overview.subscriptions_revenue_month, { minor: true }),
      sub: `сегодня: ${formatMoney(overview.subscriptions_revenue_today, { minor: true })}`, tone: "primary" },
    { title: "Удержания по наличным",       value: formatMoney(overview.cash_debt_total, { minor: true }),
      sub: "Расчёты с Tow Truck", tone: "neutral" },
  ];

  document.getElementById("overview-metrics").innerHTML = cards
    .map((c) => `
      <article class="kpi-card kpi-${escapeAttr(c.tone)}">
        <div class="kpi-title">${escapeHtml(c.title)}</div>
        <div class="kpi-value">${escapeHtml(c.value)}</div>
        <div class="kpi-sub">${escapeHtml(c.sub)}</div>
      </article>
    `).join("");
}

function numberOr(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n.toLocaleString("ru-RU") : "—";
}

// --- Chart.js: GMV and commission by day ----------------------------------

function renderDashboardCharts(overview) {
  renderDailySeriesChart({
    canvasId: "chart-gmv",
    emptyId: "chart-gmv-empty",
    totalLabelId: "gmv-total-label",
    chartKey: "gmv",
    label: "GMV, ₽",
    color: { line: "#34d399", fill: "rgba(52,211,153,0.14)" },
    series: overview.gmv_by_day,
  });
  renderDailySeriesChart({
    canvasId: "chart-commission",
    emptyId: "chart-commission-empty",
    totalLabelId: "commission-total-label",
    chartKey: "commission",
    label: "Комиссия, ₽",
    color: { line: "#fbbf24", fill: "rgba(251,191,36,0.14)" },
    series: overview.commission_by_day,
  });
}

function renderDailySeriesChart({ canvasId, emptyId, totalLabelId, chartKey, label, color, series }) {
  const canvas = document.getElementById(canvasId);
  const emptyEl = document.getElementById(emptyId);
  const totalLabel = document.getElementById(totalLabelId);
  if (!canvas || typeof window.Chart === "undefined") {
    if (emptyEl) {
      emptyEl.hidden = false;
      emptyEl.innerHTML = renderEmptyState("График недоступен", "Chart.js не загружен");
    }
    return;
  }

  const points = Array.isArray(series) ? series : [];
  if (totalLabel) {
    const total = points.reduce((acc, p) => acc + (Number(p?.amount) || 0), 0);
    totalLabel.textContent = `за 30 дней: ${formatMoney(total, { minor: true })}`;
  }

  if (points.length === 0) {
    canvas.hidden = true;
    if (emptyEl) {
      emptyEl.hidden = false;
      emptyEl.innerHTML = renderEmptyState("Нет данных за период");
    }
    if (state.charts[chartKey]) {
      state.charts[chartKey].destroy();
      state.charts[chartKey] = null;
    }
    return;
  }

  canvas.hidden = false;
  if (emptyEl) emptyEl.hidden = true;

  const labels = points.map((p) => formatChartDate(p.date));
  const data = points.map((p) => (Number(p?.amount) || 0) / 100); // kopecks → rubles

  if (state.charts[chartKey]) {
    state.charts[chartKey].data.labels = labels;
    state.charts[chartKey].data.datasets[0].data = data;
    state.charts[chartKey].update();
    return;
  }

  state.charts[chartKey] = new window.Chart(canvas.getContext("2d"), {
    type: "line",
    data: {
      labels,
      datasets: [{
        label,
        data,
        borderColor: color.line,
        backgroundColor: color.fill,
        fill: true,
        tension: 0.3,
        pointRadius: 0,
        pointHoverRadius: 4,
        borderWidth: 2,
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: "rgba(16,16,20,0.95)",
          borderColor: "rgba(255,255,255,0.12)",
          borderWidth: 1,
          padding: 10,
          callbacks: {
            label: (ctx) => ` ${label}: ${formatMoney(ctx.parsed.y)}`,
          },
        },
      },
      scales: {
        x: {
          grid: { color: "rgba(255,255,255,0.04)" },
          ticks: { color: "#9b9ba4", maxRotation: 0, autoSkip: true, maxTicksLimit: 8 },
        },
        y: {
          grid: { color: "rgba(255,255,255,0.06)" },
          ticks: {
            color: "#9b9ba4",
            callback: (value) => formatCompactRub(value),
          },
          beginAtZero: true,
        },
      },
    },
  });
}

function formatChartDate(iso) {
  if (!iso) return "";
  const d = new Date(iso + "T00:00:00Z");
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString("ru-RU", { day: "2-digit", month: "2-digit" });
}

function formatCompactRub(value) {
  const n = Number(value) || 0;
  if (Math.abs(n) >= 1_000_000) return `${(n / 1_000_000).toFixed(1)} млн ₽`;
  if (Math.abs(n) >= 1_000) return `${Math.round(n / 1000)} тыс ₽`;
  return `${Math.round(n)} ₽`;
}

// --- Recent activity panels -----------------------------------------------

function renderRecentOrders() {
  const el = document.getElementById("dashboard-recent-orders");
  if (!el) return;
  if (state.recentErrors.orders) {
    el.innerHTML = renderErrorState({ message: "Не удалось получить заказы", retryId: "recent-orders-retry" });
    el.querySelector("[data-retry]")?.addEventListener("click", () => loadAll());
    return;
  }
  if (state.recentOrders.length === 0) {
    el.innerHTML = renderEmptyState("Заказов нет");
    return;
  }
  el.innerHTML = state.recentOrders.map((order) => `
    <article class="compact-row">
      <div class="compact-row-main">
        <div class="compact-row-title">
          <strong>${escapeHtml(order.client_name || order.client_id || "—")}</strong>
          <span class="muted">→ ${escapeHtml(order.driver_name || order.driver_id || "без водителя")}</span>
        </div>
        <div class="compact-row-meta muted">
          ${escapeHtml(order.order_id)} ${copyButton(order.order_id, { title: "Скопировать ID заказа" })}
          · ${escapeHtml(formatDate(order.created_at))}
        </div>
      </div>
      <div class="compact-row-aside">
        <div class="compact-row-amount">${escapeHtml(formatMoney(order.price_total, { minor: true }))}</div>
        ${statusBadge(order.status)}
      </div>
    </article>
  `).join("");
}

function renderRecentPayments() {
  const el = document.getElementById("dashboard-recent-payments");
  if (!el) return;
  if (state.recentErrors.payments) {
    el.innerHTML = renderErrorState({ message: "Не удалось получить платежи", retryId: "recent-payments-retry" });
    el.querySelector("[data-retry]")?.addEventListener("click", () => loadAll());
    return;
  }
  if (state.recentPayments.length === 0) {
    el.innerHTML = renderEmptyState("Платежей нет");
    return;
  }
  // payments columns: id, order_id, user_id, provider, provider_payment_id, payment_method, purpose, amount, currency, status, created_at
  el.innerHTML = state.recentPayments.map((p) => `
    <article class="compact-row">
      <div class="compact-row-main">
        <div class="compact-row-title">
          <strong>${escapeHtml(p.payment_method || "—")}</strong>
          <span class="muted">${escapeHtml(p.purpose || "")}</span>
        </div>
        <div class="compact-row-meta muted">
          ${escapeHtml(p.id || "")} ${copyButton(p.id || "", { title: "Скопировать ID платежа" })}
          · ${escapeHtml(formatDate(p.created_at))}
        </div>
      </div>
      <div class="compact-row-aside">
        <div class="compact-row-amount">${escapeHtml(formatMoney(p.amount, { minor: true }))}</div>
        ${statusBadge(p.status)}
      </div>
    </article>
  `).join("");
}

function renderRecentPayouts() {
  const el = document.getElementById("dashboard-recent-payouts");
  if (!el) return;
  if (state.recentErrors.payouts) {
    el.innerHTML = renderErrorState({ message: "Не удалось получить выплаты", retryId: "recent-payouts-retry" });
    el.querySelector("[data-retry]")?.addEventListener("click", () => loadAll());
    return;
  }
  if (state.recentPayouts.length === 0) {
    el.innerHTML = renderEmptyState("Выплат нет");
    return;
  }
  // payouts columns: id, driver_id, amount, currency, status, provider_payout_id, created_at
  el.innerHTML = state.recentPayouts.map((p) => `
    <article class="compact-row">
      <div class="compact-row-main">
        <div class="compact-row-title">
          <strong>${escapeHtml(p.driver_id || "—")}</strong>
        </div>
        <div class="compact-row-meta muted">
          ${escapeHtml(p.id || "")} ${copyButton(p.id || "", { title: "Скопировать ID выплаты" })}
          · ${escapeHtml(formatDate(p.created_at))}
        </div>
      </div>
      <div class="compact-row-aside">
        <div class="compact-row-amount">${escapeHtml(formatMoney(p.amount, { minor: true }))}</div>
        ${statusBadge(p.status)}
      </div>
    </article>
  `).join("");
}

function renderModeration() {
  const items = filteredVerifications();
  const list = document.getElementById("moderation-list");
  list.innerHTML = items.map(renderCaseCard).join("") || empty("В этом фильтре заявок нет");

  list.querySelectorAll(".case-card").forEach((card) => {
    card.addEventListener("click", () => {
      state.selectedCaseId = card.dataset.id;
      renderModeration();
    });
  });

  const selected = state.verifications.find((item) => item.id === state.selectedCaseId) || items[0] || state.verifications[0];
  if (selected) state.selectedCaseId = selected.id;
  renderModerationDetail(selected);
}

function filteredVerifications() {
  if (state.moderationFilter === "pending") return state.verifications.filter((item) => item.status === "pending");
  if (state.moderationFilter === "high") return state.verifications.filter((item) => item.risk === "high");
  if (state.moderationFilter === "reviewed") return state.verifications.filter((item) => item.status !== "pending");
  return state.verifications;
}

function renderCaseCard(item) {
  const selectedClass = item.id === state.selectedCaseId ? " selected" : "";
  return `
    <button class="case-card${selectedClass}" data-id="${escapeAttr(item.id)}" type="button">
      <div class="card-row">
        <span class="card-title">${escapeHtml(item.driver_name || item.driverName || "Без имени")}</span>
        ${pill(item.risk || "low", riskLabel(item.risk))}
      </div>
      <div class="card-meta">${escapeHtml(item.vehicle || "")} · ${escapeHtml(item.plate || "")}</div>
      <div class="card-footer">
        ${pill(item.status || "pending", statusLabel(item.status))}
        <span class="muted">${ageLabel(item.submitted_at)}</span>
      </div>
    </button>
  `;
}

function renderModerationDetail(item) {
  const panel = document.getElementById("moderation-detail");
  if (!item) {
    panel.innerHTML = empty("Выберите заявку");
    return;
  }

  const documents = Array.isArray(item.documents) ? item.documents : [];
  const signals = Array.isArray(item.signals) ? item.signals : [];
  const canAct = item.status === "pending";

  panel.innerHTML = `
    <div class="panel-header">
      <div>
        <h2>${escapeHtml(item.id)}</h2>
        <div class="muted">${escapeHtml(item.driver_name || "Без имени")}</div>
      </div>
      <div class="card-row">
        ${pill(item.status, statusLabel(item.status))}
        ${pill(item.risk, riskLabel(item.risk))}
      </div>
    </div>
    <div class="detail-content">
      <section>
        <h3>Водитель</h3>
        <div class="info-grid">
          ${infoCell("ФИО", item.driver_name)}
          ${infoCell("Телефон", item.phone)}
          ${infoCell("Город", item.city)}
          ${infoCell("Рейтинг", `${formatStarsValue(item.stars)} · ${item.orders || 0} заказов`)}
          ${infoCell("Авто", item.vehicle)}
          ${infoCell("Госномер", item.plate)}
        </div>
      </section>
      <section>
        <h3>Документы</h3>
        <div class="document-list">
          ${documents.map((doc) => `<div class="document-item"><span class="doc-badge">DOC</span><strong>${escapeHtml(doc)}</strong><span class="muted">Проверить оригинал</span></div>`).join("") || empty("Документы не переданы")}
        </div>
      </section>
      <section>
        <h3>Риск-сигналы</h3>
        <div class="signal-list">
          ${signals.map((signal) => `<div class="signal-item"><span>RISK</span>${escapeHtml(signal)}</div>`).join("") || `<div class="muted">Критичных сигналов нет.</div>`}
        </div>
      </section>
    </div>
    <div class="action-bar">
      <button class="secondary-button" data-action="request-changes" ${canAct ? "" : "disabled"}>Запросить правки</button>
      <button class="secondary-button" data-action="reject" ${canAct ? "" : "disabled"}>Отклонить</button>
      <button class="danger-button" data-action="block" ${canAct ? "" : "disabled"}>Заблокировать</button>
      <button class="primary-button" data-action="approve" ${canAct ? "" : "disabled"}>Одобрить</button>
    </div>
  `;

  panel.querySelectorAll("[data-action]").forEach((button) => {
    button.addEventListener("click", () => moderateCase(item.id, button.dataset.action));
  });
}

async function moderateCase(id, action) {
  let reason = "";
  if (action !== "approve") {
    reason = window.prompt("Причина решения");
    if (!reason || reason.trim().length < 8) {
      showToast("Нужна понятная причина не короче 8 символов.");
      return;
    }
  }

  const path = `/api/v1/admin/moderation/driver-verifications/${encodeURIComponent(id)}/${action}`;
  try {
    const response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...authHeaders() },
      body: JSON.stringify({ reason }),
    });
    if (!response.ok) throw new Error(`API ${response.status}`);
    showToast("Решение сохранено на сервере.");
    await loadAll();
  } catch (error) {
    console.error("moderation action failed", error);
    showToast("Не удалось сохранить решение. Проверьте подключение к backend.");
  }
}

function renderUsers() {
  const query = document.getElementById("users-search").value.trim().toLowerCase();
  const items = state.users.filter((item) => {
    const haystack = `${item.id} ${item.name} ${item.role} ${item.phone} ${item.status}`.toLowerCase();
    return haystack.includes(query);
  });

  document.getElementById("users-table").innerHTML = items.map((item) => `
    <tr>
      <td>${escapeHtml(item.id)}</td>
      <td>${escapeHtml(item.name)}</td>
      <td>${escapeHtml(roleLabel(item.role))}</td>
      <td>${escapeHtml(item.phone)}</td>
      <td>${escapeHtml(item.orders ?? 0)}</td>
      <td>${pill(item.status, userStatusLabel(item.status))}</td>
    </tr>
  `).join("") || `<tr><td colspan="6">${empty("Пользователи не найдены")}</td></tr>`;
}

function renderReviews() {
  document.getElementById("reviews-list").innerHTML = state.reviews.map((item) => `
    <article class="review-card">
      <div class="card-row">
        <strong>${escapeHtml(item.driver_name)}</strong>
        <span class="stars">${stars(item.stars)}</span>
      </div>
      <div class="muted">Клиент: ${escapeHtml(item.client_name)} · ${ageLabel(item.created_at)}</div>
      <p>${escapeHtml(item.text)}</p>
    </article>
  `).join("") || empty("Отзывов нет");
}

function renderDriverMaps() {
  document.getElementById("map-online-label").textContent = `${state.onlineDrivers.length} водителей`;
  renderMap(document.getElementById("driver-map"), state.onlineDrivers, true);
  document.getElementById("online-drivers-list").innerHTML = state.onlineDrivers.map((driver) => `
    <article class="driver-card">
      <div class="card-row">
        <strong>${escapeHtml(driver.name)}</strong>
        ${pill(driver.status, driverStatusLabel(driver.status))}
      </div>
      <div class="muted">${escapeHtml(driver.vehicle)} · ${formatStarsValue(driver.stars)} ★</div>
      <div class="muted">Последний сигнал: ${ageLabel(driver.last_seen)}</div>
    </article>
  `).join("") || empty("Онлайн-водителей нет");
}

async function renderMap(container, drivers, showLabels) {
  if (!container) return;
  const validDrivers = drivers
    .map((driver) => ({ ...driver, lat: Number(driver.lat), lng: Number(driver.lng) }))
    .filter((driver) => Number.isFinite(driver.lat) && Number.isFinite(driver.lng));

  const apiKey = state.config?.promaps_api_key;
  if (!apiKey) {
    container.innerHTML = `<div class="map-fallback-note">Укажите ProMaps API key в настройках или переменной PROMAPS_API_KEY.</div>`;
    return;
  }

  await renderProMapsMap(container, validDrivers, showLabels, apiKey);
}

async function renderProMapsMap(container, drivers, showLabels, apiKey) {
  const center = drivers.length ? getMapCenter(drivers) : { lat: 55.7558, lng: 37.6173 };
  const zoom = showLabels ? 12 : 10;
  const existing = promapsMapInstances.get(container.id);
  if (existing) existing.remove();

  container.classList.add("promaps-ready");
  const emptyState = drivers.length
    ? ""
    : `<div class="map-empty-state">Нет водителей на смене</div>`;
  const mapCanvasId = `${container.id || "promaps"}-canvas`;

  container.innerHTML = `
    <div class="promaps-container">
      <div class="promaps-map-canvas" id="${escapeAttr(mapCanvasId)}"></div>
      <div class="map-overlay" aria-label="Водители на смене">
        ${emptyState}
      </div>
    </div>
  `;

  try {
    await loadMapLibre();
    const map = new maplibregl.Map({
      container: mapCanvasId,
      style: `https://promaps.online/api/styles/default?key=${encodeURIComponent(apiKey)}`,
      center: [center.lng, center.lat],
      zoom,
      attributionControl: false,
    });

    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    map.addControl(new maplibregl.AttributionControl({ compact: true }), "bottom-right");

    map.on("load", () => {
      drivers.forEach((driver) => {
        new maplibregl.Marker({
          element: createDriverMarkerElement(driver, showLabels),
          anchor: "center",
        })
          .setLngLat([driver.lng, driver.lat])
          .addTo(map);
      });
    });

    map.on("error", (event) => {
      console.error("ProMaps MapLibre error", event?.error || event);
      showMapError(container, "ProMaps не загрузила стиль карты. Проверьте Maps API key.");
    });

    promapsMapInstances.set(container.id, {
      remove: () => {
        map.remove();
        container.innerHTML = "";
        container.classList.remove("promaps-ready");
      },
    });
  } catch (error) {
    console.error("MapLibre failed", error);
    showMapError(container, "Не удалось загрузить MapLibre для ProMaps.");
  }
}

function createDriverMarkerElement(driver, showLabels) {
  const status = driver.status || "online";
  const marker = document.createElement("button");
  marker.className = `driver-map-marker ${status}`;
  marker.type = "button";
  marker.title = driver.vehicle ? `${driver.name} · ${driver.vehicle}` : driver.name || driver.id;
  marker.style.borderColor = getDriverStatusColor(status);
  marker.innerHTML = `
    <img src="${getDriverIconPath(status)}" alt="" />
    ${showLabels ? `<span>${escapeHtml(driver.name || driver.id)}<small>${escapeHtml(driver.vehicle || driver.status || "online")}</small></span>` : ""}
  `;
  return marker;
}

function loadMapLibre() {
  if (window.maplibregl) return Promise.resolve();
  if (mapLibreLoadPromise) return mapLibreLoadPromise;

  mapLibreLoadPromise = new Promise((resolve, reject) => {
    if (!document.querySelector(`link[href="${mapLibreCssUrl}"]`)) {
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = mapLibreCssUrl;
      document.head.appendChild(link);
    }

    const script = document.createElement("script");
    script.src = mapLibreScriptUrl;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error("MapLibre script failed to load"));
    document.head.appendChild(script);
  });

  return mapLibreLoadPromise;
}

function showMapError(container, message) {
  const overlay = container.querySelector(".map-overlay");
  if (!overlay) return;
  overlay.innerHTML = `<div class="map-empty-state">${escapeHtml(message)}</div>`;
}

function getMapCenter(drivers) {
  const sum = drivers.reduce(
    (acc, driver) => {
      acc.lat += driver.lat;
      acc.lng += driver.lng;
      return acc;
    },
    { lat: 0, lng: 0 },
  );
  return { lat: sum.lat / drivers.length, lng: sum.lng / drivers.length };
}

function projectLatLng(lat, lng, center, zoom) {
  const scale = 256 * Math.pow(2, zoom);
  const centerWorld = latLngToWorld(center.lat, center.lng, scale);
  const pointWorld = latLngToWorld(lat, lng, scale);
  const dx = pointWorld.x - centerWorld.x;
  const dy = pointWorld.y - centerWorld.y;
  return {
    x: 50 + (dx / 10),
    y: 50 + (dy / 10),
  };
}

function latLngToWorld(lat, lng, scaleValue) {
  const sinLat = Math.sin((lat * Math.PI) / 180);
  return {
    x: ((lng + 180) / 360) * scaleValue,
    y: (0.5 - Math.log((1 + sinLat) / (1 - sinLat)) / (4 * Math.PI)) * scaleValue,
  };
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function pendingCount() {
  return state.verifications.filter((item) => item.status === "pending").length;
}

function infoCell(label, value) {
  return `<div class="info-cell"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value ?? "—")}</strong></div>`;
}

function pill(kind, label) {
  const normalized = String(kind || "pending").replaceAll("-", "_");
  return `<span class="pill ${escapeAttr(normalized)}">${escapeHtml(label || normalized)}</span>`;
}

function statusLabel(status) {
  return {
    pending: "На проверке",
    approved: "Одобрено",
    rejected: "Отклонено",
    blocked: "Блок",
    changes_requested: "Нужны правки",
  }[status] || "На проверке";
}

function riskLabel(risk) {
  return {
    low: "Низкий риск",
    medium: "Средний риск",
    high: "Высокий риск",
  }[risk] || "Низкий риск";
}

function roleLabel(role) {
  return role === "driver" ? "Водитель" : role === "admin" ? "Админ" : "Клиент";
}

function userStatusLabel(status) {
  return {
    active: "Активен",
    moderation: "Модерация",
    blocked: "Заблокирован",
  }[status] || status || "—";
}

function driverStatusLabel(status) {
  return status === "busy" ? "В заказе" : "Онлайн";
}

function stars(value) {
  const count = Math.max(0, Math.min(5, Number(value) || 0));
  return "★★★★★".slice(0, count) + "☆☆☆☆☆".slice(0, 5 - count);
}

function formatStarsValue(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number.toFixed(1) : "—";
}

function ageLabel(value) {
  if (!value) return "—";
  const date = new Date(value);
  const diff = Date.now() - date.getTime();
  if (!Number.isFinite(diff)) return "—";
  const minutes = Math.max(1, Math.round(diff / 60000));
  if (minutes < 60) return `${minutes} мин назад`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} ч назад`;
  return `${Math.round(hours / 24)} д назад`;
}

function empty(text) {
  return `<div class="empty">${escapeHtml(text)}</div>`;
}

function showToast(message) {
  const toast = document.getElementById("toast");
  toast.textContent = message;
  toast.classList.add("visible");
  window.clearTimeout(showToast.timeout);
  showToast.timeout = window.setTimeout(() => toast.classList.remove("visible"), 3200);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttr(value) {
  return escapeHtml(value).replaceAll("`", "&#096;");
}

// ============================================================================
// Generic UI components (Phase 0)
// ============================================================================

// --- Formatting helpers -----------------------------------------------------

const RUB_FORMATTER = new Intl.NumberFormat("ru-RU", {
  style: "currency",
  currency: "RUB",
  maximumFractionDigits: 2,
});

const DATETIME_FORMATTER = new Intl.DateTimeFormat("ru-RU", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
});

const DATE_FORMATTER = new Intl.DateTimeFormat("ru-RU", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/**
 * Format a value in RUB. Accepts kopecks or rubles; backend stores amounts
 * in minor units (kopecks) for finance entities. Pass {minor:true} to divide
 * by 100 before formatting.
 */
function formatMoney(value, { minor = false, fallback = "—" } = {}) {
  const num = Number(value);
  if (!Number.isFinite(num)) return fallback;
  return RUB_FORMATTER.format(minor ? num / 100 : num);
}

function formatDate(value, { withTime = true, fallback = "—" } = {}) {
  if (!value) return fallback;
  const date = value instanceof Date ? value : new Date(value);
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) return fallback;
  return (withTime ? DATETIME_FORMATTER : DATE_FORMATTER).format(date);
}

function debounce(fn, ms = 200) {
  let timer = null;
  return function debounced(...args) {
    if (timer) window.clearTimeout(timer);
    timer = window.setTimeout(() => fn.apply(this, args), ms);
  };
}

// --- Status badge -----------------------------------------------------------

const STATUS_BADGE_TONES = {
  // payment / payout / refund / verification — semantic mapping
  succeeded: "ok",
  paid: "ok",
  approved: "ok",
  active: "ok",
  online: "ok",
  completed: "ok",
  pending: "info",
  processing: "info",
  searching: "info",
  in_progress: "info",
  moderation: "info",
  changes_requested: "warn",
  expired: "warn",
  hold: "warn",
  failed: "danger",
  rejected: "danger",
  blocked: "danger",
  cancelled: "danger",
  canceled: "danger",
  refunded: "danger",
  busy: "info",
};

const STATUS_BADGE_LABELS = {
  // generic Russian fallback labels
  succeeded: "Успешно",
  paid: "Оплачено",
  approved: "Одобрено",
  active: "Активно",
  online: "Онлайн",
  completed: "Завершено",
  pending: "Ожидает",
  processing: "В обработке",
  searching: "Поиск",
  in_progress: "В работе",
  moderation: "Модерация",
  changes_requested: "Нужны правки",
  expired: "Истекло",
  hold: "Удержание",
  failed: "Ошибка",
  rejected: "Отклонено",
  blocked: "Заблокировано",
  cancelled: "Отменено",
  canceled: "Отменено",
  refunded: "Возврат",
  busy: "В заказе",
};

function statusBadge(status, label) {
  const key = String(status || "").toLowerCase().replaceAll("-", "_");
  const tone = STATUS_BADGE_TONES[key] || "neutral";
  const text = label || STATUS_BADGE_LABELS[key] || (status ?? "—");
  return `<span class="badge badge-${escapeAttr(tone)}">${escapeHtml(text)}</span>`;
}

// --- Copy button ------------------------------------------------------------

function copyButton(value, { title = "Скопировать" } = {}) {
  return `<button class="copy-btn" type="button" data-copy="${escapeAttr(value)}" title="${escapeAttr(title)}" aria-label="${escapeAttr(title)}">
    <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>
  </button>`;
}

document.addEventListener("click", (event) => {
  const btn = event.target.closest("[data-copy]");
  if (!btn) return;
  const value = btn.getAttribute("data-copy");
  if (!value) return;
  if (navigator.clipboard?.writeText) {
    navigator.clipboard.writeText(value).then(
      () => showToast("Скопировано"),
      () => showToast("Не удалось скопировать"),
    );
  } else {
    showToast("Буфер обмена недоступен");
  }
});

// --- Loading / Empty / Error states -----------------------------------------

function renderLoadingState(message = "Загрузка данных…") {
  return `<div class="state state-loading">
    <span class="state-spinner" aria-hidden="true"></span>
    <span>${escapeHtml(message)}</span>
  </div>`;
}

function renderEmptyState(message = "Данных пока нет", hint = "") {
  return `<div class="state state-empty">
    <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18"/></svg>
    <div class="state-title">${escapeHtml(message)}</div>
    ${hint ? `<div class="state-hint">${escapeHtml(hint)}</div>` : ""}
  </div>`;
}

function renderErrorState({ message = "Не удалось загрузить данные", retryId = "" } = {}) {
  return `<div class="state state-error">
    <svg viewBox="0 0 24 24" width="28" height="28" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 8v5"/><circle cx="12" cy="16" r="0.6" fill="currentColor"/></svg>
    <div class="state-title">${escapeHtml(message)}</div>
    ${retryId ? `<button class="secondary-button" type="button" data-retry="${escapeAttr(retryId)}">Повторить</button>` : ""}
  </div>`;
}

// --- DataTable (generic) ----------------------------------------------------

/**
 * Render a generic data table.
 *
 * opts = {
 *   container: HTMLElement,
 *   columns:   [{ key, label, render?(row), align?, sortable? }],
 *   rows:      Array<object>,
 *   state:     "loading" | "empty" | "error" | undefined,
 *   emptyMessage?: string,
 *   errorMessage?: string,
 *   onRetry?:  () => void,
 *   page?:     1-based, pageSize?: number, total?: number,
 *   onPage?:   (page) => void,
 *   onRowClick?: (row) => void,
 *   rowId?:    (row) => string,
 * }
 */
function renderDataTable(opts) {
  const {
    container,
    columns = [],
    rows = [],
    state: tableState,
    emptyMessage = "Данных нет",
    errorMessage = "Не удалось загрузить данные",
    onRetry,
    page = 1,
    pageSize = 20,
    total = rows.length,
    onPage,
    onRowClick,
    rowId,
  } = opts;
  if (!container) return;

  if (tableState === "loading") {
    container.innerHTML = renderLoadingState();
    return;
  }
  if (tableState === "error") {
    container.innerHTML = renderErrorState({ message: errorMessage, retryId: onRetry ? "datatable-retry" : "" });
    if (onRetry) container.querySelector("[data-retry]")?.addEventListener("click", onRetry);
    return;
  }
  if (!rows.length) {
    container.innerHTML = renderEmptyState(emptyMessage);
    return;
  }

  const headHtml = columns
    .map((col) => `<th${col.align ? ` style="text-align:${col.align}"` : ""}>${escapeHtml(col.label || col.key)}</th>`)
    .join("");

  const bodyHtml = rows
    .map((row) => {
      const id = rowId ? rowId(row) : "";
      const cells = columns
        .map((col) => {
          const raw = col.render ? col.render(row) : escapeHtml(row[col.key] ?? "—");
          return `<td${col.align ? ` style="text-align:${col.align}"` : ""}>${raw}</td>`;
        })
        .join("");
      return `<tr${id ? ` data-row-id="${escapeAttr(id)}"` : ""}${onRowClick ? ' class="row-clickable"' : ""}>${cells}</tr>`;
    })
    .join("");

  const totalPages = Math.max(1, Math.ceil(total / pageSize));
  const pagination = totalPages > 1
    ? `<div class="table-pagination">
        <button class="secondary-button" type="button" data-page-prev ${page <= 1 ? "disabled" : ""}>Назад</button>
        <span class="muted">Стр. ${page} из ${totalPages}</span>
        <button class="secondary-button" type="button" data-page-next ${page >= totalPages ? "disabled" : ""}>Вперёд</button>
      </div>`
    : "";

  container.innerHTML = `
    <div class="table-wrap">
      <table class="data-table">
        <thead><tr>${headHtml}</tr></thead>
        <tbody>${bodyHtml}</tbody>
      </table>
    </div>
    ${pagination}
  `;

  if (onPage && totalPages > 1) {
    container.querySelector("[data-page-prev]")?.addEventListener("click", () => onPage(Math.max(1, page - 1)));
    container.querySelector("[data-page-next]")?.addEventListener("click", () => onPage(Math.min(totalPages, page + 1)));
  }

  if (onRowClick && rowId) {
    container.querySelectorAll("tr[data-row-id]").forEach((tr) => {
      tr.addEventListener("click", (event) => {
        if (event.target.closest("button, a, [data-copy]")) return;
        const id = tr.getAttribute("data-row-id");
        const row = rows.find((r) => rowId(r) === id);
        if (row) onRowClick(row);
      });
    });
  }
}

// --- FilterBar (generic) ----------------------------------------------------

/**
 * Render a filter bar.
 *
 * opts = {
 *   container: HTMLElement,
 *   fields: [
 *     { type: "search", key, placeholder?, value? },
 *     { type: "select", key, label?, options: [{ value, label }], value? },
 *     { type: "date-range", keyFrom, keyTo, valueFrom?, valueTo? },
 *   ],
 *   values: { [key]: value },
 *   onChange: (values) => void,
 *   onReset?: () => void,
 * }
 */
function renderFilterBar(opts) {
  const { container, fields = [], values = {}, onChange, onReset } = opts;
  if (!container) return;

  const current = { ...values };
  const emitDebounced = debounce(() => onChange?.({ ...current }), 200);
  const emit = () => onChange?.({ ...current });

  const html = fields
    .map((field) => {
      if (field.type === "search") {
        const v = current[field.key] ?? field.value ?? "";
        return `<label class="filter-field filter-search">
          <span class="visually-hidden">${escapeHtml(field.placeholder || "Поиск")}</span>
          <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>
          <input type="search" data-filter-key="${escapeAttr(field.key)}" placeholder="${escapeAttr(field.placeholder || "Поиск…")}" value="${escapeAttr(v)}" />
        </label>`;
      }
      if (field.type === "select") {
        const v = current[field.key] ?? field.value ?? "";
        const opts = (field.options || [])
          .map((o) => `<option value="${escapeAttr(o.value)}"${String(v) === String(o.value) ? " selected" : ""}>${escapeHtml(o.label)}</option>`)
          .join("");
        return `<label class="filter-field filter-select">
          ${field.label ? `<span class="filter-label">${escapeHtml(field.label)}</span>` : ""}
          <select data-filter-key="${escapeAttr(field.key)}">${opts}</select>
        </label>`;
      }
      if (field.type === "date-range") {
        const vf = current[field.keyFrom] ?? field.valueFrom ?? "";
        const vt = current[field.keyTo] ?? field.valueTo ?? "";
        return `<div class="filter-field filter-date-range">
          ${field.label ? `<span class="filter-label">${escapeHtml(field.label)}</span>` : ""}
          <input type="date" data-filter-key="${escapeAttr(field.keyFrom)}" value="${escapeAttr(vf)}" />
          <span class="muted">—</span>
          <input type="date" data-filter-key="${escapeAttr(field.keyTo)}" value="${escapeAttr(vt)}" />
        </div>`;
      }
      return "";
    })
    .join("");

  container.innerHTML = `
    <div class="filter-bar">
      ${html}
      ${onReset ? `<button class="secondary-button filter-reset" type="button" data-filter-reset>Сбросить</button>` : ""}
    </div>
  `;

  container.querySelectorAll("[data-filter-key]").forEach((input) => {
    const key = input.getAttribute("data-filter-key");
    const handler = () => {
      current[key] = input.value;
      if (input.type === "search") emitDebounced();
      else emit();
    };
    input.addEventListener("input", handler);
    if (input.tagName === "SELECT") input.addEventListener("change", handler);
  });

  if (onReset) {
    container.querySelector("[data-filter-reset]")?.addEventListener("click", () => {
      onReset();
    });
  }
}

// --- DetailDrawer -----------------------------------------------------------

/**
 * Open a right-side drawer with arbitrary HTML content.
 *
 * opts = { title, subtitle?, contentHtml, actionsHtml?, onMount?(drawerEl), onClose?() }
 */
function openDrawer(opts) {
  const { title = "", subtitle = "", contentHtml = "", actionsHtml = "", onMount, onClose } = opts;
  const root = document.getElementById("drawer-root");
  if (!root) return;

  root.setAttribute("aria-hidden", "false");
  root.innerHTML = `
    <div class="drawer-backdrop" data-drawer-close></div>
    <aside class="drawer" role="dialog" aria-modal="true" aria-label="${escapeAttr(title)}">
      <header class="drawer-header">
        <div>
          <h2>${escapeHtml(title)}</h2>
          ${subtitle ? `<p class="muted">${escapeHtml(subtitle)}</p>` : ""}
        </div>
        <button class="icon-button" type="button" data-drawer-close aria-label="Закрыть">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>
        </button>
      </header>
      <div class="drawer-body">${contentHtml}</div>
      ${actionsHtml ? `<footer class="drawer-footer">${actionsHtml}</footer>` : ""}
    </aside>
  `;

  const closeAll = () => {
    root.setAttribute("aria-hidden", "true");
    root.innerHTML = "";
    document.removeEventListener("keydown", escListener);
    onClose?.();
  };

  function escListener(event) {
    if (event.key === "Escape") closeAll();
  }
  document.addEventListener("keydown", escListener);

  root.querySelectorAll("[data-drawer-close]").forEach((el) => {
    el.addEventListener("click", closeAll);
  });

  onMount?.(root.querySelector(".drawer"));
}

function closeDrawer() {
  const root = document.getElementById("drawer-root");
  if (!root) return;
  root.setAttribute("aria-hidden", "true");
  root.innerHTML = "";
}

// --- ConfirmDialog ----------------------------------------------------------

/**
 * Show a modal confirmation dialog. Returns a Promise<boolean>.
 *
 * confirmDialog({ title, message, confirmLabel, cancelLabel, tone: "default"|"danger", requireReason?, reasonLabel? })
 *   → resolves with true (confirmed) or false (cancelled)
 *   → if requireReason, resolves with { confirmed: true, reason: string } | { confirmed: false }
 */
function confirmDialog(opts) {
  return new Promise((resolve) => {
    const {
      title = "Подтвердите действие",
      message = "Продолжить?",
      confirmLabel = "Подтвердить",
      cancelLabel = "Отмена",
      tone = "default",
      requireReason = false,
      reasonLabel = "Причина",
      reasonMinLength = 8,
    } = opts || {};
    const root = document.getElementById("dialog-root");
    if (!root) {
      resolve(requireReason ? { confirmed: false } : false);
      return;
    }
    root.setAttribute("aria-hidden", "false");
    root.innerHTML = `
      <div class="dialog-backdrop" data-dialog-close></div>
      <div class="dialog" role="alertdialog" aria-modal="true" aria-labelledby="dialog-title">
        <h2 id="dialog-title">${escapeHtml(title)}</h2>
        <p class="dialog-message">${escapeHtml(message)}</p>
        ${requireReason ? `<label class="field"><span>${escapeHtml(reasonLabel)}</span><textarea id="dialog-reason" rows="3" placeholder="Минимум ${reasonMinLength} символов"></textarea></label>` : ""}
        <div class="dialog-actions">
          <button class="secondary-button" type="button" data-dialog-cancel>${escapeHtml(cancelLabel)}</button>
          <button class="${tone === "danger" ? "danger-button" : "primary-button"}" type="button" data-dialog-confirm>${escapeHtml(confirmLabel)}</button>
        </div>
      </div>
    `;

    const cleanup = () => {
      root.setAttribute("aria-hidden", "true");
      root.innerHTML = "";
      document.removeEventListener("keydown", keyListener);
    };

    function keyListener(event) {
      if (event.key === "Escape") {
        cleanup();
        resolve(requireReason ? { confirmed: false } : false);
      }
    }
    document.addEventListener("keydown", keyListener);

    root.querySelectorAll("[data-dialog-cancel], [data-dialog-close]").forEach((el) => {
      el.addEventListener("click", () => {
        cleanup();
        resolve(requireReason ? { confirmed: false } : false);
      });
    });

    root.querySelector("[data-dialog-confirm]").addEventListener("click", () => {
      if (requireReason) {
        const reason = root.querySelector("#dialog-reason").value.trim();
        if (reason.length < reasonMinLength) {
          showToast(`Нужна причина не короче ${reasonMinLength} символов.`);
          return;
        }
        cleanup();
        resolve({ confirmed: true, reason });
        return;
      }
      cleanup();
      resolve(true);
    });
  });
}

/**
 * Driver verification approval dialog — collects the vehicle data the admin
 * must enter manually after reviewing photos / documents. Backend requires
 * vehicle_plate / vehicle_model / vehicle_type when status = "approved";
 * see admin_handler.go:decideDriverVerification.
 *
 * Resolves with { confirmed: true, plate, model, type } or { confirmed: false }.
 */
function vehicleApprovalDialog({ driverName = "", verificationID = "" } = {}) {
  return new Promise((resolve) => {
    const root = document.getElementById("dialog-root");
    if (!root) { resolve({ confirmed: false }); return; }
    root.setAttribute("aria-hidden", "false");
    root.innerHTML = `
      <div class="dialog-backdrop" data-dialog-close></div>
      <div class="dialog dialog-form" role="alertdialog" aria-modal="true" aria-labelledby="approval-title">
        <h2 id="approval-title">Одобрить водителя</h2>
        <p class="dialog-message">${escapeHtml(driverName || verificationID)} — введите данные машины. После одобрения водитель получит SMS и сможет подключить «Мой Налог».</p>
        <label class="field">
          <span>Гос. номер</span>
          <input id="approve-plate" type="text" placeholder="A123BC777" autocomplete="off" maxlength="12" />
        </label>
        <label class="field">
          <span>Модель авто</span>
          <input id="approve-model" type="text" placeholder="Газель Next, Ford Transit и т.д." autocomplete="off" maxlength="80" />
        </label>
        <fieldset class="field field-radio-group">
          <legend>Тип эвакуатора</legend>
          <label class="radio-tile">
            <input type="radio" name="approve-type" value="winch" />
            <span class="radio-tile-title">Лебёдка</span>
            <span class="radio-tile-hint">Только лебёдка, без платформы</span>
          </label>
          <label class="radio-tile">
            <input type="radio" name="approve-type" value="platform" />
            <span class="radio-tile-title">Платформа</span>
            <span class="radio-tile-hint">Стандартный эвакуатор-платформа</span>
          </label>
          <label class="radio-tile">
            <input type="radio" name="approve-type" value="manipulator" />
            <span class="radio-tile-title">Манипулятор</span>
            <span class="radio-tile-hint">Со стрелой / краном для тяжёлой техники</span>
          </label>
        </fieldset>
        <div class="dialog-actions">
          <button class="secondary-button" type="button" data-dialog-cancel>Отмена</button>
          <button class="primary-button" type="button" data-dialog-confirm>Одобрить и отправить SMS</button>
        </div>
      </div>
    `;

    const cleanup = () => {
      root.setAttribute("aria-hidden", "true");
      root.innerHTML = "";
      document.removeEventListener("keydown", keyListener);
    };
    function keyListener(event) {
      if (event.key === "Escape") { cleanup(); resolve({ confirmed: false }); }
    }
    document.addEventListener("keydown", keyListener);

    root.querySelectorAll("[data-dialog-cancel], [data-dialog-close]").forEach((el) => {
      el.addEventListener("click", () => { cleanup(); resolve({ confirmed: false }); });
    });

    root.querySelector("[data-dialog-confirm]").addEventListener("click", () => {
      const plate = root.querySelector("#approve-plate").value.trim().toUpperCase();
      const model = root.querySelector("#approve-model").value.trim();
      const typeNode = root.querySelector('input[name="approve-type"]:checked');
      const type = typeNode ? typeNode.value : "";

      if (!plate || plate.length < 4) { showToast("Введите гос. номер машины."); return; }
      if (!model) { showToast("Введите модель авто."); return; }
      if (!type) { showToast("Выберите тип эвакуатора."); return; }
      cleanup();
      resolve({ confirmed: true, plate, model, type });
    });

    root.querySelector("#approve-plate")?.focus();
  });
}

// --- Coming soon placeholder for upcoming sections --------------------------

function renderComingSoon(tab) {
  const section = document.getElementById(`tab-${tab}`);
  if (!section) return;
  const slot = section.querySelector(`[data-section-placeholder="${tab}"]`);
  if (!slot) return;
  const message = sectionsComingSoon[tab] || "Раздел будет подключён на следующем этапе.";
  slot.innerHTML = `
    <section class="panel placeholder-panel">
      ${renderEmptyState(message, "Backend готов — добавим интерфейс на следующей итерации.")}
    </section>
  `;
}

// ============================================================================
// Phase 3 — Drivers + Documents/Moderation
// ============================================================================

// --- Drivers screen --------------------------------------------------------

function buildDriversRows() {
  // Backend /admin/users returns a unified list of drivers + clients. The
  // driver flavor has role === "driver". driver_verifications gives us
  // verification status, full name and phone for verified rows.
  // drivers-online (an aggregate of drivers + last location) tells us who is
  // online and busy right now.
  const onlineByName = new Map();
  for (const driver of state.onlineDrivers) {
    if (driver?.name) onlineByName.set(String(driver.name).toLowerCase(), driver);
  }
  const verificationsByName = new Map();
  for (const verification of state.verifications) {
    const key = String(verification.driver_name || verification.id || "").toLowerCase();
    if (key) verificationsByName.set(key, verification);
  }

  const rows = [];
  for (const user of state.users) {
    if ((user.role || "").toLowerCase() !== "driver") continue;
    const nameKey = String(user.name || "").toLowerCase();
    const verification = verificationsByName.get(nameKey);
    const online = onlineByName.get(nameKey);
    rows.push({
      id: user.id,
      name: user.name,
      phone: user.phone || verification?.phone || "",
      verificationStatus: verification?.status || (user.status === "moderation" ? "pending" : ""),
      vehicle: verification?.vehicle || "",
      plate: verification?.plate || "",
      risk: verification?.risk || "",
      stars: verification?.stars,
      orders: user.orders,
      onlineStatus: online?.status || (user.status === "active" ? "offline" : user.status || ""),
      isOnline: Boolean(online),
      blocked: user.status === "blocked" || verification?.status === "blocked",
      verificationID: verification?.id,
      submittedAt: verification?.submitted_at,
    });
  }
  return rows;
}

function filteredDrivers() {
  const f = state.driversFilters;
  const q = (f.search || "").trim().toLowerCase();
  return buildDriversRows().filter((row) => {
    if (q) {
      const hay = `${row.id} ${row.name} ${row.phone} ${row.plate} ${row.vehicle}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    if (f.presence === "online" && !row.isOnline) return false;
    if (f.presence === "offline" && row.isOnline) return false;
    if (f.verification !== "all" && row.verificationStatus !== f.verification) return false;
    if (f.blocked === "yes" && !row.blocked) return false;
    if (f.blocked === "no" && row.blocked) return false;
    return true;
  });
}

function renderDrivers() {
  const filterHost = document.getElementById("drivers-filters");
  const tableHost = document.getElementById("drivers-table");
  const countLabel = document.getElementById("drivers-count-label");
  if (!filterHost || !tableHost) return;

  renderFilterBar({
    container: filterHost,
    fields: [
      { type: "search", key: "search", placeholder: "Поиск по ФИО, телефону, ID, госномеру", value: state.driversFilters.search },
      {
        type: "select", key: "presence", label: "Статус",
        options: [
          { value: "all", label: "Все" },
          { value: "online", label: "Онлайн" },
          { value: "offline", label: "Оффлайн" },
        ],
        value: state.driversFilters.presence,
      },
      {
        type: "select", key: "verification", label: "Верификация",
        options: [
          { value: "all", label: "Все" },
          { value: "approved", label: "Одобрены" },
          { value: "pending", label: "На модерации" },
          { value: "rejected", label: "Отклонены" },
          { value: "blocked", label: "Заблокированы" },
        ],
        value: state.driversFilters.verification,
      },
      {
        type: "select", key: "blocked", label: "Доступ",
        options: [
          { value: "all", label: "Все" },
          { value: "no", label: "Активные" },
          { value: "yes", label: "Заблокированы" },
        ],
        value: state.driversFilters.blocked,
      },
    ],
    values: state.driversFilters,
    onChange: (values) => {
      state.driversFilters = { ...state.driversFilters, ...values };
      renderDrivers();
    },
    onReset: () => {
      state.driversFilters = { search: "", presence: "all", verification: "all", blocked: "all" };
      renderDrivers();
    },
  });

  if (state.source === "loading") {
    tableHost.innerHTML = renderLoadingState();
    if (countLabel) countLabel.textContent = "—";
    return;
  }

  const rows = filteredDrivers();
  if (countLabel) countLabel.textContent = `${rows.length} водителей`;

  renderDataTable({
    container: tableHost,
    rowId: (row) => row.id,
    onRowClick: (row) => openDriverDrawer(row),
    columns: [
      {
        key: "id", label: "ID",
        render: (r) => `<span class="mono">${escapeHtml(r.id)}</span>${copyButton(r.id, { title: "Скопировать ID" })}`,
      },
      { key: "name", label: "ФИО", render: (r) => escapeHtml(r.name || "—") },
      { key: "phone", label: "Телефон", render: (r) => escapeHtml(r.phone || "—") },
      {
        key: "verification", label: "Верификация",
        render: (r) => r.verificationStatus
          ? statusBadge(r.verificationStatus)
          : `<span class="muted">—</span>`,
      },
      {
        key: "online", label: "Онлайн",
        render: (r) => r.isOnline ? statusBadge(r.onlineStatus || "online") : `<span class="muted">оффлайн</span>`,
      },
      {
        key: "rating", label: "Рейтинг",
        align: "right",
        render: (r) => escapeHtml(formatStarsValue(r.stars)),
      },
      {
        key: "orders", label: "Заказы",
        align: "right",
        render: (r) => escapeHtml(numberOr(r.orders)),
      },
      {
        key: "blocked", label: "Доступ",
        render: (r) => r.blocked
          ? statusBadge("blocked")
          : statusBadge("active"),
      },
    ],
    rows,
    emptyMessage: "Водители не найдены",
  });
}

function openDriverDrawer(driver) {
  const verification = state.verifications.find((v) => v.id === driver.verificationID);
  const online = state.onlineDrivers.find((d) => String(d.name || "").toLowerCase() === String(driver.name || "").toLowerCase());

  const info = `
    <section class="drawer-section">
      <h3>Профиль</h3>
      <dl class="info-list">
        <dt>ID</dt><dd>${escapeHtml(driver.id)}${copyButton(driver.id)}</dd>
        <dt>ФИО</dt><dd>${escapeHtml(driver.name || "—")}</dd>
        <dt>Телефон</dt><dd>${escapeHtml(driver.phone || "—")}</dd>
        <dt>Авто</dt><dd>${escapeHtml(driver.vehicle || "—")} · ${escapeHtml(driver.plate || "—")}</dd>
        <dt>Рейтинг</dt><dd>${escapeHtml(formatStarsValue(driver.stars))} · ${escapeHtml(numberOr(driver.orders))} заказов</dd>
        <dt>Верификация</dt><dd>${driver.verificationStatus ? statusBadge(driver.verificationStatus) : '<span class="muted">не подавал документы</span>'}</dd>
      </dl>
    </section>
    <section class="drawer-section" data-driver-npd>
      <h3>Самозанятость</h3>
      <div class="state state-loading"><span class="state-spinner" aria-hidden="true"></span><span>Загружаем налоговый статус…</span></div>
    </section>
    <section class="drawer-section">
      <h3>Активность</h3>
      <dl class="info-list">
        <dt>Сейчас</dt><dd>${driver.isOnline ? statusBadge(driver.onlineStatus || "online") : '<span class="muted">оффлайн</span>'}</dd>
        ${online?.last_seen ? `<dt>Последний сигнал</dt><dd>${escapeHtml(formatDate(online.last_seen))}</dd>` : ""}
        ${verification?.submitted_at ? `<dt>Заявка подана</dt><dd>${escapeHtml(formatDate(verification.submitted_at))}</dd>` : ""}
      </dl>
    </section>
    <section class="drawer-section">
      <h3>Финансы</h3>
      <p class="muted">Доступный баланс, ожидающий баланс, расчёты с Tow Truck и подписки появятся вместе с разделами «Кошельки» и «Подписки».</p>
    </section>
    ${verification ? `
    <section class="drawer-section">
      <h3>Документы и сигналы</h3>
      <div class="document-list">
        ${(verification.documents || []).map((d) => `<div class="document-item"><span class="doc-badge">DOC</span><strong>${escapeHtml(d)}</strong></div>`).join("") || `<div class="muted">Документы не переданы.</div>`}
      </div>
      ${(verification.signals && verification.signals.length) ? `
        <div class="signal-list" style="margin-top:10px">
          ${verification.signals.map((s) => `<div class="signal-item"><span>!</span>${escapeHtml(s)}</div>`).join("")}
        </div>
      ` : ""}
    </section>
    ` : ""}
  `;

  const canBlock = driver.verificationID && !driver.blocked;
  const canUnblock = driver.verificationID && driver.blocked;

  const actions = `
    <button class="secondary-button" type="button" data-driver-action="open-docs"${driver.verificationID ? "" : " disabled"}>Открыть документы</button>
    ${canBlock ? `<button class="danger-button" type="button" data-driver-action="block">Заблокировать</button>` : ""}
    ${canUnblock ? `<button class="primary-button" type="button" data-driver-action="unblock">Разблокировать</button>` : ""}
    <button class="secondary-button" type="button" data-drawer-close>Закрыть</button>
  `;

  openDrawer({
    title: driver.name || driver.id,
    subtitle: driver.phone || "",
    contentHtml: info,
    actionsHtml: actions,
    onMount: (drawer) => {
      drawer.querySelectorAll("[data-driver-action]").forEach((btn) => {
        btn.addEventListener("click", async () => {
          const action = btn.getAttribute("data-driver-action");
          if (action === "open-docs") {
            closeDrawer();
            setTab("documents");
            return;
          }
          if (action === "block" || action === "unblock") {
            await driverBlockToggle(driver, action);
          }
        });
      });
      loadDriverNPDStatus(driver, drawer);
    },
  });
}

const NPD_STATUS_LABELS = {
  not_connected: "Не подключено",
  connected: "Подключено",
  revoked: "Отозвано",
  error: "Ошибка",
};

async function loadDriverNPDStatus(driver, drawer) {
  const host = drawer.querySelector("[data-driver-npd]");
  if (!host) return;
  const result = await getAdminPath(`/api/v1/drivers/${encodeURIComponent(driver.id)}/npd/status`);
  if (result.source === "error") {
    host.innerHTML = `<h3>Самозанятость</h3>${renderErrorState({
      message: "Не удалось загрузить налоговый статус водителя.",
    })}`;
    return;
  }
  const data = result.data || {};
  const profile = data.profile || data;
  const status = String(profile.npd_connection_status || "not_connected").toLowerCase();
  const inn = profile.inn || "";
  const connectedAt = profile.npd_connected_at;
  const revokedAt = profile.npd_revoked_at;
  const verificationStatus = profile.verification_status;
  const tone = status === "connected" ? "ok" : status === "revoked" ? "warn" : "neutral";

  host.innerHTML = `
    <h3>Самозанятость</h3>
    <dl class="info-list">
      <dt>Статус «Мой Налог»</dt><dd><span class="badge badge-${escapeAttr(tone)}">${escapeHtml(NPD_STATUS_LABELS[status] || status)}</span></dd>
      <dt>ИНН</dt><dd>${inn ? `<span class="mono">${escapeHtml(inn)}</span>${copyButton(inn)}` : '<span class="muted">не указан</span>'}</dd>
      ${verificationStatus ? `<dt>Налоговая проверка</dt><dd>${statusBadge(verificationStatus)}</dd>` : ""}
      ${connectedAt ? `<dt>Подключён</dt><dd>${escapeHtml(formatDate(connectedAt))}</dd>` : ""}
      ${revokedAt ? `<dt>Отозвано</dt><dd>${escapeHtml(formatDate(revokedAt))}</dd>` : ""}
    </dl>
    ${status === "not_connected" ? `<p class="muted" style="margin-top:8px">Водитель ещё не подключил «Мой Налог». Интеграция станет активной после получения статуса партнёра ФНС.</p>` : ""}
  `;
}

async function driverBlockToggle(driver, action) {
  if (!driver.verificationID) {
    showToast("У водителя нет заявки на верификацию — заблокировать нельзя.");
    return;
  }
  const isBlock = action === "block";
  const result = await confirmDialog({
    title: isBlock ? "Заблокировать водителя?" : "Разблокировать водителя?",
    message: isBlock
      ? "Водитель перестанет получать заказы и не сможет войти в приложение."
      : "Водитель снова сможет получать заказы. Подтвердите действие.",
    confirmLabel: isBlock ? "Заблокировать" : "Разблокировать",
    tone: isBlock ? "danger" : "default",
    requireReason: true,
    reasonLabel: "Причина решения",
  });
  if (!result?.confirmed) return;

  const endpoint = isBlock ? "block" : "approve";
  const path = `/api/v1/admin/moderation/driver-verifications/${encodeURIComponent(driver.verificationID)}/${endpoint}`;
  try {
    const response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...authHeaders() },
      body: JSON.stringify({ reason: result.reason }),
    });
    if (!response.ok) throw new Error(`API ${response.status}`);
    showToast(isBlock ? "Водитель заблокирован." : "Водитель разблокирован.");
    closeDrawer();
    await loadAll();
  } catch (error) {
    console.error("driver block/unblock failed", error);
    showToast("Не удалось применить решение. Проверьте подключение к backend.");
  }
}

// --- Documents (driver verifications) screen -------------------------------

function filteredDocuments() {
  const f = state.documentsFilters;
  const q = (f.search || "").trim().toLowerCase();
  return state.verifications.filter((item) => {
    if (q) {
      const hay = `${item.id} ${item.driver_name || ""} ${item.phone || ""} ${item.plate || ""} ${item.vehicle || ""}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    if (f.status !== "all" && item.status !== f.status) return false;
    if (f.risk !== "all" && item.risk !== f.risk) return false;
    return true;
  });
}

function renderDocuments() {
  const filterHost = document.getElementById("documents-filters");
  const grid = document.getElementById("documents-grid");
  const countLabel = document.getElementById("documents-count-label");
  if (!filterHost || !grid) return;

  renderFilterBar({
    container: filterHost,
    fields: [
      { type: "search", key: "search", placeholder: "Поиск по ФИО, телефону, госномеру, ID", value: state.documentsFilters.search },
      {
        type: "select", key: "status", label: "Статус",
        options: [
          { value: "all", label: "Все" },
          { value: "pending", label: "На проверке" },
          { value: "approved", label: "Одобрены" },
          { value: "rejected", label: "Отклонены" },
          { value: "changes_requested", label: "Нужны правки" },
          { value: "blocked", label: "Заблокированы" },
        ],
        value: state.documentsFilters.status,
      },
      {
        type: "select", key: "risk", label: "Риск",
        options: [
          { value: "all", label: "Все" },
          { value: "low", label: "Низкий" },
          { value: "medium", label: "Средний" },
          { value: "high", label: "Высокий" },
        ],
        value: state.documentsFilters.risk,
      },
    ],
    values: state.documentsFilters,
    onChange: (values) => {
      state.documentsFilters = { ...state.documentsFilters, ...values };
      renderDocuments();
    },
    onReset: () => {
      state.documentsFilters = { search: "", status: "all", risk: "all" };
      renderDocuments();
    },
  });

  if (state.source === "loading") {
    grid.innerHTML = renderLoadingState();
    if (countLabel) countLabel.textContent = "—";
    return;
  }

  const items = filteredDocuments();
  if (countLabel) countLabel.textContent = `${items.length} заявок`;

  if (items.length === 0) {
    grid.innerHTML = renderEmptyState("Заявок по фильтру нет");
    return;
  }

  grid.innerHTML = `
    <div class="documents-grid">
      ${items.map(renderDocumentCard).join("")}
    </div>
  `;

  grid.querySelectorAll("[data-doc-id]").forEach((card) => {
    card.addEventListener("click", (event) => {
      if (event.target.closest("button, a, [data-copy]")) return;
      const id = card.getAttribute("data-doc-id");
      const item = state.verifications.find((v) => v.id === id);
      if (item) openDocumentDrawer(item);
    });
  });
}

function renderDocumentCard(item) {
  const canAct = item.status === "pending" || item.status === "changes_requested";
  return `
    <article class="doc-card" data-doc-id="${escapeAttr(item.id)}">
      <div class="doc-card-head">
        <div>
          <strong>${escapeHtml(item.driver_name || "Без имени")}</strong>
          <div class="muted">${escapeHtml(item.phone || "—")} · ${escapeHtml(item.city || "—")}</div>
        </div>
        <div class="doc-card-badges">
          ${statusBadge(item.status)}
          ${item.risk ? statusBadge(item.risk, riskLabel(item.risk)) : ""}
        </div>
      </div>
      <div class="doc-card-vehicle muted">
        ${escapeHtml(item.vehicle || "—")} · ${escapeHtml(item.plate || "—")} · ${escapeHtml(item.vehicle_type || "—")}
      </div>
      <div class="doc-card-thumbs">
        ${(item.documents || []).slice(0, 6).map((doc, idx) => documentThumb(doc, idx)).join("") || `<div class="muted small">Документы не переданы</div>`}
      </div>
      ${(item.signals && item.signals.length) ? `
        <div class="doc-card-signals">
          ${item.signals.slice(0, 3).map((s) => `<span class="signal-chip">${escapeHtml(s)}</span>`).join("")}
          ${item.signals.length > 3 ? `<span class="muted small">+${item.signals.length - 3}</span>` : ""}
        </div>
      ` : ""}
      <div class="doc-card-footer">
        <span class="muted small">Подана ${escapeHtml(formatDate(item.submitted_at))}</span>
        <div class="doc-card-actions">
          ${canAct ? `<button class="secondary-button" type="button" data-doc-action="open">Открыть</button>` : `<button class="secondary-button" type="button" data-doc-action="open">Подробнее</button>`}
        </div>
      </div>
    </article>
  `;
}

function documentThumb(doc, index) {
  // The backend currently stores document titles as plain strings (no URLs).
  // We render a labelled thumb tile; if the value happens to look like a URL,
  // we use it as an image src. The drawer will offer a zoom view.
  const isUrl = typeof doc === "string" && /^https?:\/\//i.test(doc);
  const label = isUrl ? `Файл ${index + 1}` : doc;
  return `
    <button class="doc-thumb" type="button" data-doc-thumb data-doc-src="${escapeAttr(isUrl ? doc : "")}" data-doc-label="${escapeAttr(label)}" aria-label="${escapeAttr(label)}">
      ${isUrl
        ? `<img src="${escapeAttr(doc)}" alt="${escapeAttr(label)}" loading="lazy" />`
        : `<div class="doc-thumb-fallback"><svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z"/><path d="M14 3v5h5"/></svg></div>`}
      <span class="doc-thumb-label">${escapeHtml(label)}</span>
    </button>
  `;
}

function openDocumentDrawer(item) {
  const canAct = item.status === "pending" || item.status === "changes_requested";

  const body = `
    <section class="drawer-section">
      <div class="card-row">
        ${statusBadge(item.status)}
        ${item.risk ? statusBadge(item.risk, riskLabel(item.risk)) : ""}
        <span class="muted small">Подана ${escapeHtml(formatDate(item.submitted_at))}</span>
      </div>
    </section>
    <section class="drawer-section">
      <h3>Водитель</h3>
      <dl class="info-list">
        <dt>ID</dt><dd>${escapeHtml(item.id)}${copyButton(item.id)}</dd>
        <dt>ФИО</dt><dd>${escapeHtml(item.driver_name || "—")}</dd>
        <dt>Телефон</dt><dd>${escapeHtml(item.phone || "—")}</dd>
        <dt>Город</dt><dd>${escapeHtml(item.city || "—")}</dd>
        <dt>Авто</dt><dd>${escapeHtml(item.vehicle || "—")} · ${escapeHtml(item.plate || "—")} · ${escapeHtml(item.vehicle_type || "—")}</dd>
        <dt>Рейтинг</dt><dd>${escapeHtml(formatStarsValue(item.stars))} · ${escapeHtml(numberOr(item.orders))} заказов</dd>
      </dl>
    </section>
    <section class="drawer-section">
      <h3>Документы</h3>
      <div class="doc-card-thumbs doc-drawer-thumbs">
        ${(item.documents || []).map((doc, idx) => documentThumb(doc, idx)).join("") || `<div class="muted">Документы не переданы.</div>`}
      </div>
    </section>
    <section class="drawer-section">
      <h3>Риск-сигналы</h3>
      ${(item.signals && item.signals.length)
        ? `<div class="signal-list">${item.signals.map((s) => `<div class="signal-item"><span>!</span>${escapeHtml(s)}</div>`).join("")}</div>`
        : `<div class="muted">Критичных сигналов нет.</div>`}
    </section>
    ${item.decision_reason ? `
    <section class="drawer-section">
      <h3>Комментарий модератора</h3>
      <p>${escapeHtml(item.decision_reason)}</p>
    </section>` : ""}
  `;

  const actions = canAct ? `
    <button class="secondary-button" type="button" data-doc-decision="request-changes">Запросить правки</button>
    <button class="secondary-button" type="button" data-doc-decision="reject">Отклонить</button>
    <button class="danger-button" type="button" data-doc-decision="block">Заблокировать</button>
    <button class="primary-button" type="button" data-doc-decision="approve">Одобрить</button>
  ` : `
    <button class="secondary-button" type="button" data-drawer-close>Закрыть</button>
  `;

  openDrawer({
    title: item.driver_name || item.id,
    subtitle: `${item.vehicle || ""} · ${item.plate || ""}`,
    contentHtml: body,
    actionsHtml: actions,
    onMount: (drawer) => {
      drawer.querySelectorAll("[data-doc-decision]").forEach((btn) => {
        btn.addEventListener("click", () => {
          const decision = btn.getAttribute("data-doc-decision");
          documentDecision(item, decision);
        });
      });
      drawer.querySelectorAll("[data-doc-thumb]").forEach((thumb) => {
        thumb.addEventListener("click", () => {
          openDocumentZoom(thumb.getAttribute("data-doc-src"), thumb.getAttribute("data-doc-label"));
        });
      });
    },
  });

  // Wire up thumb clicks on card grid too (re-attached on every render).
  document.querySelectorAll("#documents-grid [data-doc-thumb]").forEach((thumb) => {
    thumb.addEventListener("click", (event) => {
      event.stopPropagation();
      openDocumentZoom(thumb.getAttribute("data-doc-src"), thumb.getAttribute("data-doc-label"));
    });
  });
}

async function documentDecision(item, decision) {
  let payload;

  if (decision === "approve") {
    const result = await vehicleApprovalDialog({
      driverName: item.driver_name || "",
      verificationID: item.id,
    });
    if (!result?.confirmed) return;
    payload = {
      reason: "approved by admin",
      vehicle_plate: result.plate,
      vehicle_model: result.model,
      vehicle_type: result.type,
    };
  } else {
    const titles = {
      reject: "Отклонить заявку?",
      "request-changes": "Запросить правки?",
      block: "Заблокировать водителя?",
    };
    const confirmLabels = { reject: "Отклонить", "request-changes": "Запросить", block: "Заблокировать" };
    const tones = { reject: "danger", "request-changes": "default", block: "danger" };

    const result = await confirmDialog({
      title: titles[decision],
      message: `Заявка ${item.id} · ${item.driver_name || ""}`,
      confirmLabel: confirmLabels[decision],
      tone: tones[decision],
      requireReason: true,
      reasonLabel: "Причина / комментарий",
    });
    if (!result?.confirmed) return;
    payload = { reason: result.reason };
  }

  const path = `/api/v1/admin/moderation/driver-verifications/${encodeURIComponent(item.id)}/${decision}`;
  try {
    const response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...authHeaders() },
      body: JSON.stringify(payload),
    });
    if (!response.ok) {
      let msg = `API ${response.status}`;
      try { const j = await response.json(); if (j?.error) msg = j.error; } catch (_) {}
      throw new Error(msg);
    }
    showToast(decision === "approve" ? "Водитель одобрен, SMS отправлена." : "Решение сохранено.");
    closeDrawer();
    await loadAll();
  } catch (error) {
    console.error("document decision failed", error);
    showToast(`Не удалось сохранить решение: ${error.message || error}`);
  }
}

function openDocumentZoom(src, label) {
  if (!src) {
    showToast("Файл не доступен для предпросмотра. Backend пока хранит документы как метки.");
    return;
  }
  const root = document.getElementById("dialog-root");
  if (!root) return;
  root.setAttribute("aria-hidden", "false");
  root.innerHTML = `
    <div class="dialog-backdrop" data-dialog-close></div>
    <div class="dialog dialog-zoom" role="dialog" aria-modal="true" aria-label="${escapeAttr(label || "Документ")}">
      <header class="dialog-zoom-head">
        <strong>${escapeHtml(label || "Документ")}</strong>
        <button class="icon-button" type="button" data-dialog-close aria-label="Закрыть">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>
        </button>
      </header>
      <div class="dialog-zoom-body">
        <img src="${escapeAttr(src)}" alt="${escapeAttr(label || "Документ")}" />
      </div>
    </div>
  `;
  const close = () => {
    root.setAttribute("aria-hidden", "true");
    root.innerHTML = "";
    document.removeEventListener("keydown", onKey);
  };
  function onKey(e) { if (e.key === "Escape") close(); }
  document.addEventListener("keydown", onKey);
  root.querySelectorAll("[data-dialog-close]").forEach((el) => el.addEventListener("click", close));
}

// ============================================================================
// Phase 4 — Orders
// ============================================================================

const ORDER_STATUS_LABELS = {
  draft: "Черновик",
  searching: "Поиск",
  assigned: "Назначен",
  accepted: "Принят",
  arriving: "Едет",
  arrived: "На месте",
  in_progress: "В работе",
  evacuating: "Эвакуация",
  to_destination: "К точке",
  completed: "Завершён",
  cancelled: "Отменён",
  canceled: "Отменён",
  rejected: "Отклонён",
  failed: "Ошибка",
};

const PAYMENT_METHOD_LABELS = {
  cash: "Наличные",
  card: "Карта",
  sbp: "СБП",
  yookassa: "Карта (ЮKassa)",
  applepay: "Apple Pay",
  googlepay: "Google Pay",
};

const PAYMENT_PURPOSE_LABELS = {
  order: "Заказ",
  subscription: "Подписка",
  topup: "Пополнение",
  refund: "Возврат",
};

const FINANCIAL_STATUS_LABELS = {
  pending: "Ожидает",
  paid: "Оплачен",
  hold: "Удержание",
  settled: "Расчёт проведён",
  refunded: "Возврат",
  unpaid: "Не оплачен",
  failed: "Ошибка",
};

function labelOr(map, key, fallback = "") {
  if (key == null || key === "") return fallback || "—";
  return map[String(key).toLowerCase()] || String(key);
}

function ordersQuery() {
  const f = state.ordersFilters;
  const params = new URLSearchParams();
  params.set("limit", String(ADMIN_PAGE_SIZE));
  params.set("offset", String(Math.max(0, (f.page - 1) * ADMIN_PAGE_SIZE)));
  if (f.status && f.status !== "all") params.set("status", f.status);
  if (f.payment_method && f.payment_method !== "all") params.set("payment_method", f.payment_method);
  if (f.financial_status && f.financial_status !== "all") params.set("financial_status", f.financial_status);
  if (f.from) params.set("from", f.from);
  if (f.to) params.set("to", f.to);
  return params.toString();
}

async function loadOrders() {
  state.ordersLoading = true;
  state.ordersError = null;
  renderOrders();
  const result = await getAdminPath(`/api/v1/admin/orders?${ordersQuery()}`);
  state.ordersLoading = false;
  if (result.source === "error") {
    state.orders = [];
    state.ordersTotal = 0;
    state.ordersError = result.error;
  } else {
    state.orders = Array.isArray(result.data?.items) ? result.data.items : [];
    state.ordersTotal = Number(result.data?.total ?? state.orders.length) || 0;
    state.ordersError = null;
  }
  renderOrders();
}

function filteredOrders() {
  const q = (state.ordersFilters.search || "").trim().toLowerCase();
  if (!q) return state.orders;
  return state.orders.filter((o) => {
    const hay = [
      o.order_id, o.client_id, o.client_name, o.client_phone,
      o.driver_id, o.driver_name, o.driver_phone,
    ].map((v) => String(v ?? "").toLowerCase()).join(" ");
    return hay.includes(q);
  });
}

function renderOrders() {
  const filterHost = document.getElementById("orders-filters");
  const tableHost = document.getElementById("orders-table");
  const countLabel = document.getElementById("orders-count-label");
  if (!filterHost || !tableHost) return;

  renderFilterBar({
    container: filterHost,
    fields: [
      { type: "search", key: "search", placeholder: "Поиск по ID, клиенту, водителю, телефону", value: state.ordersFilters.search },
      {
        type: "select", key: "status", label: "Статус",
        options: [
          { value: "all", label: "Все" },
          { value: "searching", label: "Поиск" },
          { value: "assigned", label: "Назначен" },
          { value: "accepted", label: "Принят" },
          { value: "in_progress", label: "В работе" },
          { value: "completed", label: "Завершён" },
          { value: "cancelled", label: "Отменён" },
        ],
        value: state.ordersFilters.status,
      },
      {
        type: "select", key: "payment_method", label: "Оплата",
        options: [
          { value: "all", label: "Все" },
          { value: "card", label: "Карта" },
          { value: "cash", label: "Наличные" },
          { value: "sbp", label: "СБП" },
        ],
        value: state.ordersFilters.payment_method,
      },
      {
        type: "select", key: "financial_status", label: "Финансы",
        options: [
          { value: "all", label: "Все" },
          { value: "pending", label: "Ожидает" },
          { value: "paid", label: "Оплачен" },
          { value: "hold", label: "Удержание" },
          { value: "settled", label: "Расчёт проведён" },
          { value: "refunded", label: "Возврат" },
          { value: "unpaid", label: "Не оплачен" },
        ],
        value: state.ordersFilters.financial_status,
      },
      { type: "date-range", keyFrom: "from", keyTo: "to", label: "Период" },
    ],
    values: state.ordersFilters,
    onChange: (values) => {
      state.ordersFilters = { ...state.ordersFilters, ...values, page: 1 };
      // server-side filters trigger fetch; search is local
      if (
        values.status !== undefined || values.payment_method !== undefined ||
        values.financial_status !== undefined || values.from !== undefined ||
        values.to !== undefined
      ) {
        loadOrders();
      } else {
        renderOrders();
      }
    },
    onReset: () => {
      state.ordersFilters = {
        search: "", status: "all", payment_method: "all", financial_status: "all",
        from: "", to: "", page: 1,
      };
      loadOrders();
    },
  });

  if (state.ordersLoading) {
    tableHost.innerHTML = renderLoadingState();
    if (countLabel) countLabel.textContent = "—";
    return;
  }
  if (state.ordersError) {
    tableHost.innerHTML = renderErrorState({
      message: "Не удалось загрузить заказы. Проверьте подключение и токен администратора.",
      retryId: "orders-retry",
    });
    tableHost.querySelector("[data-retry]")?.addEventListener("click", () => loadOrders());
    if (countLabel) countLabel.textContent = "—";
    return;
  }

  const rows = filteredOrders();
  if (countLabel) countLabel.textContent = `${state.ordersTotal.toLocaleString("ru-RU")} заказов всего · показано ${rows.length}`;

  renderDataTable({
    container: tableHost,
    rowId: (r) => r.order_id,
    onRowClick: (r) => openOrderDrawer(r.order_id),
    columns: [
      {
        key: "order_id", label: "ID заказа",
        render: (r) => `<span class="mono">${escapeHtml(String(r.order_id || "").slice(0, 10))}</span>${copyButton(r.order_id || "", { title: "Скопировать ID заказа" })}`,
      },
      {
        key: "client", label: "Клиент",
        render: (r) => `
          <div class="cell-stack">
            <strong>${escapeHtml(r.client_name || "—")}</strong>
            <span class="muted">${escapeHtml(r.client_phone || "")}</span>
          </div>`,
      },
      {
        key: "driver", label: "Водитель",
        render: (r) => r.driver_id
          ? `<div class="cell-stack">
              <strong>${escapeHtml(r.driver_name || r.driver_id)}</strong>
              <span class="muted">${escapeHtml(r.driver_phone || "")}</span>
            </div>`
          : `<span class="muted">не назначен</span>`,
      },
      {
        key: "status", label: "Статус",
        render: (r) => statusBadge(r.status, ORDER_STATUS_LABELS[String(r.status || "").toLowerCase()]),
      },
      {
        key: "payment_method", label: "Оплата",
        render: (r) => labelOr(PAYMENT_METHOD_LABELS, r.payment_method, "—"),
      },
      {
        key: "financial_status", label: "Финансы",
        render: (r) => r.financial_status
          ? statusBadge(r.financial_status, FINANCIAL_STATUS_LABELS[String(r.financial_status).toLowerCase()])
          : `<span class="muted">—</span>`,
      },
      {
        key: "price_total", label: "Сумма",
        align: "right",
        render: (r) => formatMoney(r.price_total, { minor: true }),
      },
      {
        key: "commission_amount", label: "Комиссия",
        align: "right",
        render: (r) => formatMoney(r.commission_amount, { minor: true }),
      },
      {
        key: "driver_amount", label: "К водителю",
        align: "right",
        render: (r) => formatMoney(r.driver_amount, { minor: true }),
      },
      {
        key: "created_at", label: "Создан",
        render: (r) => escapeHtml(formatDate(r.created_at)),
      },
    ],
    rows,
    emptyMessage: "Заказы по выбранным фильтрам не найдены",
    page: state.ordersFilters.page,
    pageSize: ADMIN_PAGE_SIZE,
    total: state.ordersTotal,
    onPage: (page) => {
      state.ordersFilters = { ...state.ordersFilters, page };
      loadOrders();
    },
  });
}

async function openOrderDrawer(orderID) {
  if (!orderID) return;
  openDrawer({
    title: `Заказ ${orderID}`,
    subtitle: "Загрузка деталей…",
    contentHtml: renderLoadingState("Загружаем заказ…"),
  });
  const result = await getAdminPath(`/api/v1/admin/orders/${encodeURIComponent(orderID)}`);
  if (result.source === "error") {
    openDrawer({
      title: `Заказ ${orderID}`,
      subtitle: "Ошибка загрузки",
      contentHtml: renderErrorState({ message: "Не удалось загрузить детали заказа.", retryId: "order-retry" }),
      onMount: (drawer) => {
        drawer.querySelector("[data-retry]")?.addEventListener("click", () => openOrderDrawer(orderID));
      },
    });
    return;
  }
  renderOrderDrawer(result.data || {});
}

function renderOrderDrawer(details) {
  const order = details.order || {};
  const payment = details.payment;
  const fb = details.financial_breakdown || {};
  const timeline = Array.isArray(details.timeline) ? details.timeline : [];
  const wtx = Array.isArray(details.wallet_transactions) ? details.wallet_transactions : [];
  const payouts = Array.isArray(details.payouts) ? details.payouts : [];
  const refunds = Array.isArray(details.refunds) ? details.refunds : [];
  const pickup = details.pickup || {};
  const dropoff = details.dropoff || {};

  const generalSection = `
    <section class="drawer-section">
      <h3>Основное</h3>
      <dl class="info-list">
        <dt>ID заказа</dt><dd><span class="mono">${escapeHtml(order.order_id || "—")}</span>${copyButton(order.order_id || "")}</dd>
        <dt>Статус</dt><dd>${statusBadge(order.status, ORDER_STATUS_LABELS[String(order.status || "").toLowerCase()])}</dd>
        <dt>Клиент</dt><dd>${escapeHtml(order.client_name || "—")} · <span class="muted">${escapeHtml(order.client_phone || "")}</span></dd>
        <dt>ID клиента</dt><dd><span class="mono">${escapeHtml(order.client_id || "—")}</span>${order.client_id ? copyButton(order.client_id) : ""}</dd>
        <dt>Водитель</dt><dd>${order.driver_id ? `${escapeHtml(order.driver_name || order.driver_id)} · <span class="muted">${escapeHtml(order.driver_phone || "")}</span>` : '<span class="muted">не назначен</span>'}</dd>
        ${order.driver_id ? `<dt>ID водителя</dt><dd><span class="mono">${escapeHtml(order.driver_id)}</span>${copyButton(order.driver_id)}</dd>` : ""}
        <dt>Тип эвакуатора</dt><dd>${escapeHtml(details.tow_truck_type || "—")}</dd>
        <dt>Создан</dt><dd>${escapeHtml(formatDate(order.created_at))}</dd>
        ${order.completed_at ? `<dt>Завершён</dt><dd>${escapeHtml(formatDate(order.completed_at))}</dd>` : ""}
        ${order.cancelled_at ? `<dt>Отменён</dt><dd>${escapeHtml(formatDate(order.cancelled_at))}</dd>` : ""}
      </dl>
    </section>
  `;

  const routeSection = `
    <section class="drawer-section">
      <h3>Маршрут</h3>
      <dl class="info-list">
        <dt>Подача</dt><dd>${escapeHtml(formatCoord(pickup))}</dd>
        <dt>Назначение</dt><dd>${escapeHtml(formatCoord(dropoff))}</dd>
      </dl>
    </section>
  `;

  const financeSection = `
    <section class="drawer-section">
      <h3>Финансовая разбивка</h3>
      <dl class="info-list">
        <dt>Сумма заказа</dt><dd><strong>${formatMoney(fb.total_amount ?? order.price_total, { minor: true })}</strong></dd>
        <dt>Комиссия Tow Truck</dt><dd>${formatMoney(fb.commission_amount ?? order.commission_amount, { minor: true })}</dd>
        <dt>К водителю</dt><dd>${formatMoney(fb.driver_amount ?? order.driver_amount, { minor: true })}</dd>
        <dt>Удержание (наличные)</dt><dd>${formatMoney(fb.cash_commission_hold, { minor: true })}</dd>
        <dt>Чистая выручка платформы</dt><dd>${formatMoney(fb.platform_net_amount, { minor: true })}</dd>
        <dt>Способ оплаты</dt><dd>${escapeHtml(labelOr(PAYMENT_METHOD_LABELS, order.payment_method))}</dd>
        <dt>Финансовый статус</dt><dd>${order.financial_status ? statusBadge(order.financial_status, FINANCIAL_STATUS_LABELS[String(order.financial_status).toLowerCase()]) : '<span class="muted">—</span>'}</dd>
      </dl>
    </section>
  `;

  const paymentSection = payment
    ? `<section class="drawer-section">
        <h3>Платёж клиента</h3>
        <dl class="info-list">
          <dt>ID платежа</dt><dd><span class="mono">${escapeHtml(payment.id || "—")}</span>${payment.id ? copyButton(payment.id) : ""}</dd>
          <dt>Провайдер</dt><dd>${escapeHtml(payment.provider || "—")}</dd>
          ${payment.provider_payment_id ? `<dt>ID у провайдера</dt><dd><span class="mono">${escapeHtml(payment.provider_payment_id)}</span>${copyButton(payment.provider_payment_id)}</dd>` : ""}
          <dt>Метод</dt><dd>${escapeHtml(labelOr(PAYMENT_METHOD_LABELS, payment.payment_method))}</dd>
          <dt>Сумма</dt><dd>${formatMoney(payment.amount, { minor: true })}</dd>
          <dt>Статус</dt><dd>${statusBadge(payment.status)}</dd>
          ${payment.paid_at ? `<dt>Оплачен</dt><dd>${escapeHtml(formatDate(payment.paid_at))}</dd>` : ""}
          <dt>Создан</dt><dd>${escapeHtml(formatDate(payment.created_at))}</dd>
        </dl>
      </section>`
    : `<section class="drawer-section">
        <h3>Платёж клиента</h3>
        <p class="muted">К заказу не привязан платёж (например, оплата наличными или клиент ещё не оплатил).</p>
      </section>`;

  const timelineSection = timeline.length
    ? `<section class="drawer-section">
        <h3>Таймлайн</h3>
        <ol class="timeline">
          ${timeline.map((ev) => `
            <li>
              <span class="timeline-dot"></span>
              <div>
                <strong>${escapeHtml(ORDER_STATUS_LABELS[String(ev.status || "").toLowerCase()] || ev.status || "—")}</strong>
                <div class="muted">${escapeHtml(formatDate(ev.at))}</div>
              </div>
            </li>`).join("")}
        </ol>
      </section>`
    : "";

  const wtxSection = wtx.length
    ? `<section class="drawer-section">
        <h3>Транзакции кошелька</h3>
        <div class="mini-table">
          <table>
            <thead><tr><th>Тип</th><th>Направление</th><th class="right">Сумма</th><th>Статус</th><th>Создана</th></tr></thead>
            <tbody>
              ${wtx.map((tx) => `
                <tr>
                  <td>${escapeHtml(tx.type || "—")}</td>
                  <td>${escapeHtml(tx.direction || "—")}</td>
                  <td class="right">${formatMoney(tx.amount, { minor: true })}</td>
                  <td>${statusBadge(tx.status)}</td>
                  <td>${escapeHtml(formatDate(tx.created_at))}</td>
                </tr>`).join("")}
            </tbody>
          </table>
        </div>
      </section>`
    : "";

  const payoutsSection = payouts.length
    ? `<section class="drawer-section">
        <h3>Выплаты водителю</h3>
        <div class="mini-table">
          <table>
            <thead><tr><th>ID</th><th class="right">Сумма</th><th>Статус</th><th>Создана</th></tr></thead>
            <tbody>
              ${payouts.map((p) => `
                <tr>
                  <td><span class="mono">${escapeHtml(String(p.id || "").slice(0, 10))}</span></td>
                  <td class="right">${formatMoney(p.amount, { minor: true })}</td>
                  <td>${statusBadge(p.status)}</td>
                  <td>${escapeHtml(formatDate(p.created_at))}</td>
                </tr>`).join("")}
            </tbody>
          </table>
        </div>
      </section>`
    : "";

  const refundsSection = refunds.length
    ? `<section class="drawer-section">
        <h3>Возвраты</h3>
        <div class="mini-table">
          <table>
            <thead><tr><th>ID</th><th class="right">Сумма</th><th>Статус</th><th>Причина</th><th>Создан</th></tr></thead>
            <tbody>
              ${refunds.map((rf) => `
                <tr>
                  <td><span class="mono">${escapeHtml(String(rf.id || "").slice(0, 10))}</span></td>
                  <td class="right">${formatMoney(rf.amount, { minor: true })}</td>
                  <td>${statusBadge(rf.status)}</td>
                  <td>${escapeHtml(rf.reason || "—")}</td>
                  <td>${escapeHtml(formatDate(rf.created_at))}</td>
                </tr>`).join("")}
            </tbody>
          </table>
        </div>
      </section>`
    : "";

  openDrawer({
    title: `Заказ ${order.order_id || ""}`,
    subtitle: order.client_name || "",
    contentHtml: `
      ${generalSection}
      ${routeSection}
      ${financeSection}
      ${paymentSection}
      ${timelineSection}
      ${wtxSection}
      ${payoutsSection}
      ${refundsSection}
    `,
    actionsHtml: `<button class="secondary-button" type="button" data-drawer-close>Закрыть</button>`,
  });
}

function formatCoord(p) {
  if (p == null || (p.lat === 0 && p.lng === 0)) return "—";
  if (typeof p.lat !== "number" || typeof p.lng !== "number") return "—";
  return `${p.lat.toFixed(5)}, ${p.lng.toFixed(5)}`;
}

// ============================================================================
// Phase 4 — Payments
// ============================================================================

async function loadPayments() {
  state.paymentsLoading = true;
  state.paymentsError = null;
  renderPayments();
  const result = await getAdminPath(`/api/v1/admin/finance/payments`);
  state.paymentsLoading = false;
  if (result.source === "error") {
    state.payments = [];
    state.paymentsError = result.error;
  } else {
    state.payments = rowsToObjects(result.data?.rows);
    state.paymentsError = null;
  }
  renderPayments();
}

function filteredPayments() {
  const f = state.paymentsFilters;
  const q = (f.search || "").trim().toLowerCase();
  return state.payments.filter((p) => {
    if (q) {
      const hay = [p.id, p.order_id, p.user_id, p.provider_payment_id, p.provider]
        .map((v) => String(v ?? "").toLowerCase()).join(" ");
      if (!hay.includes(q)) return false;
    }
    if (f.status !== "all" && String(p.status || "").toLowerCase() !== f.status) return false;
    if (f.purpose !== "all" && String(p.purpose || "").toLowerCase() !== f.purpose) return false;
    if (f.payment_method !== "all" && String(p.payment_method || "").toLowerCase() !== f.payment_method) return false;
    if (f.from) {
      const created = new Date(p.created_at).getTime();
      if (Number.isFinite(created) && created < new Date(f.from).getTime()) return false;
    }
    if (f.to) {
      const created = new Date(p.created_at).getTime();
      const toTs = new Date(f.to).getTime() + 24 * 60 * 60 * 1000 - 1;
      if (Number.isFinite(created) && created > toTs) return false;
    }
    return true;
  });
}

function renderPayments() {
  const filterHost = document.getElementById("payments-filters");
  const tableHost = document.getElementById("payments-table");
  const countLabel = document.getElementById("payments-count-label");
  if (!filterHost || !tableHost) return;

  renderFilterBar({
    container: filterHost,
    fields: [
      { type: "search", key: "search", placeholder: "Поиск по ID платежа, заказа, клиента, провайдеру", value: state.paymentsFilters.search },
      {
        type: "select", key: "status", label: "Статус",
        options: [
          { value: "all", label: "Все" },
          { value: "pending", label: "Ожидает" },
          { value: "waiting_for_capture", label: "Ожидает захвата" },
          { value: "succeeded", label: "Успешно" },
          { value: "canceled", label: "Отменён" },
          { value: "failed", label: "Ошибка" },
        ],
        value: state.paymentsFilters.status,
      },
      {
        type: "select", key: "purpose", label: "Назначение",
        options: [
          { value: "all", label: "Все" },
          { value: "order", label: "Заказ" },
          { value: "subscription", label: "Подписка" },
          { value: "topup", label: "Пополнение" },
        ],
        value: state.paymentsFilters.purpose,
      },
      {
        type: "select", key: "payment_method", label: "Метод",
        options: [
          { value: "all", label: "Все" },
          { value: "card", label: "Карта" },
          { value: "sbp", label: "СБП" },
          { value: "cash", label: "Наличные" },
        ],
        value: state.paymentsFilters.payment_method,
      },
      { type: "date-range", keyFrom: "from", keyTo: "to", label: "Период" },
    ],
    values: state.paymentsFilters,
    onChange: (values) => {
      state.paymentsFilters = { ...state.paymentsFilters, ...values, page: 1 };
      renderPayments();
    },
    onReset: () => {
      state.paymentsFilters = {
        search: "", status: "all", purpose: "all", payment_method: "all",
        from: "", to: "", page: 1,
      };
      renderPayments();
    },
  });

  if (state.paymentsLoading) {
    tableHost.innerHTML = renderLoadingState();
    if (countLabel) countLabel.textContent = "—";
    return;
  }
  if (state.paymentsError) {
    tableHost.innerHTML = renderErrorState({
      message: "Не удалось загрузить платежи. Проверьте подключение и токен администратора.",
      retryId: "payments-retry",
    });
    tableHost.querySelector("[data-retry]")?.addEventListener("click", () => loadPayments());
    if (countLabel) countLabel.textContent = "—";
    return;
  }

  const all = filteredPayments();
  if (countLabel) countLabel.textContent = `${all.length.toLocaleString("ru-RU")} платежей`;

  const page = Math.max(1, state.paymentsFilters.page || 1);
  const startIdx = (page - 1) * ADMIN_PAGE_SIZE;
  const rows = all.slice(startIdx, startIdx + ADMIN_PAGE_SIZE);

  renderDataTable({
    container: tableHost,
    rowId: (r) => r.id,
    onRowClick: (r) => openPaymentDrawer(r),
    columns: [
      {
        key: "id", label: "ID платежа",
        render: (r) => `<span class="mono">${escapeHtml(String(r.id || "").slice(0, 10))}</span>${r.id ? copyButton(r.id, { title: "Скопировать ID" }) : ""}`,
      },
      {
        key: "order_id", label: "Заказ",
        render: (r) => r.order_id
          ? `<span class="mono">${escapeHtml(String(r.order_id).slice(0, 10))}</span>${copyButton(r.order_id)}`
          : `<span class="muted">—</span>`,
      },
      {
        key: "user_id", label: "Клиент",
        render: (r) => r.user_id
          ? `<span class="mono">${escapeHtml(String(r.user_id).slice(0, 10))}</span>${copyButton(r.user_id)}`
          : `<span class="muted">—</span>`,
      },
      { key: "provider", label: "Провайдер", render: (r) => escapeHtml(r.provider || "—") },
      {
        key: "payment_method", label: "Метод",
        render: (r) => escapeHtml(labelOr(PAYMENT_METHOD_LABELS, r.payment_method)),
      },
      {
        key: "purpose", label: "Назначение",
        render: (r) => escapeHtml(labelOr(PAYMENT_PURPOSE_LABELS, r.purpose)),
      },
      {
        key: "amount", label: "Сумма",
        align: "right",
        render: (r) => formatMoney(r.amount, { minor: true }),
      },
      {
        key: "status", label: "Статус",
        render: (r) => statusBadge(r.status),
      },
      {
        key: "created_at", label: "Создан",
        render: (r) => escapeHtml(formatDate(r.created_at)),
      },
    ],
    rows,
    emptyMessage: "Платежи по выбранным фильтрам не найдены",
    page,
    pageSize: ADMIN_PAGE_SIZE,
    total: all.length,
    onPage: (next) => {
      state.paymentsFilters = { ...state.paymentsFilters, page: next };
      renderPayments();
    },
  });
}

function openPaymentDrawer(p) {
  if (!p) return;
  const linkedOrderHtml = p.order_id
    ? `<button class="link-button" type="button" data-open-order="${escapeAttr(p.order_id)}">Открыть заказ →</button>`
    : "";
  openDrawer({
    title: `Платёж ${String(p.id || "").slice(0, 10)}`,
    subtitle: `${labelOr(PAYMENT_PURPOSE_LABELS, p.purpose)} · ${labelOr(PAYMENT_METHOD_LABELS, p.payment_method)}`,
    contentHtml: `
      <section class="drawer-section">
        <h3>Основное</h3>
        <dl class="info-list">
          <dt>ID платежа</dt><dd><span class="mono">${escapeHtml(p.id || "—")}</span>${p.id ? copyButton(p.id) : ""}</dd>
          <dt>Статус</dt><dd>${statusBadge(p.status)}</dd>
          <dt>Сумма</dt><dd><strong>${formatMoney(p.amount, { minor: true })}</strong> ${escapeHtml(p.currency || "RUB")}</dd>
          <dt>Назначение</dt><dd>${escapeHtml(labelOr(PAYMENT_PURPOSE_LABELS, p.purpose))}</dd>
          <dt>Метод</dt><dd>${escapeHtml(labelOr(PAYMENT_METHOD_LABELS, p.payment_method))}</dd>
          <dt>Создан</dt><dd>${escapeHtml(formatDate(p.created_at))}</dd>
        </dl>
      </section>
      <section class="drawer-section">
        <h3>Провайдер</h3>
        <dl class="info-list">
          <dt>Провайдер</dt><dd>${escapeHtml(p.provider || "—")}</dd>
          <dt>ID у провайдера</dt><dd>${p.provider_payment_id ? `<span class="mono">${escapeHtml(p.provider_payment_id)}</span>${copyButton(p.provider_payment_id)}` : '<span class="muted">—</span>'}</dd>
        </dl>
      </section>
      <section class="drawer-section">
        <h3>Связи</h3>
        <dl class="info-list">
          <dt>Заказ</dt><dd>${p.order_id ? `<span class="mono">${escapeHtml(p.order_id)}</span>${copyButton(p.order_id)}` : '<span class="muted">—</span>'}</dd>
          <dt>Клиент</dt><dd>${p.user_id ? `<span class="mono">${escapeHtml(p.user_id)}</span>${copyButton(p.user_id)}` : '<span class="muted">—</span>'}</dd>
        </dl>
        ${linkedOrderHtml ? `<div style="margin-top:10px">${linkedOrderHtml}</div>` : ""}
      </section>
      <section class="drawer-section">
        <h3>Возвраты и webhooks</h3>
        <p class="muted">История webhook-событий и привязанные возвраты появятся в Phase 6 (Refunds).</p>
      </section>
    `,
    actionsHtml: `<button class="secondary-button" type="button" data-drawer-close>Закрыть</button>`,
    onMount: (drawer) => {
      drawer.querySelector("[data-open-order]")?.addEventListener("click", (event) => {
        const id = event.currentTarget.getAttribute("data-open-order");
        closeDrawer();
        setTab("orders");
        openOrderDrawer(id);
      });
    },
  });
}

// ============================================================================
// Phase 5 — Payouts
// ============================================================================

const PAYOUT_APPROVABLE = new Set(["created", "processing", "manual_review", "failed"]);
const PAYOUT_REJECTABLE = new Set(["created", "processing", "manual_review"]);

const WALLET_TX_TYPE_LABELS = {
  commission: "Комиссия",
  cash_commission_debt: "Долг с наличных",
  debt_repayment: "Погашение долга",
  order_income: "Доход с заказа",
  payout: "Выплата",
  topup: "Пополнение",
  refund: "Возврат",
  subscription: "Подписка",
  adjustment: "Корректировка",
  hold: "Удержание",
  release: "Освобождение",
};

const WALLET_DIRECTION_LABELS = {
  in: "Поступление",
  out: "Списание",
  credit: "Поступление",
  debit: "Списание",
  hold: "Удержание",
};

async function loadPayouts() {
  state.payoutsLoading = true;
  state.payoutsError = null;
  renderPayouts();
  const result = await getAdminPath(`/api/v1/admin/finance/payouts`);
  state.payoutsLoading = false;
  if (result.source === "error") {
    state.payouts = [];
    state.payoutsError = result.error;
  } else {
    state.payouts = rowsToObjects(result.data?.rows);
    state.payoutsError = null;
  }
  renderPayouts();
}

function filteredPayouts() {
  const f = state.payoutsFilters;
  const q = (f.search || "").trim().toLowerCase();
  return state.payouts.filter((p) => {
    if (q) {
      const hay = [p.id, p.driver_id, p.provider_payout_id]
        .map((v) => String(v ?? "").toLowerCase()).join(" ");
      if (!hay.includes(q)) return false;
    }
    if (f.status !== "all" && String(p.status || "").toLowerCase() !== f.status) return false;
    if (f.from || f.to) {
      const created = new Date(p.created_at).getTime();
      if (f.from && Number.isFinite(created) && created < new Date(f.from).getTime()) return false;
      if (f.to) {
        const toTs = new Date(f.to).getTime() + 24 * 60 * 60 * 1000 - 1;
        if (Number.isFinite(created) && created > toTs) return false;
      }
    }
    return true;
  });
}

function renderPayouts() {
  const filterHost = document.getElementById("payouts-filters");
  const tableHost = document.getElementById("payouts-table");
  const countLabel = document.getElementById("payouts-count-label");
  if (!filterHost || !tableHost) return;

  renderFilterBar({
    container: filterHost,
    fields: [
      { type: "search", key: "search", placeholder: "Поиск по ID выплаты, водителя, provider_payout_id", value: state.payoutsFilters.search },
      {
        type: "select", key: "status", label: "Статус",
        options: [
          { value: "all", label: "Все" },
          { value: "created", label: "Создана" },
          { value: "processing", label: "В обработке" },
          { value: "manual_review", label: "Ручная проверка" },
          { value: "paid", label: "Выплачена" },
          { value: "failed", label: "Ошибка" },
          { value: "cancelled", label: "Отменена" },
        ],
        value: state.payoutsFilters.status,
      },
      { type: "date-range", keyFrom: "from", keyTo: "to", label: "Период" },
    ],
    values: state.payoutsFilters,
    onChange: (values) => {
      state.payoutsFilters = { ...state.payoutsFilters, ...values, page: 1 };
      renderPayouts();
    },
    onReset: () => {
      state.payoutsFilters = { search: "", status: "all", from: "", to: "", page: 1 };
      renderPayouts();
    },
  });

  if (state.payoutsLoading) {
    tableHost.innerHTML = renderLoadingState();
    if (countLabel) countLabel.textContent = "—";
    return;
  }
  if (state.payoutsError) {
    tableHost.innerHTML = renderErrorState({
      message: "Не удалось загрузить выплаты. Проверьте подключение и токен администратора.",
      retryId: "payouts-retry",
    });
    tableHost.querySelector("[data-retry]")?.addEventListener("click", () => loadPayouts());
    if (countLabel) countLabel.textContent = "—";
    return;
  }

  const all = filteredPayouts();
  if (countLabel) countLabel.textContent = `${all.length.toLocaleString("ru-RU")} выплат`;

  const page = Math.max(1, state.payoutsFilters.page || 1);
  const startIdx = (page - 1) * ADMIN_PAGE_SIZE;
  const rows = all.slice(startIdx, startIdx + ADMIN_PAGE_SIZE);

  renderDataTable({
    container: tableHost,
    rowId: (r) => r.id,
    onRowClick: (r) => openPayoutDrawer(r),
    columns: [
      {
        key: "id", label: "ID выплаты",
        render: (r) => `<span class="mono">${escapeHtml(String(r.id || "").slice(0, 10))}</span>${r.id ? copyButton(r.id) : ""}`,
      },
      {
        key: "driver_id", label: "Водитель",
        render: (r) => r.driver_id
          ? `<span class="mono">${escapeHtml(String(r.driver_id).slice(0, 10))}</span>${copyButton(r.driver_id)}`
          : `<span class="muted">—</span>`,
      },
      {
        key: "amount", label: "Сумма",
        align: "right",
        render: (r) => formatMoney(r.amount, { minor: true }),
      },
      { key: "currency", label: "Валюта", render: (r) => escapeHtml(r.currency || "RUB") },
      {
        key: "status", label: "Статус",
        render: (r) => statusBadge(r.status),
      },
      {
        key: "provider_payout_id", label: "У провайдера",
        render: (r) => r.provider_payout_id
          ? `<span class="mono">${escapeHtml(String(r.provider_payout_id).slice(0, 14))}</span>`
          : `<span class="muted">—</span>`,
      },
      {
        key: "created_at", label: "Создана",
        render: (r) => escapeHtml(formatDate(r.created_at)),
      },
    ],
    rows,
    emptyMessage: "Выплаты по выбранным фильтрам не найдены",
    page,
    pageSize: ADMIN_PAGE_SIZE,
    total: all.length,
    onPage: (next) => {
      state.payoutsFilters = { ...state.payoutsFilters, page: next };
      renderPayouts();
    },
  });
}

function openPayoutDrawer(p) {
  if (!p) return;
  const status = String(p.status || "").toLowerCase();
  const canApprove = PAYOUT_APPROVABLE.has(status);
  const canReject = PAYOUT_REJECTABLE.has(status);

  const actions = [
    canApprove ? `<button class="primary-button" type="button" data-payout-action="approve">Одобрить</button>` : "",
    canReject ? `<button class="danger-button" type="button" data-payout-action="reject">Отклонить</button>` : "",
    `<button class="secondary-button" type="button" data-drawer-close>Закрыть</button>`,
  ].filter(Boolean).join("");

  openDrawer({
    title: `Выплата ${String(p.id || "").slice(0, 10)}`,
    subtitle: `${formatMoney(p.amount, { minor: true })} · ${labelOr(STATUS_BADGE_LABELS, status, status)}`,
    contentHtml: `
      <section class="drawer-section">
        <h3>Основное</h3>
        <dl class="info-list">
          <dt>ID выплаты</dt><dd><span class="mono">${escapeHtml(p.id || "—")}</span>${p.id ? copyButton(p.id) : ""}</dd>
          <dt>Статус</dt><dd>${statusBadge(p.status)}</dd>
          <dt>Сумма</dt><dd><strong>${formatMoney(p.amount, { minor: true })}</strong> ${escapeHtml(p.currency || "RUB")}</dd>
          <dt>Создана</dt><dd>${escapeHtml(formatDate(p.created_at))}</dd>
        </dl>
      </section>
      <section class="drawer-section">
        <h3>Водитель и провайдер</h3>
        <dl class="info-list">
          <dt>ID водителя</dt><dd>${p.driver_id ? `<span class="mono">${escapeHtml(p.driver_id)}</span>${copyButton(p.driver_id)}` : '<span class="muted">—</span>'}</dd>
          <dt>ID у провайдера</dt><dd>${p.provider_payout_id ? `<span class="mono">${escapeHtml(p.provider_payout_id)}</span>${copyButton(p.provider_payout_id)}` : '<span class="muted">—</span>'}</dd>
        </dl>
      </section>
      ${(!canApprove && !canReject) ? `<section class="drawer-section"><p class="muted">Действия недоступны для статуса <strong>${escapeHtml(labelOr(STATUS_BADGE_LABELS, status, status))}</strong>. Одобрить можно только выплаты в статусах created/processing/manual_review/failed; отклонить — created/processing/manual_review.</p></section>` : ""}
    `,
    actionsHtml: actions,
    onMount: (drawer) => {
      drawer.querySelectorAll("[data-payout-action]").forEach((btn) => {
        btn.addEventListener("click", async () => {
          const action = btn.getAttribute("data-payout-action");
          await payoutDecision(p, action);
        });
      });
    },
  });
}

async function payoutDecision(payout, action) {
  const isApprove = action === "approve";
  const dialog = await confirmDialog({
    title: isApprove ? "Одобрить выплату?" : "Отклонить выплату?",
    message: isApprove
      ? `Будет списано ${formatMoney(payout.amount, { minor: true })} с доступного баланса водителя и выплата помечена как paid.`
      : `Выплата будет помечена как cancelled. Возможен возврат суммы на available_balance кошелька водителя.`,
    confirmLabel: isApprove ? "Одобрить" : "Отклонить",
    tone: isApprove ? "default" : "danger",
    requireReason: !isApprove,
    reasonLabel: "Причина отклонения",
    reasonMinLength: 8,
  });
  if (!dialog || (typeof dialog === "object" && !dialog.confirmed) || dialog === false) return;

  const path = `/api/v1/admin/finance/payouts/${encodeURIComponent(payout.id)}/${isApprove ? "approve" : "reject"}`;
  const body = isApprove ? undefined : JSON.stringify({ reason: dialog.reason });
  try {
    const response = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json", ...authHeaders() },
      body,
    });
    if (!response.ok) {
      let msg = `API ${response.status}`;
      try { const j = await response.json(); if (j?.error) msg = j.error; } catch (_) {}
      throw new Error(msg);
    }
    showToast(isApprove ? "Выплата одобрена." : "Выплата отклонена.");
    closeDrawer();
    await loadPayouts();
  } catch (error) {
    showToast(`Не удалось: ${error.message || error}`);
  }
}

// ============================================================================
// Phase 5 — Wallets
// ============================================================================

async function loadWallets() {
  state.walletsLoading = true;
  state.walletsError = null;
  renderWallets();
  const result = await getAdminPath(`/api/v1/admin/finance/wallets`);
  state.walletsLoading = false;
  if (result.source === "error") {
    state.wallets = [];
    state.walletsError = result.error;
  } else {
    state.wallets = rowsToObjects(result.data?.rows);
    state.walletsError = null;
  }
  renderWallets();
}

function filteredWallets() {
  const f = state.walletsFilters;
  const q = (f.search || "").trim().toLowerCase();
  return state.wallets.filter((w) => {
    if (q) {
      const hay = `${w.id} ${w.driver_id}`.toLowerCase();
      if (!hay.includes(q)) return false;
    }
    const debt = Number(w.debt_balance) || 0;
    if (f.debt === "with" && debt <= 0) return false;
    if (f.debt === "without" && debt > 0) return false;
    return true;
  });
}

function renderWalletsKPI() {
  const host = document.getElementById("wallets-kpi");
  if (!host) return;
  if (state.walletsLoading || state.walletsError || state.wallets.length === 0) {
    host.innerHTML = "";
    return;
  }
  let available = 0, pending = 0, debt = 0;
  for (const w of state.wallets) {
    available += Number(w.available_balance) || 0;
    pending += Number(w.pending_balance) || 0;
    debt += Number(w.debt_balance) || 0;
  }
  const tiles = [
    { tone: "green", label: "Доступно у водителей", value: formatMoney(available, { minor: true }) },
    { tone: "amber", label: "Ожидание (hold)", value: formatMoney(pending, { minor: true }) },
    { tone: "red", label: "Расчёты с Tow Truck (наличные)", value: formatMoney(debt, { minor: true }) },
    { tone: "neutral", label: "Кошельков", value: String(state.wallets.length) },
  ];
  host.innerHTML = tiles.map((t) => `
    <div class="kpi-card kpi-card-${escapeAttr(t.tone)}">
      <div class="kpi-label">${escapeHtml(t.label)}</div>
      <div class="kpi-value">${t.value}</div>
    </div>
  `).join("");
}

function renderWallets() {
  const filterHost = document.getElementById("wallets-filters");
  const tableHost = document.getElementById("wallets-table");
  const countLabel = document.getElementById("wallets-count-label");
  if (!filterHost || !tableHost) return;

  renderFilterBar({
    container: filterHost,
    fields: [
      { type: "search", key: "search", placeholder: "Поиск по ID кошелька или водителя", value: state.walletsFilters.search },
      {
        type: "select", key: "debt", label: "Расчёты с Tow Truck",
        options: [
          { value: "all", label: "Все" },
          { value: "with", label: "С задолженностью" },
          { value: "without", label: "Без задолженности" },
        ],
        value: state.walletsFilters.debt,
      },
    ],
    values: state.walletsFilters,
    onChange: (values) => {
      state.walletsFilters = { ...state.walletsFilters, ...values, page: 1 };
      renderWallets();
    },
    onReset: () => {
      state.walletsFilters = { search: "", debt: "all", page: 1 };
      renderWallets();
    },
  });

  renderWalletsKPI();

  if (state.walletsLoading) {
    tableHost.innerHTML = renderLoadingState();
    if (countLabel) countLabel.textContent = "—";
    return;
  }
  if (state.walletsError) {
    tableHost.innerHTML = renderErrorState({
      message: "Не удалось загрузить кошельки. Проверьте подключение и токен администратора.",
      retryId: "wallets-retry",
    });
    tableHost.querySelector("[data-retry]")?.addEventListener("click", () => loadWallets());
    if (countLabel) countLabel.textContent = "—";
    return;
  }

  const all = filteredWallets();
  if (countLabel) countLabel.textContent = `${all.length.toLocaleString("ru-RU")} кошельков`;

  const page = Math.max(1, state.walletsFilters.page || 1);
  const startIdx = (page - 1) * ADMIN_PAGE_SIZE;
  const rows = all.slice(startIdx, startIdx + ADMIN_PAGE_SIZE);

  renderDataTable({
    container: tableHost,
    rowId: (r) => r.id,
    onRowClick: (r) => openWalletDrawer(r),
    columns: [
      {
        key: "id", label: "ID кошелька",
        render: (r) => `<span class="mono">${escapeHtml(String(r.id || "").slice(0, 14))}</span>${r.id ? copyButton(r.id) : ""}`,
      },
      {
        key: "driver_id", label: "Водитель",
        render: (r) => r.driver_id
          ? `<span class="mono">${escapeHtml(String(r.driver_id).slice(0, 10))}</span>${copyButton(r.driver_id)}`
          : `<span class="muted">—</span>`,
      },
      {
        key: "available_balance", label: "Доступно",
        align: "right",
        render: (r) => formatMoney(r.available_balance, { minor: true }),
      },
      {
        key: "pending_balance", label: "Ожидание",
        align: "right",
        render: (r) => formatMoney(r.pending_balance, { minor: true }),
      },
      {
        key: "debt_balance", label: "Расчёты с Tow Truck",
        align: "right",
        render: (r) => {
          const v = Number(r.debt_balance) || 0;
          const cls = v > 0 ? "amount-debt" : "muted";
          return `<span class="${cls}">${formatMoney(r.debt_balance, { minor: true })}</span>`;
        },
      },
      { key: "currency", label: "Валюта", render: (r) => escapeHtml(r.currency || "RUB") },
      {
        key: "updated_at", label: "Обновлён",
        render: (r) => escapeHtml(formatDate(r.updated_at)),
      },
    ],
    rows,
    emptyMessage: "Кошельки не найдены",
    page,
    pageSize: ADMIN_PAGE_SIZE,
    total: all.length,
    onPage: (next) => {
      state.walletsFilters = { ...state.walletsFilters, page: next };
      renderWallets();
    },
  });
}

function openWalletDrawer(w) {
  if (!w) return;
  const debt = Number(w.debt_balance) || 0;
  openDrawer({
    title: `Кошелёк ${String(w.id || "").slice(0, 14)}`,
    subtitle: w.driver_id ? `Водитель ${String(w.driver_id).slice(0, 10)}` : "",
    contentHtml: `
      <section class="drawer-section">
        <h3>Балансы</h3>
        <dl class="info-list">
          <dt>Доступно (к выплате)</dt><dd><strong>${formatMoney(w.available_balance, { minor: true })}</strong></dd>
          <dt>Ожидание (hold)</dt><dd>${formatMoney(w.pending_balance, { minor: true })}</dd>
          <dt>Расчёты с Tow Truck</dt><dd class="${debt > 0 ? "amount-debt" : ""}">${formatMoney(w.debt_balance, { minor: true })}</dd>
          <dt>Валюта</dt><dd>${escapeHtml(w.currency || "RUB")}</dd>
          <dt>Обновлён</dt><dd>${escapeHtml(formatDate(w.updated_at))}</dd>
        </dl>
      </section>
      <section class="drawer-section">
        <h3>Реквизиты</h3>
        <dl class="info-list">
          <dt>ID кошелька</dt><dd><span class="mono">${escapeHtml(w.id || "—")}</span>${w.id ? copyButton(w.id) : ""}</dd>
          <dt>ID водителя</dt><dd>${w.driver_id ? `<span class="mono">${escapeHtml(w.driver_id)}</span>${copyButton(w.driver_id)}` : '<span class="muted">—</span>'}</dd>
        </dl>
      </section>
      <section class="drawer-section">
        <h3>Транзакции и выплаты</h3>
        <p class="muted">Полная история транзакций — в разделе «Транзакции» (с фильтром по водителю), выплаты — в разделе «Выплаты».</p>
        <div style="display:flex; gap:8px; margin-top:8px; flex-wrap:wrap;">
          ${w.driver_id ? `<button class="secondary-button" type="button" data-wallet-action="tx">Транзакции водителя →</button>` : ""}
          ${w.driver_id ? `<button class="secondary-button" type="button" data-wallet-action="payouts">Выплаты водителя →</button>` : ""}
        </div>
      </section>
    `,
    actionsHtml: `<button class="secondary-button" type="button" data-drawer-close>Закрыть</button>`,
    onMount: (drawer) => {
      drawer.querySelector('[data-wallet-action="tx"]')?.addEventListener("click", () => {
        closeDrawer();
        state.transactionsFilters = { ...state.transactionsFilters, search: w.driver_id, page: 1 };
        setTab("transactions");
      });
      drawer.querySelector('[data-wallet-action="payouts"]')?.addEventListener("click", () => {
        closeDrawer();
        state.payoutsFilters = { ...state.payoutsFilters, search: w.driver_id, page: 1 };
        setTab("payouts");
      });
    },
  });
}

// ============================================================================
// Phase 5 — Wallet Transactions
// ============================================================================

async function loadTransactions() {
  state.transactionsLoading = true;
  state.transactionsError = null;
  renderTransactions();
  const result = await getAdminPath(`/api/v1/admin/finance/transactions`);
  state.transactionsLoading = false;
  if (result.source === "error") {
    state.transactions = [];
    state.transactionsError = result.error;
  } else {
    state.transactions = rowsToObjects(result.data?.rows);
    state.transactionsError = null;
  }
  renderTransactions();
}

function filteredTransactions() {
  const f = state.transactionsFilters;
  const q = (f.search || "").trim().toLowerCase();
  return state.transactions.filter((t) => {
    if (q) {
      const hay = [t.id, t.wallet_id, t.driver_id, t.order_id, t.payment_id, t.payout_id, t.description]
        .map((v) => String(v ?? "").toLowerCase()).join(" ");
      if (!hay.includes(q)) return false;
    }
    if (f.type !== "all" && String(t.type || "").toLowerCase() !== f.type) return false;
    if (f.direction !== "all" && String(t.direction || "").toLowerCase() !== f.direction) return false;
    if (f.status !== "all" && String(t.status || "").toLowerCase() !== f.status) return false;
    if (f.from || f.to) {
      const created = new Date(t.created_at).getTime();
      if (f.from && Number.isFinite(created) && created < new Date(f.from).getTime()) return false;
      if (f.to) {
        const toTs = new Date(f.to).getTime() + 24 * 60 * 60 * 1000 - 1;
        if (Number.isFinite(created) && created > toTs) return false;
      }
    }
    return true;
  });
}

function renderTransactions() {
  const filterHost = document.getElementById("transactions-filters");
  const tableHost = document.getElementById("transactions-table");
  const countLabel = document.getElementById("transactions-count-label");
  if (!filterHost || !tableHost) return;

  renderFilterBar({
    container: filterHost,
    fields: [
      { type: "search", key: "search", placeholder: "Поиск по ID транзакции, кошелька, водителя, заказа, описанию", value: state.transactionsFilters.search },
      {
        type: "select", key: "type", label: "Тип",
        options: [
          { value: "all", label: "Все" },
          { value: "order_income", label: "Доход с заказа" },
          { value: "commission", label: "Комиссия" },
          { value: "cash_commission_debt", label: "Долг с наличных" },
          { value: "debt_repayment", label: "Погашение долга" },
          { value: "payout", label: "Выплата" },
          { value: "topup", label: "Пополнение" },
          { value: "refund", label: "Возврат" },
          { value: "subscription", label: "Подписка" },
          { value: "adjustment", label: "Корректировка" },
          { value: "hold", label: "Удержание" },
        ],
        value: state.transactionsFilters.type,
      },
      {
        type: "select", key: "direction", label: "Направление",
        options: [
          { value: "all", label: "Все" },
          { value: "in", label: "Поступление" },
          { value: "out", label: "Списание" },
          { value: "credit", label: "Credit" },
          { value: "debit", label: "Debit" },
        ],
        value: state.transactionsFilters.direction,
      },
      {
        type: "select", key: "status", label: "Статус",
        options: [
          { value: "all", label: "Все" },
          { value: "available", label: "Доступно" },
          { value: "pending", label: "Ожидает" },
          { value: "hold", label: "Удержание" },
          { value: "failed", label: "Ошибка" },
        ],
        value: state.transactionsFilters.status,
      },
      { type: "date-range", keyFrom: "from", keyTo: "to", label: "Период" },
    ],
    values: state.transactionsFilters,
    onChange: (values) => {
      state.transactionsFilters = { ...state.transactionsFilters, ...values, page: 1 };
      renderTransactions();
    },
    onReset: () => {
      state.transactionsFilters = {
        search: "", type: "all", direction: "all", status: "all",
        from: "", to: "", page: 1,
      };
      renderTransactions();
    },
  });

  if (state.transactionsLoading) {
    tableHost.innerHTML = renderLoadingState();
    if (countLabel) countLabel.textContent = "—";
    return;
  }
  if (state.transactionsError) {
    tableHost.innerHTML = renderErrorState({
      message: "Не удалось загрузить транзакции. Проверьте подключение и токен администратора.",
      retryId: "transactions-retry",
    });
    tableHost.querySelector("[data-retry]")?.addEventListener("click", () => loadTransactions());
    if (countLabel) countLabel.textContent = "—";
    return;
  }

  const all = filteredTransactions();
  if (countLabel) countLabel.textContent = `${all.length.toLocaleString("ru-RU")} транзакций`;

  const page = Math.max(1, state.transactionsFilters.page || 1);
  const startIdx = (page - 1) * ADMIN_PAGE_SIZE;
  const rows = all.slice(startIdx, startIdx + ADMIN_PAGE_SIZE);

  renderDataTable({
    container: tableHost,
    rowId: (r) => r.id,
    onRowClick: (r) => openTransactionDrawer(r),
    columns: [
      {
        key: "id", label: "ID",
        render: (r) => `<span class="mono">${escapeHtml(String(r.id || "").slice(0, 10))}</span>${r.id ? copyButton(r.id) : ""}`,
      },
      {
        key: "driver_id", label: "Водитель",
        render: (r) => r.driver_id
          ? `<span class="mono">${escapeHtml(String(r.driver_id).slice(0, 10))}</span>`
          : `<span class="muted">—</span>`,
      },
      {
        key: "type", label: "Тип",
        render: (r) => escapeHtml(labelOr(WALLET_TX_TYPE_LABELS, r.type)),
      },
      {
        key: "direction", label: "Напр.",
        render: (r) => escapeHtml(labelOr(WALLET_DIRECTION_LABELS, r.direction)),
      },
      {
        key: "amount", label: "Сумма",
        align: "right",
        render: (r) => {
          const dir = String(r.direction || "").toLowerCase();
          const isOut = dir === "out" || dir === "debit";
          const cls = isOut ? "amount-out" : "amount-in";
          const sign = isOut ? "−" : "+";
          return `<span class="${cls}">${sign} ${formatMoney(r.amount, { minor: true })}</span>`;
        },
      },
      {
        key: "status", label: "Статус",
        render: (r) => statusBadge(r.status),
      },
      {
        key: "description", label: "Описание",
        render: (r) => escapeHtml(r.description || "—"),
      },
      {
        key: "created_at", label: "Создана",
        render: (r) => escapeHtml(formatDate(r.created_at)),
      },
    ],
    rows,
    emptyMessage: "Транзакции по выбранным фильтрам не найдены",
    page,
    pageSize: ADMIN_PAGE_SIZE,
    total: all.length,
    onPage: (next) => {
      state.transactionsFilters = { ...state.transactionsFilters, page: next };
      renderTransactions();
    },
  });
}

function openTransactionDrawer(t) {
  if (!t) return;
  const dir = String(t.direction || "").toLowerCase();
  const isOut = dir === "out" || dir === "debit";
  openDrawer({
    title: `Транзакция ${String(t.id || "").slice(0, 10)}`,
    subtitle: `${labelOr(WALLET_TX_TYPE_LABELS, t.type)} · ${labelOr(WALLET_DIRECTION_LABELS, t.direction)}`,
    contentHtml: `
      <section class="drawer-section">
        <h3>Основное</h3>
        <dl class="info-list">
          <dt>ID транзакции</dt><dd><span class="mono">${escapeHtml(t.id || "—")}</span>${t.id ? copyButton(t.id) : ""}</dd>
          <dt>Тип</dt><dd>${escapeHtml(labelOr(WALLET_TX_TYPE_LABELS, t.type))}</dd>
          <dt>Направление</dt><dd>${escapeHtml(labelOr(WALLET_DIRECTION_LABELS, t.direction))}</dd>
          <dt>Сумма</dt><dd><strong class="${isOut ? "amount-out" : "amount-in"}">${isOut ? "− " : "+ "}${formatMoney(t.amount, { minor: true })}</strong> ${escapeHtml(t.currency || "RUB")}</dd>
          <dt>Статус</dt><dd>${statusBadge(t.status)}</dd>
          <dt>Создана</dt><dd>${escapeHtml(formatDate(t.created_at))}</dd>
        </dl>
      </section>
      <section class="drawer-section">
        <h3>Связи</h3>
        <dl class="info-list">
          <dt>Кошелёк</dt><dd>${t.wallet_id ? `<span class="mono">${escapeHtml(t.wallet_id)}</span>${copyButton(t.wallet_id)}` : '<span class="muted">—</span>'}</dd>
          <dt>Водитель</dt><dd>${t.driver_id ? `<span class="mono">${escapeHtml(t.driver_id)}</span>${copyButton(t.driver_id)}` : '<span class="muted">—</span>'}</dd>
          <dt>Заказ</dt><dd>${t.order_id ? `<span class="mono">${escapeHtml(t.order_id)}</span>${copyButton(t.order_id)}` : '<span class="muted">—</span>'}</dd>
          <dt>Платёж</dt><dd>${t.payment_id ? `<span class="mono">${escapeHtml(t.payment_id)}</span>${copyButton(t.payment_id)}` : '<span class="muted">—</span>'}</dd>
          <dt>Выплата</dt><dd>${t.payout_id ? `<span class="mono">${escapeHtml(t.payout_id)}</span>${copyButton(t.payout_id)}` : '<span class="muted">—</span>'}</dd>
        </dl>
        ${t.order_id ? `<div style="margin-top:8px"><button class="link-button" type="button" data-open-order="${escapeAttr(t.order_id)}">Открыть заказ →</button></div>` : ""}
      </section>
      <section class="drawer-section">
        <h3>Описание</h3>
        <p>${escapeHtml(t.description || "—")}</p>
      </section>
    `,
    actionsHtml: `<button class="secondary-button" type="button" data-drawer-close>Закрыть</button>`,
    onMount: (drawer) => {
      drawer.querySelector("[data-open-order]")?.addEventListener("click", (event) => {
        const id = event.currentTarget.getAttribute("data-open-order");
        closeDrawer();
        setTab("orders");
        openOrderDrawer(id);
      });
    },
  });
}
