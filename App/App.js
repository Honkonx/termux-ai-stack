// termux-ai-stack · App.js
// v1.3.0 | Abril 2026
// Tabs: Módulos / Sistema · Submenús · Polling real · Backup/Restore

import { StatusBar } from 'expo-status-bar';
import { useEffect, useState, useCallback, useRef } from 'react';
import {
  StyleSheet, Text, View, ScrollView,
  TouchableOpacity, RefreshControl, ActivityIndicator,
  Platform, Alert,
} from 'react-native';

// ─────────────────────────────────────────────
//  CONFIG
// ─────────────────────────────────────────────
const DASHBOARD_URL   = 'http://localhost:8080';
const POLL_INTERVAL   = 3000;   // auto-refresh cada 3s
const FETCH_TIMEOUT   = 4000;
const ACTION_POLL_MS  = 2000;   // polling post-acción cada 2s
const ACTION_POLL_MAX = 25;     // máx 25 intentos = 50s (cubre n8n ~35s)

// service: tiene proceso background → botón start/stop
// tool:    herramienta CLI           → sin botón, solo info
const MODULE_TYPE = {
  n8n:    'service',
  ollama: 'service',
  ssh:    'service',
  claude: 'tool',
  eas:    'tool',
  python: 'tool',
};

// Info estática para los submenús de detalle
const MODULE_INFO = {
  n8n: {
    desc:  'Automatización de workflows. Corre en proot Debian, expuesto vía Cloudflare Tunnel.',
    port:  '5678 (interno) · tunnel público',
    layer: 'proot Debian',
    cmds:  ['bash ~/start_servidor.sh', 'pkill -f "n8n start"', 'n8n-url  → ver URL pública'],
  },
  ollama: {
    desc:  'Servidor LLM local. Modelos recomendados para POCO F5: qwen2.5:0.5b (~400MB) o qwen2.5:1.5b (~1GB).',
    port:  ':11434',
    layer: 'Termux nativo',
    cmds:  ['ollama serve', 'ollama run qwen2.5:0.5b', 'ollama list', 'ollama pull qwen2.5:0.5b'],
    warn:  '⚠ Bug #27290 activo: rendimiento reducido hasta fix oficial de termux-packages.',
  },
  claude: {
    desc:  'Agente de código IA. Versión fija 2.1.111 — versiones superiores requieren glibc incompatible con Bionic libc.',
    port:  'N/A — herramienta CLI',
    layer: 'Termux nativo',
    cmds:  ['claude', 'claude -p "instrucción"', 'claude --version', 'claude --continue'],
  },
  eas: {
    desc:  'CLI para compilar APKs en la nube sin Android Studio ni PC. Compila en servidores de Expo.',
    port:  'N/A — herramienta CLI',
    layer: 'Termux nativo',
    cmds:  [
      'EAS_SKIP_AUTO_FINGERPRINT=1 eas build --platform android --profile preview',
      'eas build:list',
      'eas whoami',
      'eas login',
    ],
  },
  python: {
    desc:  'Python 3.13. Usado por dashboard_server.py y futuros scripts de trading (ccxt, pandas-ta).',
    port:  'N/A — herramienta',
    layer: 'Termux nativo',
    cmds:  [
      'python3 script.py',
      'pip install paquete --break-system-packages',
      'python3 -m http.server 8888',
    ],
  },
  ssh: {
    desc:  'Servidor SSH para acceso remoto desde PC en la misma red WiFi. Puerto 8022 sin root.',
    port:  ':8022',
    layer: 'Termux nativo',
    cmds:  ['sshd', 'pkill sshd', 'ssh -p 8022 user@IP  (desde PC)'],
  },
};

// ─────────────────────────────────────────────
//  COLORES
// ─────────────────────────────────────────────
const C = {
  bg:      '#0d1117',
  surface: '#161b22',
  border:  '#30363d',
  cyan:    '#58a6ff',
  green:   '#3fb950',
  yellow:  '#d29922',
  red:     '#f85149',
  dim:     '#8b949e',
  white:   '#e6edf3',
  card:    '#1c2128',
};

// ─────────────────────────────────────────────
//  HELPER fetch con timeout
// ─────────────────────────────────────────────
async function apiFetch(path, opts = {}, ms = FETCH_TIMEOUT) {
  const ctrl = new AbortController();
  const id   = setTimeout(() => ctrl.abort(), ms);
  try {
    const r = await fetch(DASHBOARD_URL + path, { ...opts, signal: ctrl.signal });
    clearTimeout(id);
    return r;
  } catch (e) {
    clearTimeout(id);
    throw e;
  }
}

// ─────────────────────────────────────────────
//  APP
// ─────────────────────────────────────────────
export default function App() {
  const [status,       setStatus]      = useState(null);
  const [connError,    setConnError]   = useState(false);
  const [refreshing,   setRefreshing]  = useState(false);
  const [lastSync,     setLastSync]    = useState('--');
  const [actionState,  setActionState] = useState({});
  const [activeTab,    setActiveTab]   = useState('modules');
  const [detailMod,    setDetailMod]   = useState(null);
  const [logs,         setLogs]        = useState([]);
  const pollRef = useRef({});

  // ── Fetch estado ──────────────────────────────────────────
  const fetchStatus = useCallback(async (manual = false) => {
    if (manual) setRefreshing(true);
    try {
      const r = await apiFetch('/api/status');
      if (!r.ok) throw new Error();
      const d = await r.json();
      setStatus(d);
      setConnError(false);
      setLastSync(new Date().toLocaleTimeString());
    } catch {
      setConnError(true);
    } finally {
      if (manual) setRefreshing(false);
    }
  }, []);

  // ── Fetch logs ────────────────────────────────────────────
  const fetchLogs = useCallback(async () => {
    try {
      const r = await apiFetch('/api/logs');
      if (r.ok) { const d = await r.json(); setLogs(d.logs || []); }
    } catch {}
  }, []);

  // ── Poll automático ───────────────────────────────────────
  useEffect(() => {
    fetchStatus();
    const id = setInterval(fetchStatus, POLL_INTERVAL);
    return () => clearInterval(id);
  }, [fetchStatus]);

  // ── Polling post-acción (confirma cambio real de proceso) ─
  const startActionPoll = useCallback((moduleId, expectedRunning) => {
    let attempts = 0;
    setActionState(s => ({ ...s, [moduleId]: 'confirming' }));
    const id = setInterval(async () => {
      attempts++;
      try {
        const r = await apiFetch('/api/status');
        const d = await r.json();
        const m = (d.modules || []).find(x => x.id === moduleId);
        if (m && m.running === expectedRunning) {
          setStatus(d);
          setLastSync(new Date().toLocaleTimeString());
          clearInterval(id);
          delete pollRef.current[moduleId];
          setActionState(s => ({ ...s, [moduleId]: 'ok' }));
          setTimeout(() => setActionState(s => ({ ...s, [moduleId]: null })), 1800);
          return;
        }
      } catch {}
      if (attempts >= ACTION_POLL_MAX) {
        clearInterval(id);
        delete pollRef.current[moduleId];
        setActionState(s => ({ ...s, [moduleId]: 'error' }));
        setTimeout(() => setActionState(s => ({ ...s, [moduleId]: null })), 3000);
      }
    }, ACTION_POLL_MS);
    pollRef.current[moduleId] = id;
  }, []);

  // ── Ejecutar acción ───────────────────────────────────────
  const doAction = useCallback(async (moduleId, action) => {
    if (pollRef.current[moduleId]) {
      clearInterval(pollRef.current[moduleId]);
      delete pollRef.current[moduleId];
    }
    setActionState(s => ({ ...s, [moduleId]: 'pending' }));
    try {
      const r = await apiFetch('/api/action', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ module: moduleId, action }),
      });
      const d = await r.json();
      if (d.ok) {
        startActionPoll(moduleId, action === 'start');
      } else {
        setActionState(s => ({ ...s, [moduleId]: 'error' }));
        setTimeout(() => setActionState(s => ({ ...s, [moduleId]: null })), 3000);
      }
    } catch {
      setActionState(s => ({ ...s, [moduleId]: 'error' }));
      setTimeout(() => setActionState(s => ({ ...s, [moduleId]: null })), 3000);
    }
  }, [startActionPoll]);

  // ── Backup ────────────────────────────────────────────────
  const doBackup = useCallback(() => {
    Alert.alert('Backup', '¿Crear backup del stack ahora?', [
      { text: 'Cancelar', style: 'cancel' },
      {
        text: 'Crear backup', onPress: async () => {
          try {
            const r = await apiFetch('/api/action', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ module: 'system', action: 'backup' }),
            });
            const d = await r.json();
            Alert.alert(d.ok ? '✓ Backup creado' : '✗ Error', d.msg || '');
          } catch {
            Alert.alert('Error', 'No se pudo conectar al dashboard.');
          }
        },
      },
    ]);
  }, []);

  // ── Cleanup ───────────────────────────────────────────────
  useEffect(() => () => Object.values(pollRef.current).forEach(clearInterval), []);

  // ════════════════════════════════════════════
  //  PANTALLA: sin conexión
  // ════════════════════════════════════════════
  if (connError && status === null) {
    return (
      <View style={s.center}>
        <StatusBar style="light" />
        <Text style={s.hexBig}>⬡</Text>
        <Text style={s.errTitle}>Dashboard no responde</Text>
        <Text style={s.errSub}>Abre Termux y ejecuta:</Text>
        <View style={s.codeBox}>
          <Text style={s.codeText}>bash ~/dashboard_start.sh</Text>
        </View>
        <Text style={s.errHint}>Luego regresa — se reconecta automáticamente.</Text>
        <TouchableOpacity style={s.retryBtn} onPress={() => fetchStatus(true)}>
          <Text style={s.retryText}>↻  Reintentar</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // ════════════════════════════════════════════
  //  PANTALLA: cargando
  // ════════════════════════════════════════════
  if (status === null) {
    return (
      <View style={s.center}>
        <StatusBar style="light" />
        <ActivityIndicator color={C.cyan} size="large" />
        <Text style={[s.errSub, { marginTop: 16 }]}>Conectando...</Text>
      </View>
    );
  }

  // ════════════════════════════════════════════
  //  PANTALLA: detalle de módulo
  // ════════════════════════════════════════════
  if (detailMod) {
    // Siempre usar datos frescos del status
    const m         = (status.modules || []).find(x => x.id === detailMod.id) || detailMod;
    const info      = MODULE_INFO[m.id] || {};
    const isService = MODULE_TYPE[m.id] === 'service';
    const aState    = actionState[m.id];
    const isPending = aState === 'pending' || aState === 'confirming';

    let statusColor = C.dim;
    let statusLabel = 'no instalado';
    if (m.installed) {
      statusLabel = isService ? (m.running ? 'activo' : 'listo') : 'listo';
      statusColor = (isService && m.running) ? C.green : C.yellow;
    }

    return (
      <View style={s.root}>
        <StatusBar style="light" />
        <View style={s.header}>
          <TouchableOpacity onPress={() => setDetailMod(null)} style={{ marginBottom: 10 }}>
            <Text style={{ fontSize: 14, color: C.cyan }}>← Volver</Text>
          </TouchableOpacity>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
            <Text style={{ fontSize: 22 }}>{m.icon}</Text>
            <Text style={s.detailTitle}>{m.name}</Text>
            <View style={[s.badge, { borderColor: statusColor }]}>
              <Text style={[s.badgeText, { color: statusColor }]}>{statusLabel}</Text>
            </View>
          </View>
          {m.version ? <Text style={{ fontSize: 12, color: C.dim, marginTop: 4 }}>v{m.version}</Text> : null}
        </View>

        <ScrollView style={s.scroll} contentContainerStyle={{ padding: 16 }}>

          {/* Descripción */}
          <View style={s.card}>
            <Text style={s.cardLabel}>DESCRIPCIÓN</Text>
            <Text style={s.cardBody}>{info.desc || '—'}</Text>
          </View>

          {/* Info técnica */}
          <View style={s.card}>
            <Text style={s.cardLabel}>INFO TÉCNICA</Text>
            <InfoRow k="Puerto"   v={info.port  || '—'} />
            <InfoRow k="Capa"     v={info.layer || '—'} />
            {m.detail ? <InfoRow k="Detalle" v={m.detail} /> : null}
          </View>

          {/* Advertencia */}
          {info.warn ? (
            <View style={[s.card, { borderColor: C.yellow + '66' }]}>
              <Text style={{ fontSize: 13, color: C.yellow, lineHeight: 20 }}>{info.warn}</Text>
            </View>
          ) : null}

          {/* Control start/stop */}
          {m.installed && isService ? (
            <View style={s.card}>
              <Text style={s.cardLabel}>CONTROL</Text>
              {isPending ? (
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 4 }}>
                  <ActivityIndicator color={C.cyan} />
                  <Text style={{ color: C.dim, fontSize: 13 }}>
                    {aState === 'pending' ? 'Enviando comando...' : 'Esperando confirmación...'}
                  </Text>
                </View>
              ) : (
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: 4 }}>
                  <TouchableOpacity
                    style={[s.bigBtn, m.running ? s.btnStop : s.btnStart]}
                    onPress={() => doAction(m.id, m.running ? 'stop' : 'start')}
                  >
                    <Text style={s.bigBtnText}>{m.running ? '■  Detener' : '▶  Iniciar'}</Text>
                  </TouchableOpacity>
                  {aState === 'ok'    && <Text style={{ color: C.green }}>✓ Confirmado</Text>}
                  {aState === 'error' && <Text style={{ color: C.red  }}>✗ Sin respuesta</Text>}
                </View>
              )}
            </View>
          ) : null}

          {/* Comandos */}
          {info.cmds?.length ? (
            <View style={s.card}>
              <Text style={s.cardLabel}>COMANDOS EN TERMUX</Text>
              {info.cmds.map((c, i) => (
                <View key={i} style={s.cmdBox}>
                  <Text style={s.cmdText}>{c}</Text>
                </View>
              ))}
            </View>
          ) : null}

          <View style={{ height: 32 }} />
        </ScrollView>
      </View>
    );
  }

  // ════════════════════════════════════════════
  //  UI PRINCIPAL
  // ════════════════════════════════════════════
  const ram    = status.ram || {};
  const ramStr = ram.available_mb ? `${ram.available_mb} MB libre` : '--';

  return (
    <View style={s.root}>
      <StatusBar style="light" />

      {/* Header */}
      <View style={s.header}>
        <Text style={s.headerTitle}>termux · ai · stack</Text>
        <View style={s.headerMeta}>
          <Text style={s.metaText}>IP {status.ip}</Text>
          <Text style={s.metaDot}>·</Text>
          <Text style={s.metaText}>RAM {ramStr}</Text>
          <Text style={s.metaDot}>·</Text>
          <Text style={s.metaText}>sync {lastSync}</Text>
        </View>
        {connError && (
          <View style={s.warnBanner}>
            <Text style={s.warnText}>⚠ Sin conexión — reintentando...</Text>
          </View>
        )}
      </View>

      {/* Tab bar */}
      <View style={s.tabBar}>
        {[
          { key: 'modules', label: '⬡  Módulos' },
          { key: 'system',  label: '◎  Sistema'  },
        ].map(tab => (
          <TouchableOpacity
            key={tab.key}
            style={[s.tab, activeTab === tab.key && s.tabActive]}
            onPress={() => {
              setActiveTab(tab.key);
              if (tab.key === 'system') fetchLogs();
            }}
          >
            <Text style={[s.tabText, activeTab === tab.key && s.tabTextActive]}>
              {tab.label}
            </Text>
          </TouchableOpacity>
        ))}
      </View>

      {/* ═══ TAB: MÓDULOS ═══ */}
      {activeTab === 'modules' && (
        <ScrollView
          style={s.scroll}
          contentContainerStyle={s.scrollContent}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={() => fetchStatus(true)} tintColor={C.cyan} />
          }
        >
          {(status.modules || []).map(m => {
            const isService = MODULE_TYPE[m.id] === 'service';
            const aState    = actionState[m.id];
            const isPending = aState === 'pending' || aState === 'confirming';

            let badgeText  = 'no instalado';
            let badgeColor = C.dim;
            if (m.installed) {
              badgeText  = isService ? (m.running ? 'activo' : 'listo') : 'listo';
              badgeColor = (isService && m.running) ? C.green : C.yellow;
            }

            return (
              <TouchableOpacity
                key={m.id}
                style={s.moduleRow}
                onPress={() => setDetailMod(m)}
                activeOpacity={0.7}
              >
                <View style={s.moduleLeft}>
                  <Text style={s.moduleIcon}>{m.icon}</Text>
                  <View style={s.moduleInfo}>
                    <View style={s.moduleNameRow}>
                      <Text style={s.moduleName}>{m.name}</Text>
                      <View style={[s.badge, { borderColor: badgeColor }]}>
                        <Text style={[s.badgeText, { color: badgeColor }]}>{badgeText}</Text>
                      </View>
                    </View>
                    <Text style={s.moduleDetail}>
                      {m.version ? `v${m.version}` : ''}
                      {m.detail  ? `  ${m.detail}` : ''}
                    </Text>
                  </View>
                </View>

                {m.installed && isService ? (
                  isPending ? (
                    <View style={[s.btn, s.btnPending]}>
                      <ActivityIndicator color={C.white} size="small" />
                    </View>
                  ) : (
                    <TouchableOpacity
                      style={[s.btn, m.running ? s.btnStop : s.btnStart]}
                      onPress={() => doAction(m.id, m.running ? 'stop' : 'start')}
                      hitSlop={{ top: 8, bottom: 8, left: 4, right: 4 }}
                    >
                      <Text style={s.btnText}>{m.running ? 'stop' : 'start'}</Text>
                    </TouchableOpacity>
                  )
                ) : (
                  <Text style={s.arrow}>›</Text>
                )}
              </TouchableOpacity>
            );
          })}

          {/* Backup / Restore */}
          <View style={s.separator} />
          <View style={s.sectionHeader}>
            <Text style={s.sectionTitle}>SISTEMA</Text>
          </View>

          <TouchableOpacity style={s.moduleRow} onPress={doBackup} activeOpacity={0.7}>
            <View style={s.moduleLeft}>
              <Text style={s.moduleIcon}>💾</Text>
              <View style={s.moduleInfo}>
                <Text style={s.moduleName}>Backup</Text>
                <Text style={s.moduleDetail}>Guardar registry + configs en /sdcard</Text>
              </View>
            </View>
            <Text style={s.arrow}>›</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={s.moduleRow}
            onPress={() => Alert.alert('Restore', 'Para restaurar ejecuta en Termux:\n\nbash ~/restore.sh\n\nO usa el menú: opción [0] → Restore')}
            activeOpacity={0.7}
          >
            <View style={s.moduleLeft}>
              <Text style={s.moduleIcon}>♻️</Text>
              <View style={s.moduleInfo}>
                <Text style={s.moduleName}>Restore</Text>
                <Text style={s.moduleDetail}>bash ~/restore.sh desde Termux</Text>
              </View>
            </View>
            <Text style={s.arrow}>›</Text>
          </TouchableOpacity>

          <View style={{ height: 32 }} />
        </ScrollView>
      )}

      {/* ═══ TAB: SISTEMA ═══ */}
      {activeTab === 'system' && (
        <ScrollView style={s.scroll} contentContainerStyle={{ padding: 16 }}>

          <View style={s.card}>
            <Text style={s.cardLabel}>SISTEMA</Text>
            <InfoRow k="IP WiFi"    v={status.ip} />
            <InfoRow k="RAM libre"  v={ramStr} />
            <InfoRow k="RAM total"  v={ram.total_mb ? `${(ram.total_mb/1024).toFixed(1)} GB` : '--'} />
            <InfoRow k="Dashboard"  v=":8080 activo" vc={C.green} />
            <InfoRow k="Último sync" v={lastSync} />
          </View>

          <View style={s.card}>
            <Text style={s.cardLabel}>MÓDULOS</Text>
            {(status.modules || []).map(m => {
              const isService = MODULE_TYPE[m.id] === 'service';
              const color = !m.installed ? C.dim
                : (isService && m.running) ? C.green : C.yellow;
              const label = !m.installed ? 'no instalado'
                : isService ? (m.running ? 'activo' : 'listo')
                : `listo${m.version ? ' · v'+m.version : ''}`;
              return <InfoRow key={m.id} k={`${m.running ? '●' : '○'} ${m.name}`} v={label} kc={color} vc={color} />;
            })}
          </View>

          <View style={s.card}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
              <Text style={s.cardLabel}>ÚLTIMAS ACCIONES</Text>
              <TouchableOpacity onPress={fetchLogs}>
                <Text style={{ color: C.cyan, fontSize: 12 }}>↻ actualizar</Text>
              </TouchableOpacity>
            </View>
            {logs.length === 0 ? (
              <Text style={{ fontSize: 13, color: C.dim }}>Sin acciones registradas.</Text>
            ) : (
              logs.slice().reverse().map((l, i) => (
                <View key={i} style={{ flexDirection: 'row', marginBottom: 5, gap: 8 }}>
                  <Text style={{ fontSize: 11, color: C.dim, width: 58 }}>{l.ts}</Text>
                  <Text style={{ fontSize: 11, color: l.ok ? C.green : C.red, flex: 1 }}>
                    {l.module} {l.action} {l.ok ? '✓' : '✗'}
                  </Text>
                </View>
              ))
            )}
          </View>

          <View style={s.card}>
            <Text style={s.cardLabel}>COMANDOS ÚTILES</Text>
            {['bash ~/dashboard_start.sh', 'bash ~/dashboard_stop.sh', 'menu', 'bash ~/backup.sh'].map((c, i) => (
              <View key={i} style={s.cmdBox}>
                <Text style={s.cmdText}>{c}</Text>
              </View>
            ))}
          </View>

          <View style={{ height: 32 }} />
        </ScrollView>
      )}
    </View>
  );
}

// ─────────────────────────────────────────────
//  Componente InfoRow reutilizable
// ─────────────────────────────────────────────
function InfoRow({ k, v, kc, vc }) {
  return (
    <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginBottom: 7 }}>
      <Text style={{ fontSize: 13, color: kc || C.dim,   flex: 1 }}>{k}</Text>
      <Text style={{ fontSize: 13, color: vc || C.white, flex: 2, textAlign: 'right' }}>{v}</Text>
    </View>
  );
}

// ─────────────────────────────────────────────
//  ESTILOS
// ─────────────────────────────────────────────
const s = StyleSheet.create({
  root:          { flex: 1, backgroundColor: C.bg },
  scroll:        { flex: 1 },
  scrollContent: { paddingVertical: 4 },

  center: {
    flex: 1, backgroundColor: C.bg,
    alignItems: 'center', justifyContent: 'center',
    paddingHorizontal: 32,
  },
  hexBig:   { fontSize: 52, color: C.cyan, marginBottom: 16 },
  errTitle: { fontSize: 22, fontWeight: '700', color: C.white, marginBottom: 8 },
  errSub:   { fontSize: 14, color: C.dim, marginBottom: 16 },
  errHint:  { fontSize: 13, color: C.dim, textAlign: 'center', marginBottom: 28, lineHeight: 20 },
  codeBox: {
    backgroundColor: C.surface, borderWidth: 1, borderColor: C.border,
    borderRadius: 8, paddingVertical: 12, paddingHorizontal: 20, marginBottom: 16,
  },
  codeText: {
    fontSize: 13, color: C.green,
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier',
  },
  retryBtn: {
    backgroundColor: '#1f4a8a', borderRadius: 8,
    paddingVertical: 12, paddingHorizontal: 28,
  },
  retryText: { fontSize: 14, fontWeight: '600', color: C.white },

  header: {
    paddingTop: Platform.OS === 'android' ? 44 : 54,
    paddingHorizontal: 16, paddingBottom: 10,
    backgroundColor: C.surface,
    borderBottomWidth: 1, borderBottomColor: C.border,
  },
  headerTitle: { fontSize: 17, fontWeight: '700', color: C.cyan, letterSpacing: 1 },
  headerMeta:  { flexDirection: 'row', alignItems: 'center', marginTop: 3, flexWrap: 'wrap' },
  metaText:    { fontSize: 11, color: C.dim },
  metaDot:     { fontSize: 11, color: C.dim, marginHorizontal: 5 },
  warnBanner: {
    marginTop: 6, backgroundColor: '#2d1a00',
    borderRadius: 5, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'flex-start',
  },
  warnText:    { fontSize: 11, color: C.yellow },
  detailTitle: { fontSize: 18, fontWeight: '700', color: C.white },

  tabBar: {
    flexDirection: 'row', backgroundColor: C.surface,
    borderBottomWidth: 1, borderBottomColor: C.border,
  },
  tab:          { flex: 1, paddingVertical: 10, alignItems: 'center', borderBottomWidth: 2, borderBottomColor: 'transparent' },
  tabActive:    { borderBottomColor: C.cyan },
  tabText:      { fontSize: 12, color: C.dim,  fontWeight: '500' },
  tabTextActive:{ fontSize: 12, color: C.cyan, fontWeight: '700' },

  moduleRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 13,
    borderBottomWidth: 1, borderBottomColor: C.border,
  },
  moduleLeft:    { flexDirection: 'row', alignItems: 'center', flex: 1 },
  moduleIcon:    { fontSize: 18, color: C.dim, width: 28 },
  moduleInfo:    { flex: 1, marginLeft: 8 },
  moduleNameRow: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  moduleName:    { fontSize: 15, fontWeight: '600', color: C.white },
  moduleDetail:  { fontSize: 11, color: C.dim, marginTop: 2 },
  arrow:         { fontSize: 20, color: C.dim, paddingHorizontal: 4 },

  badge: { borderWidth: 1, borderRadius: 4, paddingHorizontal: 6, paddingVertical: 1 },
  badgeText: { fontSize: 10, fontWeight: '600' },

  btn: {
    paddingHorizontal: 14, paddingVertical: 7, borderRadius: 6,
    minWidth: 64, alignItems: 'center', justifyContent: 'center',
  },
  btnStart:   { backgroundColor: '#1f4a8a' },
  btnStop:    { backgroundColor: '#3d1f1f' },
  btnPending: { backgroundColor: '#2d2d2d' },
  btnText:    { fontSize: 13, fontWeight: '600', color: C.white },

  bigBtn: {
    paddingHorizontal: 20, paddingVertical: 10,
    borderRadius: 8, minWidth: 130, alignItems: 'center',
  },
  bigBtnText: { fontSize: 14, fontWeight: '600', color: C.white },

  separator:    { height: 1, backgroundColor: C.border, marginVertical: 4 },
  sectionHeader:{ paddingHorizontal: 16, paddingVertical: 8 },
  sectionTitle: { fontSize: 11, color: C.dim, fontWeight: '700', letterSpacing: 1 },

  card: {
    backgroundColor: C.card, borderRadius: 10,
    borderWidth: 1, borderColor: C.border,
    padding: 14, marginBottom: 12,
  },
  cardLabel: { fontSize: 11, color: C.dim, fontWeight: '700', letterSpacing: 0.8, marginBottom: 10 },
  cardBody:  { fontSize: 13, color: C.white, lineHeight: 20 },

  cmdBox: {
    backgroundColor: '#0d1117', borderRadius: 6,
    paddingVertical: 7, paddingHorizontal: 10, marginBottom: 6,
  },
  cmdText: {
    fontSize: 11, color: C.green,
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier',
  },
});
