// src/theme/ThemeContext.js
import { createContext, useContext, useState } from 'react';
import { THEMES } from './themes';

export const ThemeContext = createContext(null);

export function ThemeProvider({ children }) {
  const [themeName, setThemeName] = useState('noche');
  const theme = THEMES[themeName];
  return (
    <ThemeContext.Provider value={{ theme, themeName, setThemeName, THEMES }}>
      {children}
    </ThemeContext.Provider>
  );
}

export const useTheme = () => useContext(ThemeContext);
