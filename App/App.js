// termux-ai-stack · App.js
// v1.2.0 | Abril 2026
// React Native — fetch() nativo, sin WebView, sin deps nativas extra

import { StatusBar } from 'expo-status-bar';
import { useEffect, useState, useCallback } from 'react';
import {
  StyleSheet, Text, View, ScrollView,
  TouchableOpacity, RefreshControl, ActivityIndicator,
  Linking, Platform,
} from 'react-native';

// ── Config ────────────────────────────────────────────────────
const DASHBOARD_URL = 'http://localhost:8080';
const POLL_INTERVAL  = 8000;   // ms entre auto-refresh
const ACTION_TIMEOUT = 45000;  // ms máx para confirmar acción (n8n tarda ~35s)
const FETCH_TIMEOUT  = 4000;

// ── Tipos de módulo ───────────────────────────────────────────
// service  → tiene proceso background (n8n, ollama, ssh)   → botón start/stop
// tool     → sin proceso background (claude, eas, python)  → sin botón
const MODULE_TYPE = {
  n8n:    'service',
  ollama: 'service',
  ssh:    'service',
  claude: 'tool',
  eas:    'tool',
  python: 'tool',
};

// ── Colores ───────────────────────────────────────────────────
const C = {
  bg:       '#0d1117',
  surface:  '#161b22',
  border:   '#30363d',
  cyan:     '#58a6ff',
  green:    '#3fb950',
  yellow:   '#d29922',
  red:      '#f85149',
  dim:      '#8b949e',
  white:    '#e6edf3',
};

// ── Helper: fetch con timeout ─────────────────────────────────
async function fetchWithTimeout(url, opts = {}, ms = FETCH_TIMEOUT) {
  const ctrl = new AbortController();
  const id    = setTimeout(() => ctrl.abort(), ms);
  try {
    const r = await fetch(url, { ...opts, signal: ctrl.signal });
    clearTimeout(id);
    return r;
  } catch (e) {
    clearTimeout(id);
    throw e;
  }
}

// ── Componente principal ──────────────────────────────────────
export default function App() {
  const [status,      setStatus]      = useState(null);   // null = cargando
  const [error,       setError]       = useState(null);   // string = sin conexión
  const [refreshing,  setRefreshing]  = useState(false);
  const [lastSync,    setLastSync]    = useState('--');
  const [actionState, setActionState] = useState({});     // { moduleId: 'pending'|'ok'|'error' }

  // ── Obtener estado ─────────────────────────────────────────
  const fetchStatus = useCallback(async (isManual = false) => {
    if (isManual) setRefreshing(true);
    try {
      const r = await fetchWithTimeout(`${DASHBOARD_URL}/api/status`);
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const data = await r.json();
      setStatus(data);
      setError(null);
      setLastSync(new Date().toLocaleTimeString());
    } catch (e) {
      setError(e.message?.includes('aborted') ? 'timeout' : e.message);
    } finally {
      if (isManual) setRefreshing(false);
    }
  }, []);

  // ── Poll automático ────────────────────────────────────────
  useEffect(() => {
    fetchStatus();
    const id = setInterval(() => fetchStatus(), POLL_INTERVAL);
    return () => clearInterval(id);
  }, [fetchStatus]);

  // ── Ejecutar acción (start / stop) ────────────────────────
  const doAction = async (moduleId, action) => {
    setActionState(s => ({ ...s, [moduleId]: 'pending' }));
    try {
      const r = await fetchWithTimeout(
        `${DASHBOARD_URL}/api/action`,
        {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify({ module: moduleId, action }),
        },
        ACTION_TIMEOUT,
      );
      const data = await r.json();
      setActionState(s => ({ ...s, [moduleId]: data.ok ? 'ok' : 'error' }));
      // Refrescar estado después de la acción
      setTimeout(() => {
        fetchStatus();
        setActionState(s => ({ ...s, [moduleId]: null }));
      }, 2500);
    } catch (e) {
      setActionState(s => ({ ...s, [moduleId]: 'error' }));
      setTimeout(() => setActionState(s => ({ ...s, [moduleId]: null })), 3000);
    }
  };

  // ── Pantalla: sin conexión ─────────────────────────────────
  if (error !== null && status === null) {
    return (
      <View style={styles.errorScreen}>
        <StatusBar style="light" />
        <Text style={styles.hexIcon}>⬡</Text>
        <Text style={styles.errorTitle}>Dashboard no responde</Text>
        <Text style={styles.errorSub}>Abre Termux y ejecuta:</Text>
        <TouchableOpacity
          style={styles.errorCmd}
          onPress={() => {/* solo visual */}}
        >
          <Text style={styles.errorCmdText}>bash ~/dashboard_start.sh</Text>
        </TouchableOpacity>
        <Text style={styles.errorHint}>
          Luego regresa a esta app — se reconecta automáticamente.
        </Text>
        <TouchableOpacity style={styles.retryBtn} onPress={() => fetchStatus(true)}>
          <Text style={styles.retryBtnText}>↻  Reintentar ahora</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // ── Pantalla: cargando primera vez ─────────────────────────
  if (status === null) {
    return (
      <View style={styles.errorScreen}>
        <StatusBar style="light" />
        <ActivityIndicator color={C.cyan} size="large" />
        <Text style={[styles.errorSub, { marginTop: 16 }]}>Conectando...</Text>
      </View>
    );
  }

  // ── Render módulo ──────────────────────────────────────────
  const renderModule = (m) => {
    const isService = MODULE_TYPE[m.id] === 'service';
    const aState    = actionState[m.id];
    const isPending = aState === 'pending';

    // Badge de estado
    let badgeText  = 'no instalado';
    let badgeColor = C.dim;
    if (m.installed) {
      if (isService) {
        badgeText  = m.running ? 'activo'  : 'listo';
        badgeColor = m.running ? C.green   : C.yellow;
      } else {
        badgeText  = 'listo';
        badgeColor = C.yellow;
      }
    }

    // Botón acción
    let actionBtn = null;
    if (m.installed && isService) {
      if (isPending) {
        actionBtn = (
          <View style={[styles.btn, styles.btnPending]}>
            <ActivityIndicator color={C.white} size="small" />
          </View>
        );
      } else {
        const isRunning = m.running;
        actionBtn = (
          <TouchableOpacity
            style={[styles.btn, isRunning ? styles.btnStop : styles.btnStart]}
            onPress={() => doAction(m.id, isRunning ? 'stop' : 'start')}
          >
            <Text style={styles.btnText}>{isRunning ? 'stop' : 'start'}</Text>
          </TouchableOpacity>
        );
      }
    } else if (!m.installed && isService) {
      actionBtn = (
        <TouchableOpacity style={[styles.btn, styles.btnStart]}
          onPress={() => doAction(m.id, 'start')}>
          <Text style={styles.btnText}>start</Text>
        </TouchableOpacity>
      );
    }

    return (
      <View key={m.id} style={styles.moduleRow}>
        <View style={styles.moduleLeft}>
          <Text style={styles.moduleIcon}>{m.icon}</Text>
          <View style={styles.moduleInfo}>
            <View style={styles.moduleNameRow}>
              <Text style={styles.moduleName}>{m.name}</Text>
              <View style={[styles.badge, { borderColor: badgeColor }]}>
                <Text style={[styles.badgeText, { color: badgeColor }]}>{badgeText}</Text>
              </View>
            </View>
            <Text style={styles.moduleDetail}>
              {m.version ? `v${m.version}` : ''}
              {m.detail  ? `  ${m.detail}` : ''}
            </Text>
          </View>
        </View>
        {actionBtn}
      </View>
    );
  };

  // ── RAM ────────────────────────────────────────────────────
  const ram = status.ram || {};
  const ramFree = ram.available_mb
    ? `${(ram.available_mb / 1024).toFixed(0)} MB libre`
    : '--';

  // ── UI principal ───────────────────────────────────────────
  return (
    <View style={styles.root}>
      <StatusBar style="light" />

      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>termux · ai · stack</Text>
        <View style={styles.headerMeta}>
          <Text style={styles.metaText}>IP {status.ip}</Text>
          <Text style={styles.metaDot}>·</Text>
          <Text style={styles.metaText}>RAM {ramFree}</Text>
          <Text style={styles.metaDot}>·</Text>
          <Text style={styles.metaText}>sync {lastSync}</Text>
        </View>
        {/* Banner reconexión si hay error pero ya teníamos data */}
        {error && (
          <View style={styles.reconnectBanner}>
            <Text style={styles.reconnectText}>⚠ Sin conexión — reintentando...</Text>
          </View>
        )}
      </View>

      {/* Módulos */}
      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.scrollContent}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={() => fetchStatus(true)}
            tintColor={C.cyan}
          />
        }
      >
        {(status.modules || []).map(renderModule)}
      </ScrollView>
    </View>
  );
}

// ── Estilos ───────────────────────────────────────────────────
const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: C.bg,
  },

  // Header
  header: {
    paddingTop:        Platform.OS === 'android' ? 44 : 54,
    paddingHorizontal: 20,
    paddingBottom:     12,
    backgroundColor:   C.surface,
    borderBottomWidth: 1,
    borderBottomColor: C.border,
  },
  headerTitle: {
    fontSize:    18,
    fontWeight:  '700',
    color:       C.cyan,
    letterSpacing: 1,
  },
  headerMeta: {
    flexDirection: 'row',
    alignItems:    'center',
    marginTop:     4,
    flexWrap:      'wrap',
  },
  metaText: {
    fontSize: 11,
    color:    C.dim,
  },
  metaDot: {
    fontSize:     11,
    color:        C.dim,
    marginHorizontal: 6,
  },
  reconnectBanner: {
    marginTop:       8,
    backgroundColor: '#2d1a00',
    borderRadius:    6,
    paddingVertical: 4,
    paddingHorizontal: 10,
    alignSelf:       'flex-start',
  },
  reconnectText: {
    fontSize: 11,
    color:    C.yellow,
  },

  // Scroll
  scroll: { flex: 1 },
  scrollContent: { paddingVertical: 8 },

  // Módulo
  moduleRow: {
    flexDirection:     'row',
    alignItems:        'center',
    justifyContent:    'space-between',
    paddingHorizontal: 20,
    paddingVertical:   14,
    borderBottomWidth: 1,
    borderBottomColor: C.border,
  },
  moduleLeft: {
    flexDirection: 'row',
    alignItems:    'center',
    flex:          1,
  },
  moduleIcon: {
    fontSize:    20,
    color:       C.dim,
    width:       30,
  },
  moduleInfo: {
    flex:      1,
    marginLeft: 8,
  },
  moduleNameRow: {
    flexDirection: 'row',
    alignItems:    'center',
    gap:           8,
  },
  moduleName: {
    fontSize:   15,
    fontWeight: '600',
    color:      C.white,
  },
  badge: {
    borderWidth:  1,
    borderRadius: 4,
    paddingHorizontal: 6,
    paddingVertical:   1,
  },
  badgeText: {
    fontSize:   10,
    fontWeight: '600',
  },
  moduleDetail: {
    fontSize:  11,
    color:     C.dim,
    marginTop: 2,
  },

  // Botones
  btn: {
    paddingHorizontal: 16,
    paddingVertical:    8,
    borderRadius:       6,
    minWidth:          70,
    alignItems:        'center',
    justifyContent:    'center',
  },
  btnStart:   { backgroundColor: '#1f4a8a' },
  btnStop:    { backgroundColor: '#3d1f1f' },
  btnPending: { backgroundColor: '#2d2d2d' },
  btnText: {
    fontSize:   13,
    fontWeight: '600',
    color:      C.white,
  },

  // Pantalla error
  errorScreen: {
    flex:            1,
    backgroundColor: C.bg,
    alignItems:      'center',
    justifyContent:  'center',
    paddingHorizontal: 32,
  },
  hexIcon: {
    fontSize:    48,
    color:       C.cyan,
    marginBottom: 16,
  },
  errorTitle: {
    fontSize:    22,
    fontWeight:  '700',
    color:       C.white,
    marginBottom: 8,
  },
  errorSub: {
    fontSize:    14,
    color:       C.dim,
    marginBottom: 16,
  },
  errorCmd: {
    backgroundColor: C.surface,
    borderWidth:     1,
    borderColor:     C.border,
    borderRadius:    8,
    paddingVertical:   12,
    paddingHorizontal: 20,
    marginBottom:    16,
  },
  errorCmdText: {
    fontSize:   14,
    color:      C.green,
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier',
  },
  errorHint: {
    fontSize:   13,
    color:      C.dim,
    textAlign:  'center',
    marginBottom: 28,
    lineHeight: 20,
  },
  retryBtn: {
    backgroundColor: '#1f4a8a',
    borderRadius:    8,
    paddingVertical:   12,
    paddingHorizontal: 28,
  },
  retryBtnText: {
    fontSize:   14,
    fontWeight: '600',
    color:      C.white,
  },
});
