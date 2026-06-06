// src/services/dashboard.js — endpoints del dashboard_server.py v2.1.0
import { apiFetch } from './api';

// ── GET ───────────────────────────────────────────────────────────────
export const getStatus        = ()         => apiFetch('/api/status');
export const getOllamaModels  = ()         => apiFetch('/api/ollama/models');
export const getSshInfo       = ()         => apiFetch('/api/ssh/info');
export const getN8nInfo       = ()         => apiFetch('/api/n8n/info');
export const getN8nLogs       = ()         => apiFetch('/api/n8n/logs', {}, 8000);
export const getLogs          = ()         => apiFetch('/api/logs');
export const getChatHistory   = (chat_id)  => apiFetch(`/api/chat/history?chat_id=${chat_id}`);

// ── POST ──────────────────────────────────────────────────────────────
export const postAction = (module, action) =>
  apiFetch('/api/action', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ module, action }),
  });

export const postChat = (model, message, chat_id, num_ctx) =>
  apiFetch('/api/chat', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, message, chat_id, num_ctx }),
  }, 130000); // timeout largo para LLM

export const postN8nToken = (token, remove = false) =>
  apiFetch('/api/n8n/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token, remove }),
  });

export const postN8nWebhook = (webhook_url) =>
  apiFetch('/api/n8n/webhook', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ webhook_url }),
  });

export const postClaudeConfig = (api_key, endpoint) =>
  apiFetch('/api/claude/config', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ api_key, endpoint }),
  });

export const clearChat = (chat_id) =>
  apiFetch('/api/chat/clear', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id }),
  });

export const deleteOllamaModel = (model) =>
  apiFetch('/api/ollama/delete', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model }),
  });

export const pullOllamaModel = (model) =>
  apiFetch('/api/ollama/pull', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model }),
  }, 300000); // 5 min para descarga

// ── OpenCode ─────────────────────────────────────────────────
export const getOpenCodeInfo = () =>
  apiFetch('/api/opencode/info');

// ── OpenClaw ─────────────────────────────────────────────────
export const getOpenClawInfo = () =>
  apiFetch('/api/openclaw/info');

// ── OpenClaude ───────────────────────────────────────────────
export const getOpenClaudeInfo = () =>
  apiFetch('/api/openclaude/info');

export const postOpenClaudeProvider = (provider, model, base_url, api_key) =>
  apiFetch('/api/openclaude/provider', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ provider, model, base_url, api_key }),
  });
