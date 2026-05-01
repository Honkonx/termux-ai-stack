// src/hooks/useStatus.js
import { useState, useEffect, useRef } from 'react';
import { getStatus } from '../services/dashboard';

export function useStatus() {
  const [status, setStatus]   = useState(null);
  const [connErr, setConnErr] = useState(false);
  const chatLoadingRef        = useRef(false); // evita marcar error durante chat LLM

  useEffect(() => {
    let cancelled = false;

    const poll = async () => {
      try {
        const data = await getStatus();
        if (!cancelled) {
          setStatus(data);
          setConnErr(false);
        }
      } catch {
        if (!cancelled && !chatLoadingRef.current) {
          setConnErr(true);
        }
      }
    };

    poll();
    const id = setInterval(poll, 3000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  return { status, connErr, chatLoadingRef };
}
