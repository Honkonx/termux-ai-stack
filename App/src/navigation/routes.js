// src/navigation/routes.js — constantes UPPER_SNAKE_CASE

export const ROUTES = {
  // Tabs principales
  MODULES:  'modules',
  CHAT:     'chat',
  SYSTEM:   'system',
  SETTINGS: 'settings',

  // Pantallas de módulo (stack sobre tab)
  N8N:    'n8n',
  OLLAMA: 'ollama',
  CLAUDE: 'claude',
  SSH:    'ssh',

  // Modal
  LOGS:   'logs',
};

export const TAB_LABELS = {
  [ROUTES.MODULES]:  { label: 'Módulos',  icon: '⊞' },
  [ROUTES.CHAT]:     { label: 'Chat IA',  icon: '◈' },
  [ROUTES.SYSTEM]:   { label: 'Sistema',  icon: '◉' },
  [ROUTES.SETTINGS]: { label: 'Config',   icon: '⚙' },
};
