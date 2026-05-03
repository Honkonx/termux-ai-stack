// src/theme/ThemeContext.js — v2.0.0
// Fix Bug #3: Persistencia de tema con AsyncStorage
// AsyncStorage es correcto aquí — es preferencia de UI local, no dato del stack

import React, { createContext, useContext, useState, useEffect } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { ThemeNoche, ThemeOceano, ThemeDia } from './themes';

const THEMES = {
  noche:  { ...ThemeNoche,  name: 'noche'  },
  oceano: { ...ThemeOceano, name: 'oceano' },
  dia:    { ...ThemeDia,    name: 'dia'    },
};

const THEME_KEY = '@termux_ai_stack:theme';
const DEFAULT_THEME = 'noche';

const ThemeContext = createContext(null);

export function ThemeProvider({ children }) {
  const [themeName, setThemeName] = useState(DEFAULT_THEME);
  const [loaded, setLoaded] = useState(false);

  // Cargar tema guardado al iniciar
  useEffect(() => {
    AsyncStorage.getItem(THEME_KEY)
      .then(saved => {
        if (saved && THEMES[saved]) {
          setThemeName(saved);
        }
      })
      .catch(() => {
        // Si falla AsyncStorage usar default — no crashear
      })
      .finally(() => {
        setLoaded(true);
      });
  }, []);

  // Cambiar tema y persistir
  const setTheme = (name) => {
    if (!THEMES[name]) return;
    setThemeName(name);
    AsyncStorage.setItem(THEME_KEY, name).catch(() => {
      // Silenciar error de escritura — no crítico
    });
  };

  // No renderizar hasta cargar el tema guardado (evita flash)
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
