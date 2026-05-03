// src/theme/ThemeContext.js — v2.3.0
// Persistencia con expo-secure-store (incluido en Expo SDK ~50.0.0)
// Si SecureStore falla → persiste solo en sesión, no crashea
// NUNCA retorna null — sin crash de árbol de componentes

import React, { createContext, useContext, useState, useEffect, useRef } from 'react';
import * as SecureStore from 'expo-secure-store';
import { ThemeNoche, ThemeOceano, ThemeDia } from './themes';

const THEMES = {
  noche:  { ...ThemeNoche,  name: 'noche'  },
  oceano: { ...ThemeOceano, name: 'oceano' },
  dia:    { ...ThemeDia,    name: 'dia'    },
};

const STORE_KEY     = 'ui_theme';
const DEFAULT_THEME = 'noche';

const ThemeContext = createContext(null);

// Cache en memoria — acceso síncrono sin latencia
let _cachedTheme = DEFAULT_THEME;

export function ThemeProvider({ children }) {
  const [themeName, setThemeState] = useState(_cachedTheme);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    // Cargar tema guardado al iniciar — async, no bloquea render
    SecureStore.getItemAsync(STORE_KEY)
      .then(saved => {
        if (saved && THEMES[saved] && mountedRef.current) {
          _cachedTheme = saved;
          setThemeState(saved);
        }
      })
      .catch(() => {
        // SecureStore no disponible — usar default
      });
    return () => { mountedRef.current = false; };
  }, []);

  const setThemeName = (name) => {
    if (!THEMES[name]) return;
    _cachedTheme = name;
    setThemeState(name);
    // Guardar async — no bloquea ni crashea si falla
    SecureStore.setItemAsync(STORE_KEY, name).catch(() => {});
  };

  // NUNCA retornar null
  return (
    <ThemeContext.Provider value={{
      theme: THEMES[themeName],
      themeName,
      setThemeName,          // ← SettingsScreen usa este
      setTheme: setThemeName, // ← alias por compatibilidad
    }}>
      {children}
    </ThemeContext.Provider>
  );
}

export const useTheme = () => useContext(ThemeContext);
