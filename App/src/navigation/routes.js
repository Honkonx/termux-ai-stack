// App/src/navigation/routes.js
// v1.1.0 — S19: agregado ROUTES.PYTHON

export const ROUTES = {
  // Tabs raíz
  MODULES:  'modules',
  CHAT:     'chat',
  SYSTEM:   'system',
  SETTINGS: 'settings',

  // Pantallas de módulo (se apilan sobre el tab MODULES)
  N8N:    'n8n',
  OLLAMA: 'ollama',
  CLAUDE: 'claude',
  SSH:    'ssh',
  PYTHON: 'python',   // ← nuevo S19
};

export const TAB_LABELS = {
  [ROUTES.MODULES]:  'Módulos',
  [ROUTES.CHAT]:     'Chat IA',
  [ROUTES.SYSTEM]:   'Sistema',
  [ROUTES.SETTINGS]: 'Config',
};
