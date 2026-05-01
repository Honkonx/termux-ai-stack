// src/hooks/useChatSession.js
import { useState, useRef, useCallback } from 'react';
import { postChat, clearChat, getChatHistory } from '../services/dashboard';

const CHAT_ID = 'default';

export function useChatSession(chatLoadingRef) {
  const [messages, setMessages]   = useState([]);
  const [loading, setLoading]     = useState(false);
  const [model, setModel]         = useState('');
  const [numCtx, setNumCtx]       = useState(2048);

  const loadHistory = useCallback(async () => {
    try {
      const data = await getChatHistory(CHAT_ID);
      if (data?.history) setMessages(data.history);
    } catch { /* offline */ }
  }, []);

  const send = useCallback(async (text) => {
    if (!text.trim() || loading) return;

    const userMsg = { role: 'user', content: text.trim() };
    setMessages(prev => [...prev, userMsg]);
    setLoading(true);
    if (chatLoadingRef) chatLoadingRef.current = true;

    try {
      const res = await postChat(model, text.trim(), CHAT_ID, numCtx);
      const botMsg = { role: 'assistant', content: res?.response || '…' };
      setMessages(prev => [...prev, botMsg]);
    } catch (err) {
      const errMsg = { role: 'assistant', content: '✗ Error: ' + (err.message || 'sin respuesta') };
      setMessages(prev => [...prev, errMsg]);
    } finally {
      setLoading(false);
      if (chatLoadingRef) chatLoadingRef.current = false;
    }
  }, [model, numCtx, loading, chatLoadingRef]);

  const clear = useCallback(async () => {
    try {
      await clearChat(CHAT_ID);
      setMessages([]);
    } catch { /* offline */ }
  }, []);

  return { messages, loading, model, setModel, numCtx, setNumCtx, send, clear, loadHistory };
}
