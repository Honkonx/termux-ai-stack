// src/theme/themes.js
// SURFACE: Negro puro (#000) como base — máximo contraste para dev nocturno
// JERARQUÍA: 4 niveles f4→a1→52→textCode
// ACENTO: Azul eléctrico #3d7aed (Noche) · #58a6ff (Océano) · #2563eb (Día)
// BORDES: rgba con baja opacidad — encontrar, no ver
// DENSIDAD: Compacta — herramienta dev, info densa

export const ThemeNoche = {
  bg:          '#000000',
  surface:     '#0a0a0a',
  card:        '#111111',
  cardActive:  '#161616',
  overlay:     '#1a1a1a',

  border:      'rgba(255,255,255,0.07)',
  borderFocus: 'rgba(61,122,237,0.35)',

  accent:      '#3d7aed',
  accentDim:   '#1a2d5a',
  accentGlow:  'rgba(61,122,237,0.13)',

  success:     '#22c55e',
  successDim:  '#052e16',
  warning:     '#f59e0b',
  warningDim:  '#292100',
  error:       '#ef4444',
  errorDim:    '#2d0707',
  info:        '#06b6d4',

  textPrimary: '#f4f4f5',
  textSecond:  '#a1a1aa',
  textMuted:   '#52525b',
  textCode:    '#4ade80',

  chatUser:    '#1a2d5a',
  chatBot:     '#111111',

  name: 'noche',
};

export const ThemeOceano = {
  bg:          '#0d1117',
  surface:     '#13181f',
  card:        '#161b22',
  cardActive:  '#1c2230',
  overlay:     '#0d1117',

  border:      'rgba(255,255,255,0.08)',
  borderFocus: 'rgba(56,139,253,0.27)',

  accent:      '#58a6ff',
  accentDim:   '#1f3a5f',
  accentGlow:  'rgba(56,139,253,0.13)',

  success:     '#3fb950',
  successDim:  '#1a3a22',
  warning:     '#d29922',
  warningDim:  '#3a2e10',
  error:       '#f85149',
  errorDim:    '#3a1a1a',
  info:        '#58a6ff',

  textPrimary: '#e6edf3',
  textSecond:  '#8b949e',
  textMuted:   '#6e7681',
  textCode:    '#3fb950',

  chatUser:    '#1f3a5f',
  chatBot:     '#161b22',

  name: 'oceano',
};

export const ThemeDia = {
  bg:          '#ffffff',
  surface:     '#f8fafc',
  card:        '#f1f5f9',
  cardActive:  '#e2e8f0',
  overlay:     '#f8fafc',

  border:      'rgba(0,0,0,0.08)',
  borderFocus: 'rgba(37,99,235,0.33)',

  accent:      '#2563eb',
  accentDim:   '#dbeafe',
  accentGlow:  'rgba(59,130,246,0.13)',

  success:     '#16a34a',
  successDim:  '#dcfce7',
  warning:     '#d97706',
  warningDim:  '#fef3c7',
  error:       '#dc2626',
  errorDim:    '#fee2e2',
  info:        '#0891b2',

  textPrimary: '#0f172a',
  textSecond:  '#475569',
  textMuted:   '#94a3b8',
  textCode:    '#16a34a',

  chatUser:    '#dbeafe',
  chatBot:     '#f1f5f9',

  name: 'dia',
};

export const THEMES = {
  noche:  ThemeNoche,
  oceano: ThemeOceano,
  dia:    ThemeDia,
};
