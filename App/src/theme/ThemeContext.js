// src/theme/ThemeContext.js — v2.1.0
// Fix Bug #3: Persistencia de tema con expo-file-system
// expo-file-system YA ESTÁ incluido en Expo SDK ~50.0.0 — sin instalar nada
// NO usa @react-native-async-storage (no está en package.json → rompe build)

import React, { createContext, useContext, useState, useEffect, useRef } from 'react';
import * as FileSystem from 'expo-file-system';
import { ThemeNoche, ThemeOceano, ThemeDia } from './themes';

const THEMES = {
  noche:  { ...ThemeNoche,  name: 'noche'  },
  oceano: { ...ThemeOceano, name: 'oceano' },
  dia:    { ...ThemeDia,    name: 'dia'    },
};

// Guardar fuera de /tmp (noexec en Android 15) — regla del proyecto
const PREFS_PATH = FileSystem.documentDirectory + 'ui_prefs.json';
const DEFAULT_THEME = 'noche';

const ThemeContext = createContext(null);

export function ThemeProvider({ children }) {
  const [themeName, setThemeName] = useState(DEFAULT_THEME);
  const [loaded, setLoaded] = useState(false);
  const mountedRef = useRef(true);

  useEffect(() => {
    mountedRef.current = true;
    loadTheme();
    return () => { mountedRef.current = false; };
  }, []);

  async function loadTheme() {
    try {
      const info = await FileSystem.getInfoAsync(PREFS_PATH);
      if (info.exists) {
        const raw = await FileSystem.readAsStringAsync(PREFS_PATH);
        const prefs = JSON.parse(raw);
        if (prefs.theme && THEMES[prefs.theme] && mountedRef.current) {
          setThemeName(prefs.theme);
        }
      }
    } catch {
      // Archivo no existe o JSON inválido → usar default noche
    } finally {
      if (mountedRef.current) setLoaded(true);
    }
  }

  async function saveTheme(name) {
    try {
      await FileSystem.writeAsStringAsync(
        PREFS_PATH,
        JSON.stringify({ theme: name }),
        { encoding: FileSystem.EncodingType.UTF8 }
      );
    } catch {
      // No es crítico — silenciar
    }
  }

  const setTheme = (name) => {
    if (!THEMES[name]) return;
    setThemeName(name);
    saveTheme(name);
  };

  // Evitar flash de tema incorrecto antes de leer el archivo
  if (!loaded) return null;

  return (
    <ThemeContext.Provider value={{
      theme: THEMES[themeName],
      themeName,
      setTheme,
    }}>
      {children}
    </ThemeContext.Provider>
  );
}

export const useTheme = () => useContext(ThemeContext);
