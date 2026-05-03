// src/hooks/useChatSession.js — v2.0.0
// Fix Bug #4: timeout largo + estado loading visible + no bloquea poll de status
//
// REGLAS APLICADAS:
// - HTTP: fetch builtin con AbortController (NO axios, NO requests)
// - SQLite: datos via API del dashboard (NO AsyncStorage para historial)
// - useEffect siempre con cleanup

import { useState, useRef, useCallback, useEffect } from 'react';

const DASHBOARD_URL = 'http://127.0.0.1:8080';
// Ollama local puede tardar 60s+ en responder — timeout generoso
const CHAT_TIMEOUT_MS = 90_000;
// Timeout para cargar historial
const HISTORY_TIMEOUT_MS = 10_000;

export function useChatSession(model, numCtx = 2048) {
  const [messages, setMessages]   = useState([]);
  const [loading, setLoading]     = useState(false);  // true mientras Ollama procesa
  const [error, setError]         = useState(null);
  const [chatId, setChatId]       = useState(null);
  const [historyLoading, setHistoryLoading] = useState(true);

  // Ref para que el poll de useStatus.js sepa no marcar connErr durante chat
  const loadingRef = useRef(false);
  const abortRef   = useRef(null);

  // Sincronizar ref con estado
  useEffect(() => {
    loadingRef.current = loading;
  }, [loading]);

  // Inicializar chat_id al montar (un UUID simple basado en timestamp)
  useEffect(() => {
    const id = `chat_${Date.now()}`;
    setChatId(id);
    loadHistory(id);

    return () => {
      // Cancelar request en vuelo si el componente se desmonta
      if (abortRef.current) abortRef.current.abort();
    };
  }, []);

  const loadHistory = useCallback(async (id) => {
    setHistoryLoading(true);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), HISTORY_TIMEOUT_MS);

    try {
      const res = await fetch(
        `${DASHBOARD_URL}/api/chat/history?chat_id=${id}`,
        { signal: controller.signal }
      );
      if (res.ok) {
        const data = await res.json();
        if (data.messages && Array.isArray(data.messages)) {
          setMessages(data.messages);
        }
      }
    } catch {
      // Historial no crítico — continuar sin él
    } finally {
      clearTimeout(timer);
      setHistoryLoading(false);
    }
  }, []);

  const sendMessage = useCallback(async (text) => {
    if (!text.trim() || loading) return;

    const userMsg = {
      id:      `u_${Date.now()}`,
      role:    'user',
      content: text.trim(),
      ts:      Date.now(),
    };

    setMessages(prev => [...prev, userMsg]);
    setLoading(true);
    setError(null);

    // Cancelar request anterior si hubiera
    if (abortRef.current) abortRef.current.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const timer = setTimeout(() => controller.abort(), CHAT_TIMEOUT_MS);

    try {
      const res = await fetch(`${DASHBOARD_URL}/api/chat`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({
          message:  text.trim(),
          model:    model,
          num_ctx:  numCtx,
          chat_id:  chatId,
        }),
        signal: controller.signal,
      });

      clearTimeout(timer);

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }

      const data = await res.json();

      const botMsg = {
        id:      `b_${Date.now()}`,
        role:    'assistant',
        content: data.response || '(sin respuesta)',
        ts:      Date.now(),
        model:   model,
      };

      setMessages(prev => [...prev, botMsg]);
      setError(null);

    } catch (err) {
      clearTimeout(timer);

      if (err.name === 'AbortError') {
        setError('timeout — Ollama tardó más de 90s. Intenta con un modelo más pequeño.');
      } else {
        setError(`Error: ${err.message}`);
      }
    } finally {
      setLoading(false);
      abortRef.current = null;
    }
  }, [loading, model, numCtx, chatId]);

  const clearHistory = useCallback(async () => {
    setMessages([]);
    setError(null);
    // Generar nuevo chat_id para nueva sesión limpia
    const newId = `chat_${Date.now()}`;
    setChatId(newId);
  }, []);

  const cancelRequest = useCallback(() => {
    if (abortRef.current) {
      abortRef.current.abort();
      abortRef.current = null;
      setLoading(false);
      setError('Cancelado');
    }
  }, []);

  return {
    messages,
    loading,
    error,
    historyLoading,
    sendMessage,
    clearHistory,
    cancelRequest,
    loadingRef,   // exportar para que useStatus.js no marque connErr durante chat
  };
}
