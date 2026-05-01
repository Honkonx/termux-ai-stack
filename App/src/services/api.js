// src/services/api.js
// fetch wrapper con timeout explícito — sin axios, sin requests

export const BASE_URL = 'http://localhost:8080';
export const DEFAULT_TIMEOUT = 5000;

export async function apiFetch(path, options = {}, timeout = DEFAULT_TIMEOUT) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const res = await fetch(BASE_URL + path, {
      ...options,
      signal: controller.signal,
    });
    clearTimeout(timer);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  } catch (err) {
    clearTimeout(timer);
    throw err;
  }
}
