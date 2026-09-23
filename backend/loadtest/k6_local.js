import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://127.0.0.1:18080';
const OTP = __ENV.OTP_CODE || '424242';
let clientToken = '';
let authAttempted = false;

export const options = {
  scenarios: {
    health: {
      executor: 'ramping-vus',
      stages: [
        { target: Number(__ENV.HEALTH_VUS || 10), duration: '30s' },
        { target: Number(__ENV.HEALTH_VUS || 10), duration: __ENV.HEALTH_HOLD || '2m' },
        { target: 0, duration: '15s' },
      ],
      exec: 'healthScenario',
      tags: { scenario: 'health' },
    },
    authenticated: {
      executor: 'ramping-vus',
      startVUs: 2,
      stages: [
        { target: Number(__ENV.AUTH_VUS || 10), duration: '30s' },
        { target: Number(__ENV.AUTH_VUS || 10), duration: __ENV.AUTH_HOLD || '2m' },
        { target: 0, duration: '15s' },
      ],
      gracefulRampDown: '10s',
      exec: 'authenticatedScenario',
      tags: { scenario: 'authenticated' },
    },
    order_create: {
      executor: 'constant-vus',
      vus: Number(__ENV.ORDER_VUS || 2),
      duration: __ENV.ORDER_DURATION || '30s',
      exec: 'orderScenario',
      tags: { scenario: 'order_create' },
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    'http_req_failed{endpoint:auth_otp_request}': ['rate<0.01'],
    'http_req_failed{endpoint:auth_otp_verify}': ['rate<0.01'],
    'http_req_failed{endpoint:auth_me}': ['rate<0.01'],
    'http_req_failed{endpoint:orders_active}': ['rate<0.01'],
    'http_req_failed{endpoint:pricing_calculate}': ['rate<0.01'],
    'http_req_failed{endpoint:order_create}': ['rate<0.01'],
    'http_req_duration{scenario:health}': ['p(95)<500', 'p(99)<1000'],
    'http_req_duration{scenario:authenticated}': ['p(95)<1500', 'p(99)<3000'],
    'http_req_duration{scenario:order_create}': ['p(95)<3000', 'p(99)<5000'],
    checks: ['rate>0.95'],
  },
};

function jsonParams(token) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  return { headers, tags: { component: 'api' } };
}

function authenticate(role = 'client', phoneBase) {
  const id = __VU || 1;
  const phone = `+${String(Number(phoneBase) + id)}`;
  const params = jsonParams();
  const request = http.post(
    `${BASE}/api/v1/auth/otp/request`,
    JSON.stringify({ phone, role }),
    { ...params, tags: { endpoint: 'auth_otp_request' } },
  );
  check(request, { 'otp request accepted': (r) => r.status === 202 || r.status === 200 });
  const verify = http.post(
    `${BASE}/api/v1/auth/otp/verify`,
    JSON.stringify({ phone, code: OTP, role, full_name: `EVIK-E2E ${role} ${id}` }),
    { ...params, tags: { endpoint: 'auth_otp_verify' } },
  );
  const body = verify.json();
  const token = body && body.tokens && body.tokens.access_token;
  check(verify, { 'otp verify issued token': (r) => r.status === 200 && !!token });
  return token;
}

export function healthScenario() {
  const response = http.get(`${BASE}/healthz`, { tags: { endpoint: 'healthz' } });
  check(response, { 'health is 200': (r) => r.status === 200 && r.body === 'ok' });
  sleep(1);
}

export function authenticatedScenario() {
  if (!authAttempted) {
    authAttempted = true;
    clientToken = authenticate('client', __ENV.AUTH_PHONE_BASE || '79992000000') || '';
  }
  const token = clientToken;
  if (!token) {
    sleep(1);
    return;
  }
  const params = jsonParams(token);
  const responses = http.batch([
    ['GET', `${BASE}/api/v1/auth/me`, null, { ...params, tags: { endpoint: 'auth_me' } }],
    ['GET', `${BASE}/api/v1/orders/active`, null, { ...params, tags: { endpoint: 'orders_active' } }],
    ['POST', `${BASE}/api/v1/pricing/calculate`, JSON.stringify({
      pickup_lat: 42.9764, pickup_lng: 47.5024,
      dropoff_lat: 42.9864, dropoff_lng: 47.5124,
      tow_truck_type: 'winch',
    }), { ...params, tags: { endpoint: 'pricing_calculate' } }],
  ]);
  check(responses[0], { 'auth me succeeds': (r) => r.status === 200 });
  check(responses[1], { 'active orders responds': (r) => r.status === 200 });
  check(responses[2], { 'pricing responds': (r) => r.status === 200 });
  sleep(1);
}

export function orderScenario() {
  if (!authAttempted) {
    authAttempted = true;
    clientToken = authenticate('client', __ENV.ORDER_PHONE_BASE || '79993000000') || '';
  }
  const token = clientToken;
  if (!token) {
    sleep(1);
    return;
  }
  const variant = (__VU + __ITER) % 4;
  const routes = [
    [42.9764, 47.5024, 42.9864, 47.5124],
    [42.9700, 47.4950, 42.9950, 47.5250],
    [42.9600, 47.4900, 42.9850, 47.5300],
    [42.9800, 47.5200, 42.9650, 47.4800],
  ];
  const types = ['winch', 'platform', 'manipulator', 'winch'];
  const route = routes[variant];
  const response = http.post(`${BASE}/api/v1/orders`, JSON.stringify({
    pickup_lat: route[0], pickup_lng: route[1],
    dropoff_lat: route[2], dropoff_lng: route[3],
    payment_method: 'cash', auto_dispatch: true,
    tow_truck_type: types[variant], notes: `k6-local-load-test-v${variant}`,
  }), { ...jsonParams(token), tags: { scenario: 'order_create', endpoint: 'order_create', variant: String(variant) } });
  check(response, { 'order create accepted': (r) => r.status === 201 || r.status === 200 });
  sleep(1);
}

export function handleSummary(data) {
  const summaryPath = __ENV.SUMMARY_PATH || 'k6-summary.json';
  return {
    stdout: JSON.stringify(data, null, 2),
    [summaryPath]: JSON.stringify(data, null, 2),
  };
}
