const state = {
  activeTab: "dashboard",
  moderationFilter: "all",
  selectedCaseId: null,
  config: null,
  source: "loading",
  overview: null,
  verifications: [],
  users: [],
  reviews: [],
  onlineDrivers: [],
};

const pageMeta = {
  dashboard: ["Обзор", "Операционная панель модерации и контроля EVIK"],
  moderation: ["Модерация", "Проверка водителей, документов и рисков"],
  users: ["Пользователи", "Клиенты, водители, блокировки и активность"],
  reviews: ["Отзывы", "Оценки клиентов и звезды водителей"],
  map: ["Карта водителей", "Водители онлайн и на смене"],
  settings: ["Настройки", "Подключение локального сайта к серверу приложения"],
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

  const [overview, verifications, users, reviews, onlineDrivers] = await Promise.all([
    getAdminData("overview"),
    getAdminData("driver-verifications"),
    getAdminData("users"),
    getAdminData("reviews"),
    getAdminData("drivers-online"),
  ]);

  state.overview = normalizeOverview(overview.data);
  state.verifications = normalizeItems(verifications.data);
  state.users = normalizeItems(users.data);
  state.reviews = normalizeItems(reviews.data);
  state.onlineDrivers = normalizeItems(onlineDrivers.data);
  state.source = [overview, verifications, users, reviews, onlineDrivers].some((item) => item.source === "error")
    ? "error"
    : "api";

  if (!state.selectedCaseId && state.verifications.length > 0) {
    state.selectedCaseId = state.verifications[0].id;
  }

  setSource(state.source);
  renderAll();
}

async function getAdminData(resource) {
  const adminPath = `/api/v1/admin/${resource}`;
  try {
    const response = await fetch(adminPath, {
      headers: authHeaders(),
    });
    if (!response.ok) throw new Error(`API ${response.status}`);
    return { source: "api", data: await response.json() };
  } catch (error) {
    console.error(`Admin API failed for ${resource}`, error);
    return { source: "error", data: emptyAdminPayload(resource), error };
  }
}

function emptyAdminPayload(resource) {
  if (resource === "overview") return {};
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
}

function setSource(source) {
  const pill = document.getElementById("data-source-pill");
  pill.classList.remove("mock", "error");
  if (source === "loading") {
    pill.textContent = "Проверка API";
    return;
  }
  if (source === "mock") {
    pill.textContent = "Fallback данные";
    pill.classList.add("mock");
    return;
  }
  if (source === "error") {
    pill.textContent = "API error";
    pill.classList.add("error");
    return;
  }
  pill.textContent = "Real API";
}

function renderOverview() {
  const overview = state.overview || {};
  const metrics = [
    ["Пользователи", overview.total_users ?? 0, "US", "rgba(59, 130, 246, 0.12)", "var(--blue)"],
    ["Водители", overview.drivers ?? 0, "DR", "rgba(16, 185, 129, 0.12)", "var(--green)"],
    ["Онлайн на смене", overview.online_drivers ?? state.onlineDrivers.length, "GPS", "rgba(245, 158, 11, 0.14)", "var(--amber)"],
    ["На модерации", overview.pending_moderations ?? pendingCount(), "MOD", "rgba(255, 107, 53, 0.13)", "var(--accent)"],
    ["Средняя оценка", formatStarsValue(overview.average_driver_stars), "RT", "rgba(245, 158, 11, 0.14)", "var(--amber)"],
    ["Отзывы сегодня", overview.reviews_today ?? 0, "RV", "rgba(59, 130, 246, 0.12)", "var(--blue)"],
    ["Активные заказы", overview.active_orders ?? 0, "ORD", "rgba(16, 185, 129, 0.12)", "var(--green)"],
    ["Клиенты", overview.clients ?? 0, "CL", "rgba(107, 114, 128, 0.12)", "var(--muted)"],
  ];

  document.getElementById("overview-metrics").innerHTML = metrics
    .map(([title, value, icon, bg, color]) => `
      <article class="metric-card">
        <div class="metric-icon" style="background:${bg}; color:${color}">${escapeHtml(icon)}</div>
        <div>
          <div class="metric-value">${escapeHtml(value)}</div>
          <div class="metric-title">${escapeHtml(title)}</div>
        </div>
      </article>
    `)
    .join("");

  document.getElementById("pending-count-label").textContent = `${pendingCount()} в очереди`;
  document.getElementById("online-count-label").textContent = `${state.onlineDrivers.length} на смене`;
  document.getElementById("dashboard-moderation-list").innerHTML = state.verifications
    .slice(0, 4)
    .map(renderCaseCard)
    .join("") || empty("Заявок нет");

  renderMap(document.getElementById("dashboard-mini-map"), state.onlineDrivers, false);
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
    const nextStatus = action === "approve" ? "approved" : action === "reject" ? "rejected" : action === "block" ? "blocked" : "changes_requested";
    state.verifications = state.verifications.map((item) => item.id === id ? { ...item, status: nextStatus } : item);
    state.source = "mock";
    setSource("mock");
    renderAll();
    showToast("Backend admin endpoint пока недоступен. Решение применено локально.");
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
