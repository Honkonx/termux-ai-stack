// src/hooks/useAction.js
import { useState, useRef } from 'react';
import { postAction, getStatus } from '../services/dashboard';

// Estados: idle | loading | success | error
export function useAction(moduleId) {
  const [actionState, setActionState] = useState('idle');
  const [message, setMessage]         = useState('');
  const pollRef = useRef(null);

  const clearPoll = () => {
    if (pollRef.current) {
      clearInterval(pollRef.current);
      pollRef.current = null;
    }
  };

  const trigger = async (action) => {
    setActionState('loading');
    setMessage(action === 'start' ? '⏳ Iniciando...' : '⏳ Deteniendo...');
    clearPoll();

    try {
      await postAction(moduleId, action);
    } catch (err) {
      setActionState('error');
      setMessage('✗ Sin respuesta');
      setTimeout(() => setActionState('idle'), 3000);
      return;
    }

    // Poll de confirmación — máx 12s (4 intentos × 3s)
    let attempts = 0;
    const maxAttempts = 4;
    const expectedActive = action === 'start';

    pollRef.current = setInterval(async () => {
      attempts++;
      try {
        const data = await getStatus();
        const mod  = data?.modules?.[moduleId];
        const isActive = mod?.active === true;

        if (isActive === expectedActive) {
          clearPoll();
          setActionState('success');
          setMessage(expectedActive ? '✓ Activo' : '✓ Detenido');
          setTimeout(() => setActionState('idle'), 2500);
          return;
        }
      } catch { /* sigue intentando */ }

      if (attempts >= maxAttempts) {
        clearPoll();
        setActionState('error');
        setMessage('✗ Sin confirmación');
        setTimeout(() => setActionState('idle'), 3000);
      }
    }, 3000);
  };

  return { actionState, message, trigger };
}
