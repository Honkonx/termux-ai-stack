// termux-ai-stack · App.js
// v1.4.0 | Abril 2026
// BackHandler nativo · Submenús reales SSH/Ollama/n8n · Switch · Modelos dinámicos

import { StatusBar } from 'expo-status-bar';
import { useEffect, useState, useCallback, useRef } from 'react';
import {
  StyleSheet, Text, View, ScrollView, Switch,
  TouchableOpacity, RefreshControl, ActivityIndicator,
  Platform, Alert, BackHandler, Clipboard,
} from 'react-native';

// ─────────────────────────────────────────────
//  CONFIG
// ─────────────────────────────────────────────
const API           = 'http://localhost:8080';
const POLL_MS       = 3000;
const FETCH_MS      = 4000;
const POLL_ACT_MS   = 2000;
const POLL_ACT_MAX  = 25;

const MODULE_TYPE = {
  n8n: 'service', ollama: 'service', ssh: 'service',
  claude: 'tool',  eas: 'tool',      python: 'tool',
};

// ─────────────────────────────────────────────
//  COLORES
// ─────────────────────────────────────────────
const C = {
  bg: '#0d1117', surface: '#161b22', border: '#30363d',
  cyan: '#58a6ff', green: '#3fb950', yellow: '#d29922',
  red: '#f85149', dim: '#8b949e', white: '#e6edf3', card: '#1c2128',
};

// ─────────────────────────────────────────────
//  MODELOS OLLAMA PREDEFINIDOS
// ─────────────────────────────────────────────
const OLLAMA_MODELS_PRESET = [
  { name: 'qwen2.5:0.5b',  size: '~400 MB', label: 'Más liviano ✓' },
  { name: 'qwen2.5:1.5b',  size: '~986 MB', label: 'Recomendado ✓' },
  { name: 'qwen:1.8b',     size: '~1.1 GB', label: 'Balance' },
  { name: 'llama3.2:1b',   size: '~1.3 GB', label: 'Meta' },
  { name: 'phi3:mini',     size: '~2.3 GB', label: 'Mejor calidad' },
];

// ─────────────────────────────────────────────
//  HELPER fetch
// ─────────────────────────────────────────────
async function apiFetch(path, opts = {}, ms = FETCH_MS) {
  const ctrl = new AbortController();
  const id   = setTimeout(() => ctrl.abort(), ms);
  try {
    const r = await fetch(API + path, { ...opts, signal: ctrl.signal });
    clearTimeout(id);
    return r;
  } catch (e) { clearTimeout(id); throw e; }
}

// ─────────────────────────────────────────────
//  APP
// ─────────────────────────────────────────────
export default function App() {
  const [status,      setStatus]     = useState(null);
  const [connError,   setConnError]  = useState(false);
  const [refreshing,  setRefreshing] = useState(false);
  const [lastSync,    setLastSync]   = useState('--');
  const [actState,    setActState]   = useState({});
  const [activeTab,   setActiveTab]  = useState('modules');
  const [screen,      setScreen]     = useState('main');  // 'main'|'detail'|'ssh'|'ollama'|'n8n'
  const [detailMod,   setDetailMod]  = useState(null);
  const [logs,        setLogs]       = useState([]);
  // Datos extras de submenús
  const [ollamaData,  setOllamaData] = useState({ running: false, models: [] });
  const [sshInfo,     setSshInfo]    = useState(null);
  const [n8nUrl,      setN8nUrl]     = useState('');
  const pollRef = useRef({});

  // ── BackHandler ─────────────────────────────────────────
  useEffect(() => {
    const onBack = () => {
      if (screen === 'ssh' || screen === 'ollama' || screen === 'n8n') {
        setScreen('detail');
        return true;
      }
      if (screen === 'detail') {
        setScreen('main');
        setDetailMod(null);
        return true;
      }
      if (activeTab !== 'modules') {
        setActiveTab('modules');
        return true;
      }
      // En pantalla principal: mostrar confirmación antes de salir
      Alert.alert('Salir', '¿Cerrar la app?', [
        { text: 'Cancelar', style: 'cancel' },
        { text: 'Salir', style: 'destructive', onPress: () => BackHandler.exitApp() },
      ]);
      return true;
    };
    const sub = BackHandler.addEventListener('hardwareBackPress', onBack);
    return () => sub.remove();
  }, [screen, activeTab]);

  // ── Fetch status ─────────────────────────────────────────
  const fetchStatus = useCallback(async (manual = false) => {
    if (manual) setRefreshing(true);
    try {
      const r = await apiFetch('/api/status');
      if (!r.ok) throw new Error();
      const d = await r.json();
      setStatus(d);
      setConnError(false);
      setLastSync(new Date().toLocaleTimeString());
    } catch { setConnError(true); }
    finally { if (manual) setRefreshing(false); }
  }, []);

  const fetchLogs = useCallback(async () => {
    try {
      const r = await apiFetch('/api/logs');
      if (r.ok) { const d = await r.json(); setLogs(d.logs || []); }
    } catch {}
  }, []);

  // ── Fetch datos de submenús ───────────────────────────────
  const fetchOllamaData = useCallback(async () => {
    try {
      const r = await apiFetch('/api/ollama/models');
      if (r.ok) { const d = await r.json(); setOllamaData(d); }
    } catch {}
  }, []);

  const fetchSshInfo = useCallback(async () => {
    try {
      const r = await apiFetch('/api/ssh/info');
      if (r.ok) { const d = await r.json(); setSshInfo(d); }
    } catch {}
  }, []);

  const fetchN8nUrl = useCallback(async () => {
    try {
      const r = await apiFetch('/api/n8n/url');
      if (r.ok) { const d = await r.json(); setN8nUrl(d.url || ''); }
    } catch {}
  }, []);

  // ── Poll automático ───────────────────────────────────────
  useEffect(() => {
    fetchStatus();
    const id = setInterval(fetchStatus, POLL_MS);
    return () => clearInterval(id);
  }, [fetchStatus]);

  // ── Poll post-acción ──────────────────────────────────────
  const startPoll = useCallback((modId, expectRunning) => {
    let n = 0;
    setActState(s => ({ ...s, [modId]: 'confirming' }));
    const id = setInterval(async () => {
      n++;
      try {
        const r = await apiFetch('/api/status');
        const d = await r.json();
        const m = (d.modules || []).find(x => x.id === modId);
        if (m && m.running === expectRunning) {
          setStatus(d);
          setLastSync(new Date().toLocaleTimeString());
          clearInterval(id); delete pollRef.current[modId];
          setActState(s => ({ ...s, [modId]: 'ok' }));
          setTimeout(() => setActState(s => ({ ...s, [modId]: null })), 1800);
          // Refrescar datos del submenú si está abierto
          if (modId === 'ollama') fetchOllamaData();
          return;
        }
      } catch {}
      if (n >= POLL_ACT_MAX) {
        clearInterval(id); delete pollRef.current[modId];
        setActState(s => ({ ...s, [modId]: 'error' }));
        setTimeout(() => setActState(s => ({ ...s, [modId]: null })), 3000);
      }
    }, POLL_ACT_MS);
    pollRef.current[modId] = id;
  }, [fetchOllamaData]);

  // ── Acción start/stop ─────────────────────────────────────
  const doAction = useCallback(async (modId, action) => {
    if (pollRef.current[modId]) { clearInterval(pollRef.current[modId]); delete pollRef.current[modId]; }
    setActState(s => ({ ...s, [modId]: 'pending' }));
    try {
      const r = await apiFetch('/api/action', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ module: modId, action }),
      });
      const d = await r.json();
      if (d.ok) startPoll(modId, action === 'start');
      else {
        setActState(s => ({ ...s, [modId]: 'error' }));
        setTimeout(() => setActState(s => ({ ...s, [modId]: null })), 3000);
      }
    } catch {
      setActState(s => ({ ...s, [modId]: 'error' }));
      setTimeout(() => setActState(s => ({ ...s, [modId]: null })), 3000);
    }
  }, [startPoll]);

  // ── Descargar modelo Ollama ───────────────────────────────
  const pullModel = useCallback(async (modelName) => {
    Alert.alert('Descargar modelo', `¿Descargar ${modelName}?\n\nEl proceso corre en background via tmux.`, [
      { text: 'Cancelar', style: 'cancel' },
      {
        text: 'Descargar', onPress: async () => {
          try {
            const r = await apiFetch('/api/action', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ module: 'ollama', action: `pull:${modelName}` }),
            });
            const d = await r.json();
            Alert.alert(d.ok ? '↓ Descarga iniciada' : 'Error', d.msg);
          } catch { Alert.alert('Error', 'Sin conexión al dashboard'); }
        },
      },
    ]);
  }, []);

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
            Alert.alert(d.ok ? '✓ Backup' : 'Error', d.msg);
          } catch { Alert.alert('Error', 'Sin conexión al dashboard'); }
        },
      },
    ]);
  }, []);

  // ── Navegación a submenú ──────────────────────────────────
  const openDetail = useCallback((mod) => {
    setDetailMod(mod);
    setScreen('detail');
  }, []);

  const openSubscreen = useCallback((id) => {
    setScreen(id);
    if (id === 'ollama') fetchOllamaData();
    if (id === 'ssh')    fetchSshInfo();
    if (id === 'n8n')    fetchN8nUrl();
  }, [fetchOllamaData, fetchSshInfo, fetchN8nUrl]);

  // ── Cleanup ───────────────────────────────────────────────
  useEffect(() => () => Object.values(pollRef.current).forEach(clearInterval), []);

  // ── Módulo actual desde status fresco ────────────────────
  const freshMod = (id) => (status?.modules || []).find(x => x.id === id) || detailMod;

  // ════════════════════════════════════════════
  //  PANTALLA SIN CONEXIÓN
  // ════════════════════════════════════════════
  if (connError && !status) {
    return (
      <View style={s.center}>
        <StatusBar style="light" />
        <Text style={s.hexBig}>⬡</Text>
        <Text style={s.errTitle}>Dashboard no responde</Text>
        <Text style={s.errSub}>Abre Termux y ejecuta:</Text>
        <View style={s.codeBox}><Text style={s.codeText}>bash ~/dashboard_start.sh</Text></View>
        <Text style={s.errHint}>Luego regresa — se reconecta automáticamente.</Text>
        <TouchableOpacity style={s.retryBtn} onPress={() => fetchStatus(true)}>
          <Text style={s.retryText}>↻  Reintentar</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (!status) {
    return (
      <View style={s.center}>
        <StatusBar style="light" />
        <ActivityIndicator color={C.cyan} size="large" />
        <Text style={[s.errSub, { marginTop: 16 }]}>Conectando...</Text>
      </View>
    );
  }

  // ════════════════════════════════════════════
  //  SUBMENÚ SSH
  // ════════════════════════════════════════════
  if (screen === 'ssh') {
    const m      = freshMod('ssh');
    const aState = actState['ssh'];
    const isPend = aState === 'pending' || aState === 'confirming';
    const info   = sshInfo;

    return (
      <View style={s.root}>
        <StatusBar style="light" />
        <View style={s.header}>
          <TouchableOpacity onPress={() => setScreen('detail')} style={s.backRow}>
            <Text style={s.backText}>← Ollama</Text>
          </TouchableOpacity>
          <Text style={s.subTitle}>⌗  SSH</Text>
        </View>
        <ScrollView style={s.scroll} contentContainerStyle={{ padding: 16 }}>

          {/* Switch ON/OFF */}
          <View style={s.card}>
            <View style={s.rowBetween}>
              <View>
                <Text style={s.cardLabel}>SERVIDOR SSH</Text>
                <Text style={[s.statusDot, { color: m?.running ? C.green : C.dim }]}>
                  {m?.running ? '● Activo' : '○ Detenido'}
                </Text>
              </View>
              {isPend ? (
                <ActivityIndicator color={C.cyan} />
              ) : (
                <Switch
                  value={m?.running || false}
                  onValueChange={(v) => doAction('ssh', v ? 'start' : 'stop')}
                  trackColor={{ false: C.border, true: C.cyan + '80' }}
                  thumbColor={m?.running ? C.cyan : C.dim}
                />
              )}
            </View>
            {aState === 'ok'    && <Text style={s.confirmOk}>✓ Confirmado</Text>}
            {aState === 'error' && <Text style={s.confirmErr}>✗ Sin respuesta</Text>}
          </View>

          {/* Info de conexión */}
          {info ? (
            <View style={s.card}>
              <Text style={s.cardLabel}>CONEXIÓN</Text>
              <InfoRow k="IP WiFi" v={info.ip} />
              <InfoRow k="Puerto"  v={info.port} />
              <InfoRow k="Usuario" v={info.user} />
              <InfoRow k="Claves SSH" v={`${info.keys} autorizada${info.keys !== 1 ? 's' : ''}`} />
            </View>
          ) : null}

          {/* Comando para copiar */}
          {info ? (
            <View style={s.card}>
              <Text style={s.cardLabel}>COMANDO DE CONEXIÓN</Text>
              <TouchableOpacity
                style={s.cmdBoxTap}
                onPress={() => {
                  Clipboard?.setString?.(info.cmd);
                  Alert.alert('Copiado', info.cmd);
                }}
              >
                <Text style={s.cmdText}>{info.cmd}</Text>
                <Text style={s.cmdCopy}>📋 Copiar</Text>
              </TouchableOpacity>
              <Text style={[s.cardLabel, { marginTop: 10 }]}>SCP (transferir archivos)</Text>
              <View style={s.cmdBox}>
                <Text style={s.cmdText}>{info.scp_cmd}</Text>
              </View>
            </View>
          ) : (
            <View style={s.card}>
              <ActivityIndicator color={C.cyan} />
            </View>
          )}

          {/* Nota */}
          <View style={[s.card, { borderColor: C.dim + '44' }]}>
            <Text style={[s.cardBody, { color: C.dim }]}>
              Para agregar clave SSH desde PC, usa el menú de Termux:{'\n'}
              <Text style={{ color: C.green, fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier' }}>
                menu → [6] SSH → [4] Agregar clave
              </Text>
            </Text>
          </View>

          <View style={{ height: 32 }} />
        </ScrollView>
      </View>
    );
  }

  // ════════════════════════════════════════════
  //  SUBMENÚ OLLAMA
  // ════════════════════════════════════════════
  if (screen === 'ollama') {
    const m      = freshMod('ollama');
    const aState = actState['ollama'];
    const isPend = aState === 'pending' || aState === 'confirming';

    return (
      <View style={s.root}>
        <StatusBar style="light" />
        <View style={s.header}>
          <TouchableOpacity onPress={() => setScreen('detail')} style={s.backRow}>
            <Text style={s.backText}>← Ollama</Text>
          </TouchableOpacity>
          <Text style={s.subTitle}>◎  Ollama</Text>
        </View>
        <ScrollView style={s.scroll} contentContainerStyle={{ padding: 16 }}>

          {/* Switch ON/OFF */}
          <View style={s.card}>
            <View style={s.rowBetween}>
              <View>
                <Text style={s.cardLabel}>SERVIDOR OLLAMA</Text>
                <Text style={[s.statusDot, { color: m?.running ? C.green : C.dim }]}>
                  {m?.running ? '● Activo :11434' : '○ Detenido'}
                </Text>
              </View>
              {isPend ? (
                <ActivityIndicator color={C.cyan} />
              ) : (
                <Switch
                  value={m?.running || false}
                  onValueChange={(v) => doAction('ollama', v ? 'start' : 'stop')}
                  trackColor={{ false: C.border, true: C.cyan + '80' }}
                  thumbColor={m?.running ? C.cyan : C.dim}
                />
              )}
            </View>
            {aState === 'ok'    && <Text style={s.confirmOk}>✓ Confirmado</Text>}
            {aState === 'error' && <Text style={s.confirmErr}>✗ Sin respuesta (Ollama puede tardar ~10s)</Text>}
          </View>

          {/* Advertencia bug */}
          <View style={[s.card, { borderColor: C.yellow + '55' }]}>
            <Text style={{ color: C.yellow, fontSize: 12, lineHeight: 18 }}>
              ⚠ Bug #27290 activo — rendimiento reducido hasta fix oficial de termux-packages.
            </Text>
          </View>

          {/* Modelos instalados */}
          <View style={s.card}>
            <View style={s.rowBetween}>
              <Text style={s.cardLabel}>MODELOS INSTALADOS</Text>
              <TouchableOpacity onPress={fetchOllamaData}>
                <Text style={{ color: C.cyan, fontSize: 11 }}>↻</Text>
              </TouchableOpacity>
            </View>
            {ollamaData.models.length === 0 ? (
              <Text style={{ color: C.dim, fontSize: 13 }}>
                {m?.running ? 'No hay modelos instalados.' : 'Inicia el servidor para ver modelos.'}
              </Text>
            ) : (
              ollamaData.models.map((mod, i) => (
                <View key={i} style={[s.rowBetween, { marginBottom: 8 }]}>
                  <View>
                    <Text style={{ color: C.white, fontSize: 13, fontWeight: '600' }}>{mod.name}</Text>
                    <Text style={{ color: C.dim, fontSize: 11 }}>{mod.size}</Text>
                  </View>
                  <View style={[s.badge, { borderColor: C.green }]}>
                    <Text style={[s.badgeText, { color: C.green }]}>instalado</Text>
                  </View>
                </View>
              ))
            )}
          </View>

          {/* Descargar modelo */}
          <View style={s.card}>
            <Text style={s.cardLabel}>DESCARGAR MODELO</Text>
            <Text style={{ color: C.dim, fontSize: 12, marginBottom: 10 }}>
              Recomendados para POCO F5 (12 GB RAM):
            </Text>
            {OLLAMA_MODELS_PRESET.map((preset, i) => {
              const yaInstalado = ollamaData.models.some(x => x.name === preset.name);
              return (
                <TouchableOpacity
                  key={i}
                  style={[s.modelRow, yaInstalado && { opacity: 0.5 }]}
                  onPress={() => !yaInstalado && pullModel(preset.name)}
                  disabled={yaInstalado}
                >
                  <View style={{ flex: 1 }}>
                    <Text style={{ color: C.white, fontSize: 13, fontWeight: '600' }}>{preset.name}</Text>
                    <Text style={{ color: C.dim, fontSize: 11 }}>{preset.size} · {preset.label}</Text>
                  </View>
                  <Text style={{ color: yaInstalado ? C.green : C.cyan, fontSize: 13 }}>
                    {yaInstalado ? '✓' : '↓'}
                  </Text>
                </TouchableOpacity>
              );
            })}
          </View>

          <View style={{ height: 32 }} />
        </ScrollView>
      </View>
    );
  }

  // ════════════════════════════════════════════
  //  SUBMENÚ N8N
  // ════════════════════════════════════════════
  if (screen === 'n8n') {
    const m      = freshMod('n8n');
    const aState = actState['n8n'];
    const isPend = aState === 'pending' || aState === 'confirming';

    return (
      <View style={s.root}>
        <StatusBar style="light" />
        <View style={s.header}>
          <TouchableOpacity onPress={() => setScreen('detail')} style={s.backRow}>
            <Text style={s.backText}>← n8n</Text>
          </TouchableOpacity>
          <Text style={s.subTitle}>⬡  n8n</Text>
        </View>
        <ScrollView style={s.scroll} contentContainerStyle={{ padding: 16 }}>

          {/* Switch ON/OFF */}
          <View style={s.card}>
            <View style={s.rowBetween}>
              <View>
                <Text style={s.cardLabel}>SERVIDOR N8N</Text>
                <Text style={[s.statusDot, { color: m?.running ? C.green : C.dim }]}>
                  {m?.running ? '● Activo · proot Debian' : '○ Detenido'}
                </Text>
                {isPend && aState === 'confirming' && (
                  <Text style={{ color: C.dim, fontSize: 11, marginTop: 2 }}>
                    n8n tarda ~35s en arrancar...
                  </Text>
                )}
              </View>
              {isPend ? (
                <ActivityIndicator color={C.cyan} />
              ) : (
                <Switch
                  value={m?.running || false}
                  onValueChange={(v) => doAction('n8n', v ? 'start' : 'stop')}
                  trackColor={{ false: C.border, true: C.cyan + '80' }}
                  thumbColor={m?.running ? C.cyan : C.dim}
                />
              )}
            </View>
            {aState === 'ok'    && <Text style={s.confirmOk}>✓ Confirmado</Text>}
            {aState === 'error' && <Text style={s.confirmErr}>✗ Sin respuesta (puede tardar hasta 50s)</Text>}
          </View>

          {/* URL del tunnel */}
          <View style={s.card}>
            <View style={s.rowBetween}>
              <Text style={s.cardLabel}>URL PÚBLICA (CLOUDFLARE TUNNEL)</Text>
              <TouchableOpacity onPress={fetchN8nUrl}>
                <Text style={{ color: C.cyan, fontSize: 11 }}>↻</Text>
              </TouchableOpacity>
            </View>
            {n8nUrl ? (
              <TouchableOpacity
                style={s.cmdBoxTap}
                onPress={() => {
                  Clipboard?.setString?.(n8nUrl);
                  Alert.alert('Copiado', n8nUrl);
                }}
              >
                <Text style={[s.cmdText, { color: C.cyan }]}>{n8nUrl}</Text>
                <Text style={s.cmdCopy}>📋 Copiar</Text>
              </TouchableOpacity>
            ) : (
              <Text style={{ color: C.dim, fontSize: 13 }}>
                {m?.running
                  ? 'URL no disponible — cloudflared puede estar iniciando...'
                  : 'Inicia n8n para obtener la URL del tunnel.'}
              </Text>
            )}
          </View>

          {/* Info */}
          <View style={s.card}>
            <Text style={s.cardLabel}>INFO TÉCNICA</Text>
            <InfoRow k="Puerto interno" v="5678 (proot)" />
            <InfoRow k="Puerto externo" v="443 (cloudflare)" />
            <InfoRow k="Capa"           v="proot Debian" />
            <InfoRow k="Node.js proot"  v="v20 LTS (fijo)" />
          </View>

          <View style={{ height: 32 }} />
        </ScrollView>
      </View>
    );
  }

  // ════════════════════════════════════════════
  //  PANTALLA DETALLE (tap en módulo)
  // ════════════════════════════════════════════
  if (screen === 'detail' && detailMod) {
    const m         = freshMod(detailMod.id);
    const isService = MODULE_TYPE[m?.id] === 'service';
    const aState    = actState[m?.id];
    const isPend    = aState === 'pending' || aState === 'confirming';

    let statusColor = C.dim, statusLabel = 'no instalado';
    if (m?.installed) {
      statusLabel = isService ? (m.running ? 'activo' : 'listo') : 'listo';
      statusColor = (isService && m.running) ? C.green : C.yellow;
    }

    // Submenús disponibles por módulo
    const subLinks = {
      ssh:    { label: '⌗  Control SSH →', screen: 'ssh' },
      ollama: { label: '◎  Modelos y control →', screen: 'ollama' },
      n8n:    { label: '⬡  Control n8n →', screen: 'n8n' },
    };
    const subLink = subLinks[m?.id];

    return (
      <View style={s.root}>
        <StatusBar style="light" />
        <View style={s.header}>
          <TouchableOpacity onPress={() => { setScreen('main'); setDetailMod(null); }} style={s.backRow}>
            <Text style={s.backText}>← Menú</Text>
          </TouchableOpacity>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 4 }}>
            <Text style={{ fontSize: 22 }}>{m?.icon}</Text>
            <Text style={s.detailTitle}>{m?.name}</Text>
            <View style={[s.badge, { borderColor: statusColor }]}>
              <Text style={[s.badgeText, { color: statusColor }]}>{statusLabel}</Text>
            </View>
          </View>
          {m?.version ? <Text style={{ fontSize: 12, color: C.dim, marginTop: 4 }}>v{m.version}</Text> : null}
        </View>

        <ScrollView style={s.scroll} contentContainerStyle={{ padding: 16 }}>

          {/* Acceso directo al submenú completo */}
          {subLink ? (
            <TouchableOpacity
              style={[s.card, { borderColor: C.cyan + '55', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }]}
              onPress={() => openSubscreen(subLink.screen)}
            >
              <Text style={{ color: C.cyan, fontSize: 14, fontWeight: '600' }}>{subLink.label}</Text>
              <Text style={s.arrow}>›</Text>
            </TouchableOpacity>
          ) : null}

          {/* Switch rápido para servicios */}
          {m?.installed && isService && !subLink ? (
            <View style={s.card}>
              <View style={s.rowBetween}>
                <Text style={[s.statusDot, { color: m.running ? C.green : C.dim }]}>
                  {m.running ? '● Activo' : '○ Detenido'}
                </Text>
                {isPend ? <ActivityIndicator color={C.cyan} /> : (
                  <Switch
                    value={m.running || false}
                    onValueChange={(v) => doAction(m.id, v ? 'start' : 'stop')}
                    trackColor={{ false: C.border, true: C.cyan + '80' }}
                    thumbColor={m.running ? C.cyan : C.dim}
                  />
                )}
              </View>
            </View>
          ) : null}

          {/* Info técnica */}
          <View style={s.card}>
            <Text style={s.cardLabel}>INFO</Text>
            <InfoRow k="Versión" v={m?.version ? `v${m.version}` : '—'} />
            <InfoRow k="Capa"    v={m?.layer || '—'} />
            {m?.detail ? <InfoRow k="Detalle" v={m.detail} /> : null}
          </View>

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

      {/* Tabs */}
      <View style={s.tabBar}>
        {[{ key: 'modules', label: '⬡  Módulos' }, { key: 'system', label: '◎  Sistema' }].map(tab => (
          <TouchableOpacity
            key={tab.key}
            style={[s.tab, activeTab === tab.key && s.tabActive]}
            onPress={() => { setActiveTab(tab.key); if (tab.key === 'system') fetchLogs(); }}
          >
            <Text style={[s.tabText, activeTab === tab.key && s.tabTextActive]}>{tab.label}</Text>
          </TouchableOpacity>
        ))}
      </View>

      {/* ═══ TAB MÓDULOS ═══ */}
      {activeTab === 'modules' && (
        <ScrollView
          style={s.scroll}
          contentContainerStyle={s.scrollContent}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => fetchStatus(true)} tintColor={C.cyan} />}
        >
          {(status.modules || []).map(m => {
            const isService = MODULE_TYPE[m.id] === 'service';
            const aState    = actState[m.id];
            const isPend    = aState === 'pending' || aState === 'confirming';

            let badgeText = 'no instalado', badgeColor = C.dim;
            if (m.installed) {
              badgeText  = isService ? (m.running ? 'activo' : 'listo') : 'listo';
              badgeColor = (isService && m.running) ? C.green : C.yellow;
            }

            return (
              <TouchableOpacity
                key={m.id}
                style={s.moduleRow}
                onPress={() => openDetail(m)}
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
                  isPend ? (
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

          {/* Sistema / Backup */}
          <View style={s.separator} />
          <View style={s.sectionHeader}><Text style={s.sectionTitle}>SISTEMA</Text></View>

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
            onPress={() => Alert.alert('Restore', 'Para restaurar ejecuta en Termux:\n\nbash ~/restore.sh\n\nO: menú → [0] → Restore')}
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

      {/* ═══ TAB SISTEMA ═══ */}
      {activeTab === 'system' && (
        <ScrollView style={s.scroll} contentContainerStyle={{ padding: 16 }}>
          <View style={s.card}>
            <Text style={s.cardLabel}>SISTEMA</Text>
            <InfoRow k="IP WiFi"     v={status.ip} />
            <InfoRow k="RAM libre"   v={ramStr} />
            <InfoRow k="RAM total"   v={ram.total_mb ? `${(ram.total_mb/1024).toFixed(1)} GB` : '--'} />
            <InfoRow k="Dashboard"   v=":8080 activo" vc={C.green} />
            <InfoRow k="Último sync" v={lastSync} />
          </View>

          <View style={s.card}>
            <Text style={s.cardLabel}>MÓDULOS</Text>
            {(status.modules || []).map(m => {
              const isService = MODULE_TYPE[m.id] === 'service';
              const color = !m.installed ? C.dim : (isService && m.running) ? C.green : C.yellow;
              const label = !m.installed ? 'no instalado'
                : isService ? (m.running ? 'activo' : 'listo')
                : `listo${m.version ? ' · v' + m.version : ''}`;
              return <InfoRow key={m.id} k={`${m.running ? '●' : '○'} ${m.name}`} v={label} kc={color} vc={color} />;
            })}
          </View>

          <View style={s.card}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
              <Text style={s.cardLabel}>ÚLTIMAS ACCIONES</Text>
              <TouchableOpacity onPress={fetchLogs}>
                <Text style={{ color: C.cyan, fontSize: 12 }}>↻</Text>
              </TouchableOpacity>
            </View>
            {logs.length === 0 ? (
              <Text style={{ color: C.dim, fontSize: 13 }}>Sin acciones registradas.</Text>
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
//  InfoRow
// ─────────────────────────────────────────────
function InfoRow({ k, v, kc, vc }) {
  return (
    <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginBottom: 7 }}>
      <Text style={{ fontSize: 13, color: kc || C.dim, flex: 1 }}>{k}</Text>
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
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 32,
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
  retryBtn: { backgroundColor: '#1f4a8a', borderRadius: 8, paddingVertical: 12, paddingHorizontal: 28 },
  retryText: { fontSize: 14, fontWeight: '600', color: C.white },

  header: {
    paddingTop: Platform.OS === 'android' ? 44 : 54,
    paddingHorizontal: 16, paddingBottom: 10,
    backgroundColor: C.surface, borderBottomWidth: 1, borderBottomColor: C.border,
  },
  headerTitle:  { fontSize: 17, fontWeight: '700', color: C.cyan, letterSpacing: 1 },
  headerMeta:   { flexDirection: 'row', alignItems: 'center', marginTop: 3, flexWrap: 'wrap' },
  metaText:     { fontSize: 11, color: C.dim },
  metaDot:      { fontSize: 11, color: C.dim, marginHorizontal: 5 },
  warnBanner: {
    marginTop: 6, backgroundColor: '#2d1a00',
    borderRadius: 5, paddingVertical: 3, paddingHorizontal: 8, alignSelf: 'flex-start',
  },
  warnText:    { fontSize: 11, color: C.yellow },
  backRow:     { marginBottom: 8 },
  backText:    { fontSize: 14, color: C.cyan },
  subTitle:    { fontSize: 18, fontWeight: '700', color: C.white },
  detailTitle: { fontSize: 18, fontWeight: '700', color: C.white },

  tabBar: {
    flexDirection: 'row', backgroundColor: C.surface,
    borderBottomWidth: 1, borderBottomColor: C.border,
  },
  tab:           { flex: 1, paddingVertical: 10, alignItems: 'center', borderBottomWidth: 2, borderBottomColor: 'transparent' },
  tabActive:     { borderBottomColor: C.cyan },
  tabText:       { fontSize: 12, color: C.dim, fontWeight: '500' },
  tabTextActive: { fontSize: 12, color: C.cyan, fontWeight: '700' },

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

  badge:     { borderWidth: 1, borderRadius: 4, paddingHorizontal: 6, paddingVertical: 1 },
  badgeText: { fontSize: 10, fontWeight: '600' },

  btn: {
    paddingHorizontal: 14, paddingVertical: 7, borderRadius: 6,
    minWidth: 64, alignItems: 'center', justifyContent: 'center',
  },
  btnStart:   { backgroundColor: '#1f4a8a' },
  btnStop:    { backgroundColor: '#3d1f1f' },
  btnPending: { backgroundColor: '#2d2d2d' },
  btnText:    { fontSize: 13, fontWeight: '600', color: C.white },

  separator:     { height: 1, backgroundColor: C.border, marginVertical: 4 },
  sectionHeader: { paddingHorizontal: 16, paddingVertical: 8 },
  sectionTitle:  { fontSize: 11, color: C.dim, fontWeight: '700', letterSpacing: 1 },

  card: {
    backgroundColor: C.card, borderRadius: 10,
    borderWidth: 1, borderColor: C.border,
    padding: 14, marginBottom: 12,
  },
  cardLabel: { fontSize: 11, color: C.dim, fontWeight: '700', letterSpacing: 0.8, marginBottom: 10 },
  cardBody:  { fontSize: 13, color: C.white, lineHeight: 20 },

  rowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  statusDot:  { fontSize: 13, fontWeight: '600', marginTop: 4 },
  confirmOk:  { color: C.green, fontSize: 12, marginTop: 6 },
  confirmErr: { color: C.red,   fontSize: 12, marginTop: 6 },

  cmdBox: {
    backgroundColor: '#0d1117', borderRadius: 6,
    paddingVertical: 7, paddingHorizontal: 10, marginBottom: 6,
  },
  cmdBoxTap: {
    backgroundColor: '#0d1117', borderRadius: 6,
    paddingVertical: 10, paddingHorizontal: 10, marginBottom: 6,
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
  },
  cmdCopy: { fontSize: 11, color: C.cyan },
  cmdText: {
    fontSize: 11, color: C.green, flex: 1,
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier',
  },

  modelRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingVertical: 10, paddingHorizontal: 4,
    borderBottomWidth: 1, borderBottomColor: C.border + '44',
  },
});
