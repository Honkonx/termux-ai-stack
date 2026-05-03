// src/theme/ThemeContext.js — v3.0.0 FINAL
// ════════════════════════════════════════════════════════════
// REGLA: package.json solo tiene expo, expo-build-properties,
//        expo-status-bar, react, react-native — NADA MÁS.
//
// SOLUCIÓN: persistencia via dashboard /api/prefs (HTTP fetch
// builtin — ya funciona en toda la app) + cache en variable
// de módulo para acceso síncrono entre renders.
//
// Sin imports externos. Sin AsyncStorage. Sin SecureStore.
// Sin expo-file-system. Solo fetch nativo de React Native.
// ════════════════════════════════════════════════════════════

import React, { createContext, useContext, useState, useEffect, useRef } from 'react';
import { ThemeNoche, ThemeOceano, ThemeDia } from './themes';

const THEMES = {
  noche:  { ...ThemeNoche,  name: 'noche'  },
  oceano: { ...ThemeOceano, name: 'oceano' },
  dia:    { ...ThemeDia,    name: 'dia'    },
};

const DASHBOARD    = 'http://127.0.0.1:8080';
const DEFAULT      = 'noche';
const TIMEOUT_MS   = 3000;

// Cache de módulo — persiste mientras la app está en memoria
// y da acceso síncrono sin latencia en renders subsiguientes
let _memTheme = DEFAULT;

const ThemeContext = createContext(null);

export function ThemeProvider({ children }) {
  const [themeName, setThemeState] = useState(_memTheme);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    _loadFromDashboard();
    return () => { mountedRef.current = false; };
  }, []);

  async function _loadFromDashboard() {
    try {
      const ctrl  = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
      const res   = await fetch(`${DASHBOARD}/api/prefs`, { signal: ctrl.signal });
      clearTimeout(timer);
      if (res.ok) {
        const data = await res.json();
        if (data.theme && THEMES[data.theme] && mountedRef.current) {
          _memTheme = data.theme;
          setThemeState(data.theme);
        }
      }
    } catch {
      // Dashboard no disponible → usar cache/default. No crashear.
    }
  }

  async function _saveToDashboard(name) {
    try {
      const ctrl  = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
      await fetch(`${DASHBOARD}/api/prefs`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ theme: name }),
        signal:  ctrl.signal,
      });
      clearTimeout(timer);
    } catch {
      // No crítico — el tema ya cambió en UI
    }
  }

  // setThemeName — nombre exacto que usa SettingsScreen.js
  const setThemeName = (name) => {
    if (!THEMES[name]) return;
    _memTheme = name;
    setThemeState(name);
    _saveToDashboard(name);
  };

  // NUNCA retornar null — evita crash de árbol de componentes
  return (
    <ThemeContext.Provider value={{
      theme:       THEMES[themeName],
      themeName,
      setThemeName,
      setTheme:    setThemeName, // alias por compatibilidad
    }}>
      {children}
    </ThemeContext.Provider>
  );
}

export const useTheme = () => useContext(ThemeContext);
