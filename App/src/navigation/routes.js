// App/src/navigation/routes.js
// v1.2.0 — S19: TAB_LABELS con {label, icon} para TabBar

export const ROUTES = {
  // Tabs raíz
  MODULES:  'modules',
  CHAT:     'chat',
  SYSTEM:   'system',
  SETTINGS: 'settings',

  // Pantallas de módulo (se apilan sobre el tab MODULES)
  N8N:       'n8n',
  OLLAMA:    'ollama',
  CLAUDE:    'claude',
  SSH:       'ssh',
  PYTHON:    'python',
  OPENCODE:  'opencode',
  OPENCLAW:  'openclaw',
  OPENCLAUDE:'openclaude',
};

export const TAB_LABELS = {
  [ROUTES.MODULES]:  { label: 'Módulos',  icon: '⊞' },
  [ROUTES.CHAT]:     { label: 'Chat IA',  icon: '◇' },
  [ROUTES.SYSTEM]:   { label: 'Sistema',  icon: '⊙' },
  [ROUTES.SETTINGS]: { label: 'Config',   icon: '⚙' },
};
