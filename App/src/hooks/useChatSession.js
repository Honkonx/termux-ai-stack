// src/hooks/useChatSession.js — v3.0.0 S19
// Chat async: POST /api/chat → job_id → polling GET /api/chat/status/<id>
// La app NO se congela — Ollama corre en hilo separado del dashboard

import { useState, useRef, useCallback, useEffect } from 'react';

const DASHBOARD       = 'http://127.0.0.1:8080';
const POLL_INTERVAL   = 2000;   // poll cada 2s
const POLL_MAX        = 90;     // máximo 90 intentos = 3 min
const FETCH_TIMEOUT   = 8000;   // timeout para cada fetch individual

async function apiFetch(path, opts = {}) {
  const ctrl  = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT);
  try {
    const res = await fetch(`${DASHBOARD}${path}`, {
      ...opts,
      signal: ctrl.signal,
    });
    clearTimeout(timer);
    return res;
  } catch (e) {
    clearTimeout(timer);
    throw e;
  }
}

export function useChatSession(model, numCtx = 2048) {
  const [messages, setMessages]         = useState([]);
  const [loading, setLoading]           = useState(false);
  const [loadingText, setLoadingText]   = useState('');
  const [error, setError]               = useState(null);
  const [historyLoading, setHistLoad]   = useState(true);
  const [chatId]                        = useState(() => `chat_${Date.now()}`);

  const pollTimerRef  = useRef(null);
  const pollCountRef  = useRef(0);
  const cancelledRef  = useRef(false);
  const mountedRef    = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    loadHistory();
    return () => {
      mountedRef.current = false;
      _stopPoll();
    };
  }, []);

  function _stopPoll() {
    if (pollTimerRef.current) {
      clearTimeout(pollTimerRef.current);
      pollTimerRef.current = null;
    }
  }

  async function loadHistory() {
    setHistLoad(true);
    try {
      const res = await apiFetch(`/api/chat/history?chat_id=${chatId}`);
      if (res.ok) {
        const data = await res.json();
        if (data.messages && mountedRef.current) {
          setMessages(data.messages.map((m, i) => ({
            id:      `h_${i}`,
            role:    m.rol || m.role,
            content: m.content,
            ts:      Date.now(),
          })));
        }
      }
    } catch { /* historial no crítico */ }
    finally { if (mountedRef.current) setHistLoad(false); }
  }

  // Polling de estado del job
  function _startPoll(jobId) {
    pollCountRef.current = 0;
    cancelledRef.current = false;

    const poll = async () => {
      if (!mountedRef.current || cancelledRef.current) return;

      pollCountRef.current += 1;

      if (pollCountRef.current > POLL_MAX) {
        _stopPoll();
        if (mountedRef.current) {
          setLoading(false);
          setError('Timeout — Ollama tardó más de 3 minutos.');
        }
        return;
      }

      try {
        const res  = await apiFetch(`/api/chat/status/${jobId}`);
        const data = await res.json();

        if (!mountedRef.current || cancelledRef.current) return;

        if (data.status === 'done') {
          _stopPoll();
          const botMsg = {
            id:      `b_${Date.now()}`,
            role:    'assistant',
            content: data.response || '(sin respuesta)',
            ts:      Date.now(),
            model,
          };
          setMessages(prev => [...prev, botMsg]);
          setLoading(false);
          setLoadingText('');
          setError(null);

        } else if (data.status === 'error') {
          _stopPoll();
          setLoading(false);
          setLoadingText('');
          setError(`Error Ollama: ${data.error}`);

        } else if (data.status === 'not_found') {
          _stopPoll();
          setLoading(false);
          setError('Job no encontrado — dashboard reiniciado?');

        } else {
          // 'processing' → seguir esperando
          const secs = pollCountRef.current * (POLL_INTERVAL / 1000);
          setLoadingText(`Ollama procesando... ${secs}s`);
          pollTimerRef.current = setTimeout(poll, POLL_INTERVAL);
        }

      } catch {
        if (!mountedRef.current || cancelledRef.current) return;
        // Error de red → reintentar
        pollTimerRef.current = setTimeout(poll, POLL_INTERVAL);
      }
    };

    pollTimerRef.current = setTimeout(poll, POLL_INTERVAL);
  }

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
    setLoadingText('Enviando...');
    setError(null);
    cancelledRef.current = false;

    try {
      const res = await apiFetch('/api/chat', {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({
          message: text.trim(),
          model,
          num_ctx: numCtx,
          chat_id: chatId,
        }),
      });

      const data = await res.json();

      if (!mountedRef.current) return;

      if (data.ok && data.job_id) {
        setLoadingText('Ollama procesando... 0s');
        _startPoll(data.job_id);
      } else {
        setLoading(false);
        setLoadingText('');
        setError(data.error || 'Error al enviar');
      }

    } catch (e) {
      if (!mountedRef.current) return;
      setLoading(false);
      setLoadingText('');
      setError(e.name === 'AbortError'
        ? 'Sin respuesta del dashboard (¿está corriendo?)'
        : `Error: ${e.message}`);
    }
  }, [loading, model, numCtx, chatId]);

  const cancelRequest = useCallback(() => {
    cancelledRef.current = true;
    _stopPoll();
    setLoading(false);
    setLoadingText('');
    setError('Cancelado');
  }, []);

  const clearHistory = useCallback(() => {
    setMessages([]);
    setError(null);
    cancelledRef.current = true;
    _stopPoll();
    setLoading(false);
  }, []);

  return {
    messages,
    loading,
    loadingText,
    error,
    historyLoading,
    sendMessage,
    cancelRequest,
    clearHistory,
  };
}
