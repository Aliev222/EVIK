import vm from 'node:vm';
import { test, assert, F } from './harness.mjs';

const state = vm.runInContext('state', F);
const api = vm.runInContext('api', F);
const response = (body, status = 200) => ({
  status, ok: status < 400, statusText: 'Server error',
  text: async () => JSON.stringify(body),
});

test('admin writes are never retried after network loss or server failure', async () => {
  const originalFetch = F.fetch;
  try {
    for (const method of ['POST', 'PUT', 'PATCH', 'DELETE']) {
      for (const failure of ['network', 'server']) {
        let calls = 0;
        F.fetch = async () => {
          calls++;
          if (failure === 'network') throw new Error('response lost');
          return response({ error: 'upstream failure' }, 503);
        };
        await assert.rejects(api.request(method, '/admin/mutation', { body: {}, retries: 3 }));
        assert.equal(calls, 1, `${method} ${failure} was repeated`);
      }
    }
  } finally { F.fetch = originalFetch; }
});

test('read requests recover from a transient server error', async () => {
  const originalFetch = F.fetch;
  let calls = 0;
  F.fetch = async () => ++calls === 1 ? response({}, 503) : response({ recovered: true });
  try {
    assert.equal((await api.get('/admin/overview')).recovered, true);
    assert.equal(calls, 2);
  } finally { F.fetch = originalFetch; }
});

test('dashboard toggle stays off across refresh and chart totals match selected days', async () => {
  const originalFetch = F.fetch;
  const originalById = F.document.getElementById;
  const originalQuery = F.document.querySelector;
  const originalConnect = F.connectWs;
  const originalChart = F.renderLineChart;
  const auto = {};
  const main = { isConnected: true, innerHTML: '', querySelectorAll: () => [] };
  state.token = 'test';
  state.route = { name: 'dashboard', params: {} };
  state.dashPeriod = 7;
  state.dashAutoRefreshEnabled = true;
  F.document.getElementById = id => id === 'dash-auto-refresh' ? auto : null;
  F.document.querySelector = () => null;
  F.connectWs = () => {};
  F.renderLineChart = () => '';
  F.fetch = async () => response({
    gmv_month: 99999999, commission_month: 88888888,
    gmv_by_day: Array.from({ length: 30 }, (_, i) => ({ date: `2026-09-${String(i + 1).padStart(2, '0')}`, amount: 10000 })),
    commission_by_day: [],
  });
  try {
    await F.pageDashboard(main);
    assert.match(main.innerHTML, /Авто: ВКЛ/);
    assert.ok(state.dashAutoRefresh);
    assert.ok(main.innerHTML.includes(`<div class="dash-card-figure">${F.formatMoneyMinor(70000)}</div>`));
    auto.onclick();
    await new Promise(resolve => setImmediate(resolve));
    assert.match(main.innerHTML, /Авто: ВЫКЛ/);
    assert.equal(state.dashAutoRefresh, null);
    await F.pageDashboard(main);
    assert.equal(state.dashAutoRefresh, null);
  } finally {
    F.stopDashAutoRefresh();
    F.fetch = originalFetch;
    F.document.getElementById = originalById;
    F.document.querySelector = originalQuery;
    F.connectWs = originalConnect;
    F.renderLineChart = originalChart;
    state.token = null;
  }
});

test('dashboard response arriving after navigation cannot paint or restart a session', async () => {
  const originalFetch = F.fetch;
  let resolveFetch;
  F.fetch = () => new Promise(resolve => { resolveFetch = resolve; });
  state.token = 'test';
  state.route = { name: 'dashboard', params: {} };
  const main = { isConnected: true, innerHTML: '', querySelectorAll: () => [] };
  try {
    const pending = F.pageDashboard(main);
    const skeleton = main.innerHTML;
    state.route = { name: 'orders', params: {} };
    main.isConnected = false;
    resolveFetch(response({}));
    await pending;
    assert.equal(main.innerHTML, skeleton);
    assert.equal(state.dashAutoRefresh, null);
  } finally { F.fetch = originalFetch; state.token = null; F.stopDashAutoRefresh(); }
});

test('logout closes admin socket and ignores its late callbacks', () => {
  const originalWs = F.WebSocket;
  let socket;
  F.WebSocket = class {
    static OPEN = 1;
    static CONNECTING = 0;
    constructor() { this.readyState = 0; socket = this; }
    close() { this.closed = true; this.onclose?.(); }
    send() {}
  };
  try {
    state.token = 'test';
    state.route = { name: 'dashboard', params: {} };
    F.connectWs();
    socket.onopen();
    assert.equal(state.wsConnected, true);
    F.logout();
    socket.onopen();
    socket.onclose();
    assert.equal(socket.closed, true);
    assert.equal(state.wsConnected, false);
    assert.equal(state.ws, null);
    assert.equal(state.wsReconnectTimer, null);
  } finally { F.disconnectWs(); F.WebSocket = originalWs; }
});

test('direct driver detail URL works without a previous hashchange', async () => {
  const originalDetail = F.pageDriverDetail;
  const originalHash = F.window.location.hash;
  const originalLocation = F.location;
  F.location = F.window.location;
  F.window.location.hash = '#/drivers/driver-42';
  delete F.window.__G;
  let selected;
  F.pageDriverDetail = async (_main, id) => { selected = id; };
  try {
    await F.pageDrivers({});
    assert.equal(selected, 'driver-42');
  } finally { F.pageDriverDetail = originalDetail; F.window.location.hash = originalHash; F.location = originalLocation; }
});
