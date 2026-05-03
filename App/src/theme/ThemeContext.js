// src/theme/ThemeContext.js — v2.2.0
// - Sin expo-file-system (puede fallar en runtime)
// - Sin AsyncStorage (no está en package.json)
// - Persistencia via dashboard API (mismo fetch que usa toda la app)
// - Exporta setThemeName para compatibilidad con SettingsScreen.js
// - NUNCA retorna null — evita crash de árbol de componentes

import React, { createContext, useContext, useState, useEffect, useRef } from 'react';
import { ThemeNoche, ThemeOceano, ThemeDia } from './themes';

const THEMES = {
  noche:  { ...ThemeNoche,  name: 'noche'  },
  oceano: { ...ThemeOceano, name: 'oceano' },
  dia:    { ...ThemeDia,    name: 'dia'    },
};

const DASHBOARD = 'http://127.0.0.1:8080';
const DEFAULT_THEME = 'noche';

const ThemeContext = createContext(null);

export function ThemeProvider({ children }) {
  const [themeName, setThemeState] = useState(DEFAULT_THEME);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    // Cargar tema guardado del dashboard al iniciar
    loadTheme();
    return () => { mountedRef.current = false; };
  }, []);

  async function loadTheme() {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 3000);
      const res = await fetch(`${DASHBOARD}/api/prefs`, { signal: controller.signal });
      clearTimeout(timer);
      if (res.ok) {
        const data = await res.json();
        if (data.theme && THEMES[data.theme] && mountedRef.current) {
          setThemeState(data.theme);
        }
      }
    } catch {
      // Dashboard no responde → usar default — no crashear
    }
  }

  async function saveTheme(name) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 3000);
      await fetch(`${DASHBOARD}/api/prefs`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ theme: name }),
        signal: controller.signal,
      });
      clearTimeout(timer);
    } catch {
      // No es crítico — silenciar
    }
  }

  // setThemeName — nombre idéntico al que usa SettingsScreen.js
  const setThemeName = (name) => {
    if (!THEMES[name]) return;
    setThemeState(name);
    saveTheme(name);
  };

  // NUNCA retornar null — siempre renderizar con el tema disponible
  return (
    <ThemeContext.Provider value={{
      theme: THEMES[themeName],
      themeName,
      setThemeName,   // ← compatible con SettingsScreen.js existente
      setTheme: setThemeName,  // ← alias por si algo lo usa
    }}>
      {children}
    </ThemeContext.Provider>
  );
}

export const useTheme = () => useContext(ThemeContext);
