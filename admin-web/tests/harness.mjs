// Test harness: loads admin-web/static/app.js in a minimal browser-global
// sandbox so we can unit-test its pure functions with node:test.
//
// Usage: node --test tests/audit.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const APP_JS = new URL('../static/app.js', import.meta.url);
const src = fs.readFileSync(APP_JS, 'utf8');

// --- Minimal DOM/browser shims sufficient to load the file without throwing. ---
function makeEl() {
  const el = {
    style: {}, dataset: {}, classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
    attributes: {}, children: [],
    setAttribute(k, v) { this.attributes[k] = v; },
    getAttribute(k) { return this.attributes[k]; },
    removeAttribute(k) { delete this.attributes[k]; },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    addEventListener() {}, removeEventListener() {},
    appendChild() {}, remove() {}, removeChild() {},
    closest() { return null; }, focus() {}, click() {},
    get innerHTML() { return this._h || ''; }, set innerHTML(v) { this._h = v; },
    get textContent() { return this._t || ''; }, set textContent(v) { this._t = v; },
    getElementById() { return null; },
  };
  return el;
}

const documentStub = {
  body: makeEl(),
  documentElement: makeEl(),
  createElement() { return makeEl(); },
  getElementById() { return makeEl(); },
  querySelector() { return makeEl(); },
  querySelectorAll() { return []; },
  addEventListener() {}, removeEventListener() {},
};

const windowStub = {
  location: { hash: '', protocol: 'http:', host: 'localhost' },
  addEventListener() {}, removeEventListener() {},
};
const localStorageStub = (() => {
  const m = new Map();
  return {
    getItem: (k) => (m.has(k) ? m.get(k) : null),
    setItem: (k, v) => m.set(k, String(v)),
    removeItem: (k) => m.delete(k),
  };
})();

const sandbox = {
  console,
  Intl,
  Date,
  Math,
  JSON,
  URL,
  URLSearchParams,
  setTimeout,
  clearTimeout,
  setInterval,
  clearInterval,
  performance: { now: () => Date.now() },
  navigator: { clipboard: { writeText: async () => {} } },
  localStorage: localStorageStub,
  document: documentStub,
  window: windowStub,
  L: undefined,
};
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(src, sandbox, { filename: 'app.js' });

// Expose the pure functions we want to test.
const F = sandbox;

export { test, assert, F };
