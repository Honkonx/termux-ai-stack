// termux-ai-stack · App.js
// v1.5.0 | Abril 2026
// Rediseño completo: cards expandibles · iconos SVG · footer nav · submenús inline

import { StatusBar } from 'expo-status-bar';
import { useEffect, useState, useCallback, useRef } from 'react';
import {
  StyleSheet, Text, View, ScrollView, Switch, TextInput,
  TouchableOpacity, RefreshControl, ActivityIndicator,
  Platform, Alert, BackHandler, Animated, Dimensions,
} from 'react-native';

const { width: SW } = Dimensions.get('window');

// ─────────────────────────────────────────────
//  CONFIG
// ─────────────────────────────────────────────
const API          = 'http://localhost:8080';
const POLL_MS      = 3000;
const FETCH_MS     = 4000;
const POLL_ACT_MS  = 2000;
const POLL_ACT_MAX = 25;

// ─────────────────────────────────────────────
//  PALETA — inspirada en GitHub Dark + terminal
// ─────────────────────────────────────────────
const C = {
  bg:       '#0d1117',
  surface:  '#13181f',
  card:     '#161b22',
  cardHi:   '#1c2230',
  border:   '#21262d',
  borderHi: '#388bfd44',
  cyan:     '#58a6ff',
  cyanDim:  '#1f3a5f',
  green:    '#3fb950',
  greenDim: '#1a3a22',
  yellow:   '#d29922',
  yellowDim:'#3a2e10',
  red:      '#f85149',
  redDim:   '#3a1a1a',
  dim:      '#6e7681',
  white:    '#e6edf3',
  text2:    '#8b949e',
  footer:   '#0d1117',
};

// ─────────────────────────────────────────────
//  ICONOS SVG en texto (sin deps externas)
//  Cada módulo tiene un bloque de color + texto
// ─────────────────────────────────────────────
function ModuleIcon({ id, size = 42 }) {
  const configs = {
    n8n:    { bg: '#1a2332', text: '∞',   color: '#e05d28', fs: size * 0.55 },
    ollama: { bg: '#1a2a1a', text: '🦙',  color: '#fff',    fs: size * 0.52 },
    claude: { bg: '#2a1a1a', text: 'A\\',  color: '#d4a027', fs: size * 0.45 },
    eas:    { bg: '#1a1a2a', text: '▲',   color: '#7c7cff', fs: size * 0.5  },
    python: { bg: '#1a2a1a', text: '🐍',  color: '#fff',    fs: size * 0.52 },
    ssh:    { bg: '#0d1f0d', text: '>_',  color: '#3fb950', fs: size * 0.38 },
    dashboard:{ bg:'#1a1a2a',text:'⊞',   color: '#58a6ff', fs: size * 0.5  },
    backup: { bg: '#1a2a2a', text: '☁',  color: '#58a6ff', fs: size * 0.52 },
  };
  const cfg = configs[id] || { bg: '#1a1a1a', text: '?', color: '#fff', fs: size * 0.5 };
  return (
    <View style={{
      width: size, height: size, borderRadius: 12,
      backgroundColor: cfg.bg, alignItems: 'center', justifyContent: 'center',
      borderWidth: 1, borderColor: cfg.color + '33',
    }}>
      <Text style={{ fontSize: cfg.fs, color: cfg.color, fontWeight: '700', lineHeight: cfg.fs + 4 }}>
        {cfg.text}
      </Text>
    </View>
  );
}

// ─────────────────────────────────────────────
//  PILL de estado
// ─────────────────────────────────────────────
function StatusPill({ installed, running, isService }) {
  if (!installed) return (
    <View style={[pill.base, { backgroundColor: C.surface, borderColor: C.border }]}>
      <Text style={[pill.text, { color: C.dim }]}>no instalado</Text>
    </View>
  );
  if (isService && running) return (
    <View style={[pill.base, { backgroundColor: C.greenDim, borderColor: C.green + '66' }]}>
      <View style={pill.dot} /><Text style={[pill.text, { color: C.green }]}>activo</Text>
    </View>
  );
  return (
    <View style={[pill.base, { backgroundColor: C.yellowDim, borderColor: C.yellow + '66' }]}>
      <Text style={[pill.text, { color: C.yellow }]}>listo</Text>
    </View>
  );
}
const pill = StyleSheet.create({
  base: { flexDirection: 'row', alignItems: 'center', borderWidth: 1, borderRadius: 20, paddingHorizontal: 8, paddingVertical: 3 },
  dot:  { width: 6, height: 6, borderRadius: 3, backgroundColor: C.green, marginRight: 4 },
  text: { fontSize: 11, fontWeight: '600' },
});

// ─────────────────────────────────────────────
//  MODELOS PRESET
// ─────────────────────────────────────────────
const MODELS_PRESET = [
  { name: 'qwen2.5:0.5b', size: '~400 MB', tag: 'Más liviano' },
  { name: 'qwen2.5:1.5b', size: '~986 MB', tag: 'Recomendado' },
  { name: 'qwen:1.8b',    size: '~1.1 GB', tag: 'Balance'     },
  { name: 'llama3.2:1b',  size: '~1.3 GB', tag: 'Meta'        },
  { name: 'phi3:mini',    size: '~2.3 GB', tag: 'Más calidad' },
];

// ─────────────────────────────────────────────
//  FETCH helper
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
//  APP PRINCIPAL
// ─────────────────────────────────────────────
export default function App() {
  const [status,     setStatus]    = useState(null);
  const [connErr,    setConnErr]   = useState(false);
  const [refreshing, setRefreshing]= useState(false);
  const [lastSync,   setLastSync]  = useState('--');
  const [actState,   setActState]  = useState({});     // { id: 'pending'|'confirming'|'ok'|'error' }
  const [expanded,   setExpanded]  = useState({});     // { id: bool }
  const [footerTab,  setFooterTab] = useState('home'); // 'home'|'system'|'help'
  const [logs,       setLogs]      = useState([]);
  const [ollamaModels, setOllamaModels] = useState([]);
  const [sshInfo,    setSshInfo]   = useState(null);
  const [n8nUrl,     setN8nUrl]    = useState('');
  const pollRef = useRef({});

  // ── BackHandler ─────────────────────────────
  useEffect(() => {
    const h = () => {
      const anyExpanded = Object.values(expanded).some(Boolean);
      if (anyExpanded) { setExpanded({}); return true; }
      if (footerTab !== 'home') { setFooterTab('home'); return true; }
      Alert.alert('Salir', '¿Cerrar la app?', [
        { text: 'Cancelar', style: 'cancel' },
        { text: 'Salir', style: 'destructive', onPress: () => BackHandler.exitApp() },
      ]);
      return true;
    };
    const sub = BackHandler.addEventListener('hardwareBackPress', h);
    return () => sub.remove();
  }, [expanded, footerTab]);

  // ── Fetch status ─────────────────────────────
  const fetchStatus = useCallback(async (manual = false) => {
    if (manual) setRefreshing(true);
    try {
      const r = await apiFetch('/api/status');
      if (!r.ok) throw new Error();
      setStatus(await r.json());
      setConnErr(false);
      setLastSync(new Date().toLocaleTimeString());
    } catch { setConnErr(true); }
    finally { if (manual) setRefreshing(false); }
  }, []);

  const fetchLogs = useCallback(async () => {
    try { const r = await apiFetch('/api/logs'); if (r.ok) { const d = await r.json(); setLogs(d.logs || []); } } catch {}
  }, []);

  const fetchOllama = useCallback(async () => {
    try { const r = await apiFetch('/api/ollama/models'); if (r.ok) { const d = await r.json(); setOllamaModels(d.models || []); } } catch {}
  }, []);

  const fetchSsh = useCallback(async () => {
    try { const r = await apiFetch('/api/ssh/info'); if (r.ok) setSshInfo(await r.json()); } catch {}
  }, []);

  const fetchN8n = useCallback(async () => {
    try { const r = await apiFetch('/api/n8n/url'); if (r.ok) { const d = await r.json(); setN8nUrl(d.url || ''); } } catch {}
  }, []);

  // ── Poll automático ───────────────────────────
  useEffect(() => {
    fetchStatus();
    const id = setInterval(fetchStatus, POLL_MS);
    return () => clearInterval(id);
  }, [fetchStatus]);

  // ── Poll post-acción ──────────────────────────
  const startPoll = useCallback((id, expectRunning) => {
    let n = 0;
    setActState(s => ({ ...s, [id]: 'confirming' }));
    const timer = setInterval(async () => {
      n++;
      try {
        const r = await apiFetch('/api/status');
        const d = await r.json();
        const m = (d.modules || []).find(x => x.id === id);
        if (m && m.running === expectRunning) {
          setStatus(d); setLastSync(new Date().toLocaleTimeString());
          clearInterval(timer); delete pollRef.current[id];
          setActState(s => ({ ...s, [id]: 'ok' }));
          if (id === 'ollama') fetchOllama();
          setTimeout(() => setActState(s => ({ ...s, [id]: null })), 2000);
          return;
        }
      } catch {}
      if (n >= POLL_ACT_MAX) {
        clearInterval(timer); delete pollRef.current[id];
        setActState(s => ({ ...s, [id]: 'error' }));
        setTimeout(() => setActState(s => ({ ...s, [id]: null })), 3000);
      }
    }, POLL_ACT_MS);
    pollRef.current[id] = timer;
  }, [fetchOllama]);

  // ── Acción start/stop ─────────────────────────
  const doAction = useCallback(async (moduleId, action) => {
    if (pollRef.current[moduleId]) { clearInterval(pollRef.current[moduleId]); delete pollRef.current[moduleId]; }
    setActState(s => ({ ...s, [moduleId]: 'pending' }));
    try {
      const r = await apiFetch('/api/action', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ module: moduleId, action }),
      });
      const d = await r.json();
      if (d.ok) startPoll(moduleId, action === 'start');
      else { setActState(s => ({ ...s, [moduleId]: 'error' })); setTimeout(() => setActState(s => ({ ...s, [moduleId]: null })), 3000); }
    } catch { setActState(s => ({ ...s, [moduleId]: 'error' })); setTimeout(() => setActState(s => ({ ...s, [moduleId]: null })), 3000); }
  }, [startPoll]);

  // ── Toggle expansión ──────────────────────────
  const toggleExpand = useCallback((id, extraFetch) => {
    setExpanded(s => {
      const next = !s[id];
      if (next && extraFetch) extraFetch();
      return { ...s, [id]: next };
    });
  }, []);

  // ── Pull modelo ───────────────────────────────
  const pullModel = useCallback(async (name) => {
    Alert.alert('Descargar', `¿Descargar ${name}?`, [
      { text: 'Cancelar', style: 'cancel' },
      { text: 'Descargar', onPress: async () => {
        try {
          const r = await apiFetch('/api/action', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ module: 'ollama', action: `pull:${name}` }) });
          const d = await r.json();
          Alert.alert(d.ok ? '↓ Iniciado' : 'Error', d.msg);
        } catch { Alert.alert('Error', 'Sin conexión'); }
      }},
    ]);
  }, []);

  // ── Backup ─────────────────────────────────────
  const doBackup = useCallback(() => {
    Alert.alert('Backup', '¿Crear backup ahora?', [
      { text: 'Cancelar', style: 'cancel' },
      { text: 'Crear', onPress: async () => {
        try {
          const r = await apiFetch('/api/action', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ module: 'system', action: 'backup' }) });
          const d = await r.json();
          Alert.alert(d.ok ? '✓ Backup creado' : 'Error', d.msg);
        } catch { Alert.alert('Error', 'Sin conexión'); }
      }},
    ]);
  }, []);

  // ── Cleanup ────────────────────────────────────
  useEffect(() => () => Object.values(pollRef.current).forEach(clearInterval), []);

  // ── Módulo fresco ──────────────────────────────
  const fm = (id) => (status?.modules || []).find(x => x.id === id);

  // ══════════════════════════════════════════════
  //  PANTALLA SIN CONEXIÓN
  // ══════════════════════════════════════════════
  if (connErr && !status) {
    return (
      <View style={s.center}>
        <StatusBar style="light" />
        <Text style={s.offlineHex}>⬡</Text>
        <Text style={s.offlineTitle}>Dashboard offline</Text>
        <Text style={s.offlineSub}>Abre Termux y ejecuta:</Text>
        <View style={s.offlineCode}>
          <Text style={s.offlineCmd}>bash ~/dashboard_start.sh</Text>
        </View>
        <Text style={s.offlineHint}>Se reconecta automáticamente cada {POLL_MS/1000}s</Text>
        <TouchableOpacity style={s.retryBtn} onPress={() => fetchStatus(true)}>
          <Text style={s.retryText}>↻  Reintentar ahora</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (!status) {
    return (
      <View style={s.center}>
        <StatusBar style="light" />
        <ActivityIndicator color={C.cyan} size="large" />
        <Text style={[s.offlineSub, { marginTop: 14 }]}>Conectando al dashboard...</Text>
      </View>
    );
  }

  // ══════════════════════════════════════════════
  //  RENDER CARD DE MÓDULO
  // ══════════════════════════════════════════════
  const renderCard = (m) => {
    if (!m) return null;
    const isService   = ['n8n', 'ollama', 'ssh'].includes(m.id);
    const aState      = actState[m.id];
    const isPending   = aState === 'pending' || aState === 'confirming';
    const isExpanded  = !!expanded[m.id];
    const isInstalled = m.installed;

    // ── Switch callback ────────────────────────
    const onSwitch = (v) => {
      if (!isInstalled) return;
      doAction(m.id, v ? 'start' : 'stop');
    };

    // ── Botón de acción principal ──────────────
    let actionBtn = null;
    if (!isInstalled) {
      actionBtn = (
        <TouchableOpacity style={[s.cardBtn, s.cardBtnInstall]}
          onPress={() => Alert.alert('Instalar', `Instala ${m.name} desde el menú de Termux:\n\nmenu → [${m.id === 'n8n' ? 1 : m.id === 'claude' ? 2 : m.id === 'ollama' ? 3 : m.id === 'eas' ? 4 : m.id === 'python' ? 5 : 6}]`)}>
          <Text style={s.cardBtnText}>Instalar</Text>
        </TouchableOpacity>
      );
    } else if (m.id === 'claude') {
      actionBtn = (
        <TouchableOpacity style={[s.cardBtn, s.cardBtnSub]}
          onPress={() => toggleExpand(m.id)}>
          <Text style={s.cardBtnText}>{isExpanded ? 'Cerrar' : 'Info'}</Text>
        </TouchableOpacity>
      );
    } else if (isService) {
      actionBtn = (
        <TouchableOpacity style={[s.cardBtn, s.cardBtnSub]}
          onPress={() => toggleExpand(m.id, m.id === 'ollama' ? fetchOllama : m.id === 'ssh' ? fetchSsh : m.id === 'n8n' ? fetchN8n : null)}>
          <Text style={s.cardBtnText}>{isExpanded ? 'Cerrar' : 'Submenú'}</Text>
        </TouchableOpacity>
      );
    } else {
      actionBtn = (
        <TouchableOpacity style={[s.cardBtn, s.cardBtnSub]}
          onPress={() => toggleExpand(m.id)}>
          <Text style={s.cardBtnText}>{isExpanded ? 'Cerrar' : 'Info'}</Text>
        </TouchableOpacity>
      );
    }

    return (
      <View key={m.id} style={[s.card, isExpanded && s.cardExpanded]}>
        {/* ── Fila principal ── */}
        <TouchableOpacity
          style={s.cardRow}
          onPress={() => isInstalled && toggleExpand(m.id, m.id === 'ollama' ? fetchOllama : m.id === 'ssh' ? fetchSsh : m.id === 'n8n' ? fetchN8n : null)}
          activeOpacity={0.7}
        >
          <ModuleIcon id={m.id} size={44} />

          <View style={s.cardMid}>
            <Text style={s.cardName}>{m.name}</Text>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 3 }}>
              <StatusPill installed={isInstalled} running={m.running} isService={isService} />
              {m.version ? <Text style={s.cardVer}>v{m.version}</Text> : null}
            </View>
          </View>

          <View style={s.cardRight}>
            {isService && isInstalled ? (
              isPending ? (
                <ActivityIndicator color={C.cyan} size="small" style={{ marginRight: 8 }} />
              ) : (
                <Switch
                  value={m.running || false}
                  onValueChange={onSwitch}
                  trackColor={{ false: '#30363d', true: '#388bfd55' }}
                  thumbColor={m.running ? C.cyan : '#6e7681'}
                  style={{ transform: [{ scaleX: 0.85 }, { scaleY: 0.85 }] }}
                />
              )
            ) : null}
            {actionBtn}
          </View>
        </TouchableOpacity>

        {/* ── Feedback acción ── */}
        {aState === 'ok'    && <Text style={s.feedOk}>✓ Confirmado</Text>}
        {aState === 'error' && <Text style={s.feedErr}>✗ Sin respuesta — reintenta</Text>}
        {aState === 'confirming' && m.id === 'n8n' && (
          <Text style={s.feedPending}>⏳ n8n puede tardar ~35s en arrancar...</Text>
        )}

        {/* ── Expansión según módulo ── */}
        {isExpanded && renderExpanded(m)}
      </View>
    );
  };

  // ══════════════════════════════════════════════
  //  CONTENIDO EXPANDIDO POR MÓDULO
  // ══════════════════════════════════════════════
  const renderExpanded = (m) => {
    const divider = <View style={s.divider} />;

    // ── N8N ───────────────────────────────────
    if (m.id === 'n8n') {
      return (
        <View style={s.expanded}>
          {divider}
          <Text style={s.expLabel}>URL PÚBLICA — CLOUDFLARE TUNNEL</Text>
          {n8nUrl ? (
            <TouchableOpacity style={s.urlBox} onPress={() => Alert.alert('URL n8n', n8nUrl)}>
              <Text style={s.urlText} numberOfLines={1}>{n8nUrl}</Text>
              <Text style={s.urlCopy}>📋</Text>
            </TouchableOpacity>
          ) : (
            <Text style={s.expHint}>
              {m.running ? 'Cloudflare iniciando... ↻ actualiza' : 'Inicia n8n para obtener URL'}
            </Text>
          )}
          <TouchableOpacity style={s.expRefresh} onPress={fetchN8n}>
            <Text style={{ color: C.cyan, fontSize: 12 }}>↻ Actualizar URL</Text>
          </TouchableOpacity>
          {divider}
          <Text style={s.expLabel}>INFO TÉCNICA</Text>
          <InfoRow2 k="Puerto interno" v="5678 (proot Debian)" />
          <InfoRow2 k="Acceso externo" v="443 via Cloudflare" />
          <InfoRow2 k="Node.js proot"  v="v20 LTS (fijo)" />
        </View>
      );
    }

    // ── OLLAMA ────────────────────────────────
    if (m.id === 'ollama') {
      return (
        <View style={s.expanded}>
          {divider}
          <View style={s.warnBox}>
            <Text style={s.warnText}>⚠ Bug #27290 activo — rendimiento reducido hasta fix oficial de termux-packages.</Text>
          </View>
          {divider}
          <View style={s.expRowBetween}>
            <Text style={s.expLabel}>MODELOS INSTALADOS</Text>
            <TouchableOpacity onPress={fetchOllama}><Text style={{ color: C.cyan, fontSize: 12 }}>↻</Text></TouchableOpacity>
          </View>
          {ollamaModels.length === 0 ? (
            <Text style={s.expHint}>{m.running ? 'No hay modelos. Descarga uno abajo.' : 'Inicia el servidor para listar modelos.'}</Text>
          ) : (
            ollamaModels.map((mod, i) => (
              <View key={i} style={s.modelRow}>
                <View style={s.modelDot} />
                <Text style={s.modelName}>{mod.name}</Text>
                <Text style={s.modelSize}>{mod.size}</Text>
                <View style={[pill.base, { borderColor: C.green + '66', backgroundColor: C.greenDim }]}>
                  <Text style={[pill.text, { color: C.green }]}>✓</Text>
                </View>
              </View>
            ))
          )}
          {divider}
          <Text style={s.expLabel}>DESCARGAR MODELO — RECOMENDADOS POCO F5</Text>
          {MODELS_PRESET.map((p, i) => {
            const installed = ollamaModels.some(x => x.name === p.name);
            return (
              <TouchableOpacity
                key={i}
                style={[s.presetRow, installed && { opacity: 0.45 }]}
                onPress={() => !installed && pullModel(p.name)}
                disabled={installed}
              >
                <View style={{ flex: 1 }}>
                  <Text style={s.presetName}>{p.name}</Text>
                  <Text style={s.presetMeta}>{p.size} · {p.tag}</Text>
                </View>
                <Text style={{ color: installed ? C.green : C.cyan, fontSize: 18 }}>
                  {installed ? '✓' : '↓'}
                </Text>
              </TouchableOpacity>
            );
          })}
        </View>
      );
    }

    // ── SSH ───────────────────────────────────
    if (m.id === 'ssh') {
      const info = sshInfo;
      return (
        <View style={s.expanded}>
          {divider}
          {info ? (
            <>
              <Text style={s.expLabel}>CONEXIÓN</Text>
              <InfoRow2 k="IP WiFi"  v={info.ip} />
              <InfoRow2 k="Puerto"   v={info.port} />
              <InfoRow2 k="Usuario"  v={info.user} />
              <InfoRow2 k="Claves SSH autorizadas" v={`${info.keys}`} />
              {divider}
              <Text style={s.expLabel}>COMANDO — toca para copiar</Text>
              <TouchableOpacity style={s.urlBox} onPress={() => Alert.alert('Comando SSH', info.cmd)}>
                <Text style={[s.urlText, { fontSize: 11 }]}>{info.cmd}</Text>
                <Text style={s.urlCopy}>📋</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.urlBox} onPress={() => Alert.alert('Comando SCP', info.scp_cmd)}>
                <Text style={[s.urlText, { fontSize: 11 }]}>{info.scp_cmd}</Text>
                <Text style={s.urlCopy}>📋</Text>
              </TouchableOpacity>
            </>
          ) : (
            <View style={{ alignItems: 'center', padding: 12 }}>
              <ActivityIndicator color={C.cyan} />
            </View>
          )}
          {divider}
          <Text style={s.expHint}>Para agregar claves: menu → [6] SSH → [4]</Text>
        </View>
      );
    }

    // ── CLAUDE CODE ───────────────────────────
    if (m.id === 'claude') {
      return (
        <View style={s.expanded}>
          {divider}
          <Text style={s.expLabel}>INFO</Text>
          <InfoRow2 k="Versión fija" v="2.1.111" />
          <InfoRow2 k="Instalación" v="GitHub Releases (no npm)" />
          <InfoRow2 k="Por qué fija" v=">2.1.111 requiere glibc" />
          {divider}
          <Text style={s.expLabel}>COMANDOS EN TERMUX</Text>
          {['claude', 'claude -p "instrucción"', 'claude --version'].map((c, i) => (
            <View key={i} style={s.cmdBox}><Text style={s.cmdText}>{c}</Text></View>
          ))}
        </View>
      );
    }

    // ── EXPO / EAS ────────────────────────────
    if (m.id === 'eas') {
      return (
        <View style={s.expanded}>
          {divider}
          <Text style={s.expLabel}>INFO</Text>
          <InfoRow2 k="Versión" v={m.version ? `v${m.version}` : '—'} />
          <InfoRow2 k="Builds"  v="expo.dev (nube)" />
          {divider}
          <Text style={s.expLabel}>COMANDOS</Text>
          {[
            'EAS_SKIP_AUTO_FINGERPRINT=1 eas build \\',
            '  --platform android --profile preview',
            'eas build:list',
            'eas whoami',
          ].map((c, i) => (
            <View key={i} style={s.cmdBox}><Text style={s.cmdText}>{c}</Text></View>
          ))}
          <Text style={s.expHint}>Flag EAS_SKIP_AUTO_FINGERPRINT=1 es obligatorio en Termux.</Text>
        </View>
      );
    }

    // ── PYTHON ────────────────────────────────
    if (m.id === 'python') {
      return (
        <View style={s.expanded}>
          {divider}
          <Text style={s.expLabel}>INFO</Text>
          <InfoRow2 k="Versión" v={m.version ? `v${m.version}` : '—'} />
          <InfoRow2 k="Uso"     v="dashboard_server.py · trading scripts" />
          {divider}
          <Text style={s.expLabel}>COMANDOS</Text>
          {[
            'python3 script.py',
            'pip install pkg --break-system-packages',
            'python3 -m http.server 8888',
          ].map((c, i) => (
            <View key={i} style={s.cmdBox}><Text style={s.cmdText}>{c}</Text></View>
          ))}
        </View>
      );
    }

    return null;
  };

  // ══════════════════════════════════════════════
  //  PESTAÑA: SISTEMA
  // ══════════════════════════════════════════════
  const renderSystem = () => {
    const ram = status.ram || {};
    return (
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 14 }}>
        <View style={s.sysCard}>
          <Text style={s.sysLabel}>SISTEMA</Text>
          <InfoRow2 k="IP WiFi"     v={status.ip} />
          <InfoRow2 k="RAM libre"   v={ram.available_mb ? `${ram.available_mb} MB` : '--'} />
          <InfoRow2 k="RAM total"   v={ram.total_mb ? `${(ram.total_mb/1024).toFixed(1)} GB` : '--'} />
          <InfoRow2 k="Dashboard"   v=":8080 activo" vc={C.green} />
          <InfoRow2 k="Sync"        v={lastSync} />
        </View>

        <View style={s.sysCard}>
          <Text style={s.sysLabel}>MÓDULOS</Text>
          {(status.modules || []).map(m => {
            const isService = ['n8n','ollama','ssh'].includes(m.id);
            const color = !m.installed ? C.dim : (isService && m.running) ? C.green : C.yellow;
            const label = !m.installed ? 'no instalado' : isService ? (m.running ? 'activo' : 'listo') : `listo · v${m.version || '?'}`;
            return <InfoRow2 key={m.id} k={`${m.running ? '●' : '○'} ${m.name}`} v={label} kc={color} vc={color} />;
          })}
        </View>

        <View style={s.sysCard}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
            <Text style={s.sysLabel}>ACCIONES RECIENTES</Text>
            <TouchableOpacity onPress={fetchLogs}><Text style={{ color: C.cyan, fontSize: 12 }}>↻</Text></TouchableOpacity>
          </View>
          {logs.length === 0
            ? <Text style={{ color: C.dim, fontSize: 13 }}>Sin acciones registradas.</Text>
            : logs.slice().reverse().map((l, i) => (
              <View key={i} style={{ flexDirection: 'row', marginBottom: 5, gap: 8 }}>
                <Text style={{ color: C.dim, fontSize: 11, width: 58 }}>{l.ts}</Text>
                <Text style={{ color: l.ok ? C.green : C.red, fontSize: 11, flex: 1 }}>
                  {l.module} {l.action} {l.ok ? '✓' : '✗'}
                </Text>
              </View>
            ))
          }
        </View>

        <View style={s.sysCard}>
          <Text style={s.sysLabel}>COMANDOS RÁPIDOS</Text>
          {['bash ~/dashboard_start.sh', 'menu', 'bash ~/backup.sh', 'bash ~/restore.sh'].map((c, i) => (
            <View key={i} style={s.cmdBox}><Text style={s.cmdText}>{c}</Text></View>
          ))}
        </View>
        <View style={{ height: 40 }} />
      </ScrollView>
    );
  };

  // ══════════════════════════════════════════════
  //  PESTAÑA: AYUDA
  // ══════════════════════════════════════════════
  const renderHelp = () => (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 14 }}>
      {[
        { title: 'Sin conexión', body: 'El dashboard debe estar corriendo en Termux. Ejecuta: bash ~/dashboard_start.sh\n\nLa app se reconecta automáticamente.' },
        { title: 'Botón start no responde', body: 'n8n puede tardar hasta 35s en arrancar. Ollama ~5-10s. SSH ~1s.\n\nEl spinner desaparece cuando el proceso confirma estado activo.' },
        { title: 'Claude "no instalado"', body: 'Presiona [r] Refrescar en Termux (menu). Si persiste, reinstala desde: menu → [2] Claude Code → [2] GitHub Releases.' },
        { title: 'EAS / Expo no detectado', body: 'El registry puede estar desactualizado. Ejecuta install_expo.sh o refrescar con [r] en el menú de Termux.' },
        { title: 'Backup', body: 'Guarda ~/.android_server_registry + configs en /sdcard/termux-backup/. Desde la app toca el ícono de nube en la lista.' },
        { title: 'Ollama rendimiento lento', body: 'Bug #27290 activo en termux-packages. No hay workaround — esperar fix oficial. Modelos recomendados: qwen2.5:0.5b o qwen2.5:1.5b.' },
      ].map((item, i) => (
        <View key={i} style={s.sysCard}>
          <Text style={{ color: C.cyan, fontSize: 13, fontWeight: '700', marginBottom: 6 }}>{item.title}</Text>
          <Text style={{ color: C.text2, fontSize: 12, lineHeight: 18 }}>{item.body}</Text>
        </View>
      ))}
      <View style={s.sysCard}>
        <Text style={s.sysLabel}>VERSIÓN</Text>
        <InfoRow2 k="App" v="v1.5.0" />
        <InfoRow2 k="SDK Expo" v="50.0.0" />
        <InfoRow2 k="React Native" v="0.73.6" />
        <InfoRow2 k="Dashboard" v="v1.3.0" />
        <InfoRow2 k="menu.sh" v="v3.6.0" />
      </View>
      <View style={{ height: 40 }} />
    </ScrollView>
  );

  // ══════════════════════════════════════════════
  //  RENDER PRINCIPAL
  // ══════════════════════════════════════════════
  const ram = status.ram || {};
  const ramStr = ram.available_mb ? `${(ram.available_mb/1024).toFixed(1)} GB` : '--';
  const isOnline = !connErr;

  return (
    <View style={s.root}>
      <StatusBar style="light" />

      {/* ── HEADER ───────────────────────────── */}
      <View style={s.header}>
        {/* Indicador de conexión */}
        <View style={s.headerTop}>
          <View style={s.headerDot}>
            <View style={[s.dotInner, { backgroundColor: isOnline ? C.green : C.red }]} />
            <Text style={s.headerBrand}>TERMUX · AI · STACK</Text>
          </View>
          <Text style={s.syncText}>sync {lastSync}</Text>
        </View>
        {/* Stats */}
        <View style={s.statsRow}>
          <StatChip icon="⚡" label={`RAM: ${ramStr}`} />
          <StatChip icon="📡" label={`IP: ${status.ip}`} />
          {ram.total_mb ? <StatChip icon="💾" label={`${(ram.total_mb/1024).toFixed(0)} GB total`} /> : null}
        </View>
        {/* Banner reconexión */}
        {connErr && (
          <View style={s.offlineBanner}>
            <Text style={s.offlineBannerText}>⚠ Sin conexión — reintentando...</Text>
          </View>
        )}
      </View>

      {/* ── CONTENIDO ────────────────────────── */}
      {footerTab === 'home' && (
        <ScrollView
          style={{ flex: 1 }}
          contentContainerStyle={{ paddingHorizontal: 12, paddingTop: 10, paddingBottom: 80 }}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => fetchStatus(true)} tintColor={C.cyan} />}
        >
          {/* Sección módulos */}
          <Text style={s.sectionLabel}>MÓDULOS</Text>
          {(status.modules || []).map(m => renderCard(m))}

          {/* Backup / Restore */}
          <Text style={[s.sectionLabel, { marginTop: 6 }]}>SISTEMA</Text>

          {/* Card Backup */}
          <View style={s.card}>
            <TouchableOpacity style={s.cardRow} onPress={doBackup} activeOpacity={0.7}>
              <ModuleIcon id="backup" size={44} />
              <View style={s.cardMid}>
                <Text style={s.cardName}>Backup / Restore</Text>
                <Text style={s.cardVer}>registry + configs → /sdcard</Text>
              </View>
              <TouchableOpacity style={[s.cardBtn, s.cardBtnSub]} onPress={doBackup}>
                <Text style={s.cardBtnText}>Backup</Text>
              </TouchableOpacity>
            </TouchableOpacity>
            <View style={s.divider} />
            <TouchableOpacity
              onPress={() => Alert.alert('Restore', 'Ejecuta en Termux:\n\nbash ~/restore.sh\n\nO: menú → [0] → Restore')}
              style={{ paddingVertical: 8, paddingHorizontal: 4 }}
            >
              <Text style={{ color: C.cyan, fontSize: 13 }}>♻️  Ver instrucciones de restore →</Text>
            </TouchableOpacity>
          </View>
        </ScrollView>
      )}

      {footerTab === 'system' && renderSystem()}
      {footerTab === 'help'   && renderHelp()}

      {/* ── FOOTER NAV ───────────────────────── */}
      <View style={s.footer}>
        {[
          { key: 'home',   icon: '⊞',  label: 'Módulos'  },
          { key: 'system', icon: '◎',  label: 'Sistema'  },
          { key: 'help',   icon: '?',  label: 'Ayuda'    },
        ].map(tab => (
          <TouchableOpacity
            key={tab.key}
            style={s.footerTab}
            onPress={() => { setFooterTab(tab.key); if (tab.key === 'system') fetchLogs(); }}
          >
            <Text style={[s.footerIcon, footerTab === tab.key && s.footerIconActive]}>
              {tab.icon}
            </Text>
            <Text style={[s.footerLabel, footerTab === tab.key && s.footerLabelActive]}>
              {tab.label}
            </Text>
            {footerTab === tab.key && <View style={s.footerIndicator} />}
          </TouchableOpacity>
        ))}
      </View>
    </View>
  );
}

// ─────────────────────────────────────────────
//  HELPERS
// ─────────────────────────────────────────────
function StatChip({ icon, label }) {
  return (
    <View style={s.statChip}>
      <Text style={{ fontSize: 10, marginRight: 3 }}>{icon}</Text>
      <Text style={s.statText}>{label}</Text>
    </View>
  );
}

function InfoRow2({ k, v, kc, vc }) {
  return (
    <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginBottom: 6 }}>
      <Text style={{ fontSize: 12, color: kc || C.dim, flex: 1 }}>{k}</Text>
      <Text style={{ fontSize: 12, color: vc || C.white, flex: 2, textAlign: 'right' }}>{v}</Text>
    </View>
  );
}

// ─────────────────────────────────────────────
//  ESTILOS
// ─────────────────────────────────────────────
const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: C.bg },

  // Offline
  center: { flex: 1, backgroundColor: C.bg, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 32 },
  offlineHex:   { fontSize: 56, color: C.cyan, marginBottom: 16 },
  offlineTitle: { fontSize: 22, fontWeight: '700', color: C.white, marginBottom: 8 },
  offlineSub:   { fontSize: 14, color: C.dim, marginBottom: 16 },
  offlineCode:  { backgroundColor: C.surface, borderWidth: 1, borderColor: C.border, borderRadius: 10, paddingVertical: 12, paddingHorizontal: 20, marginBottom: 14 },
  offlineCmd:   { fontSize: 13, color: C.green, fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier' },
  offlineHint:  { fontSize: 12, color: C.dim, textAlign: 'center', marginBottom: 24 },
  retryBtn:     { backgroundColor: C.cyanDim, borderWidth: 1, borderColor: C.cyan + '66', borderRadius: 10, paddingVertical: 12, paddingHorizontal: 28 },
  retryText:    { fontSize: 14, fontWeight: '600', color: C.cyan },

  // Header
  header: {
    paddingTop: Platform.OS === 'android' ? 40 : 52,
    paddingHorizontal: 14, paddingBottom: 10,
    backgroundColor: C.surface,
    borderBottomWidth: 1, borderBottomColor: C.border,
  },
  headerTop:    { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 },
  headerDot:    { flexDirection: 'row', alignItems: 'center', gap: 8 },
  dotInner:     { width: 8, height: 8, borderRadius: 4 },
  headerBrand:  { fontSize: 13, fontWeight: '700', color: C.cyan, letterSpacing: 2 },
  syncText:     { fontSize: 11, color: C.dim },
  statsRow:     { flexDirection: 'row', gap: 6, flexWrap: 'wrap' },
  statChip:     { flexDirection: 'row', alignItems: 'center', backgroundColor: C.card, borderWidth: 1, borderColor: C.border, borderRadius: 20, paddingHorizontal: 10, paddingVertical: 4 },
  statText:     { fontSize: 11, color: C.text2 },
  offlineBanner:{ marginTop: 8, backgroundColor: C.yellowDim, borderRadius: 6, paddingVertical: 4, paddingHorizontal: 10 },
  offlineBannerText: { fontSize: 11, color: C.yellow },

  // Cards
  sectionLabel: { fontSize: 11, color: C.dim, fontWeight: '700', letterSpacing: 1, marginBottom: 8, marginLeft: 2 },

  card: {
    backgroundColor: C.card,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: C.border,
    marginBottom: 8,
    overflow: 'hidden',
  },
  cardExpanded: { borderColor: C.cyan + '44' },

  cardRow: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
    gap: 10,
  },
  cardMid:  { flex: 1 },
  cardName: { fontSize: 15, fontWeight: '700', color: C.white },
  cardVer:  { fontSize: 11, color: C.dim, marginTop: 1 },
  cardRight:{ flexDirection: 'row', alignItems: 'center', gap: 6 },

  cardBtn: {
    paddingHorizontal: 12, paddingVertical: 7,
    borderRadius: 8, borderWidth: 1,
  },
  cardBtnSub:     { backgroundColor: C.cyanDim, borderColor: C.cyan + '55' },
  cardBtnInstall: { backgroundColor: '#1f3a1f', borderColor: C.green + '55' },
  cardBtnText:    { fontSize: 12, fontWeight: '600', color: C.white },

  // Feedback
  feedOk:      { fontSize: 11, color: C.green,  paddingHorizontal: 14, paddingBottom: 6 },
  feedErr:     { fontSize: 11, color: C.red,    paddingHorizontal: 14, paddingBottom: 6 },
  feedPending: { fontSize: 11, color: C.yellow, paddingHorizontal: 14, paddingBottom: 6 },

  // Expandido
  expanded: { paddingHorizontal: 14, paddingBottom: 12 },
  divider:  { height: 1, backgroundColor: C.border, marginVertical: 10 },
  expLabel: { fontSize: 10, color: C.dim, fontWeight: '700', letterSpacing: 0.8, marginBottom: 8 },
  expHint:  { fontSize: 12, color: C.dim, lineHeight: 18 },
  expRowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  expRefresh: { alignSelf: 'flex-start', marginTop: 6 },

  warnBox:  { backgroundColor: C.yellowDim, borderWidth: 1, borderColor: C.yellow + '44', borderRadius: 8, padding: 10 },
  warnText: { fontSize: 12, color: C.yellow, lineHeight: 18 },

  urlBox: {
    backgroundColor: C.bg, borderRadius: 8, borderWidth: 1, borderColor: C.border,
    paddingVertical: 8, paddingHorizontal: 10, marginBottom: 6,
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
  },
  urlText: { fontSize: 12, color: C.cyan, flex: 1, fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier' },
  urlCopy: { fontSize: 14, marginLeft: 8 },

  modelRow:  { flexDirection: 'row', alignItems: 'center', paddingVertical: 6, gap: 8 },
  modelDot:  { width: 6, height: 6, borderRadius: 3, backgroundColor: C.green },
  modelName: { fontSize: 13, color: C.white, flex: 1, fontWeight: '600' },
  modelSize: { fontSize: 11, color: C.dim },

  presetRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 10, paddingHorizontal: 4,
    borderBottomWidth: 1, borderBottomColor: C.border + '55',
  },
  presetName: { fontSize: 13, color: C.white, fontWeight: '600' },
  presetMeta: { fontSize: 11, color: C.dim, marginTop: 2 },

  cmdBox: {
    backgroundColor: C.bg, borderRadius: 7, borderWidth: 1, borderColor: C.border,
    paddingVertical: 7, paddingHorizontal: 10, marginBottom: 5,
  },
  cmdText: {
    fontSize: 11, color: C.green,
    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier',
  },

  // Sistema / Ayuda
  sysCard: {
    backgroundColor: C.card, borderRadius: 12, borderWidth: 1, borderColor: C.border,
    padding: 14, marginBottom: 10,
  },
  sysLabel: { fontSize: 10, color: C.dim, fontWeight: '700', letterSpacing: 0.8, marginBottom: 10 },

  // Footer
  footer: {
    flexDirection: 'row',
    backgroundColor: C.footer,
    borderTopWidth: 1,
    borderTopColor: C.border,
    paddingBottom: Platform.OS === 'android' ? 12 : 20,
    paddingTop: 8,
  },
  footerTab:          { flex: 1, alignItems: 'center', position: 'relative', paddingVertical: 2 },
  footerIcon:         { fontSize: 18, color: C.dim, marginBottom: 3 },
  footerIconActive:   { color: C.cyan },
  footerLabel:        { fontSize: 10, color: C.dim, fontWeight: '500' },
  footerLabelActive:  { color: C.cyan, fontWeight: '700' },
  footerIndicator:    { position: 'absolute', top: 0, width: 24, height: 2, backgroundColor: C.cyan, borderRadius: 2 },
});
