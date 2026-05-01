// termux-ai-stack · App.js
// v1.6.0 | Mayo 2026
// Chat Ollama · Config Claude · Gestión modelos · Submenús completos

import { StatusBar } from 'expo-status-bar';
import { useEffect, useState, useCallback, useRef } from 'react';
import {
  StyleSheet, Text, View, ScrollView, Switch, TextInput,
  TouchableOpacity, RefreshControl, ActivityIndicator,
  Platform, Alert, BackHandler, KeyboardAvoidingView,
  FlatList,
} from 'react-native';

// ─────────────────────────────────────────────
//  CONFIG
// ─────────────────────────────────────────────
const API         = 'http://localhost:8080';
const POLL_MS     = 3000;
const FETCH_MS    = 4000;
const POLL_ACT_MS = 2000;
const POLL_MAX    = 25;
const CHAT_ID     = 'app_local';

// ─────────────────────────────────────────────
//  PALETA
// ─────────────────────────────────────────────
const C = {
  bg:        '#0d1117',
  surface:   '#13181f',
  card:      '#161b22',
  cardHi:    '#1c2230',
  border:    '#21262d',
  borderHi:  '#388bfd44',
  cyan:      '#58a6ff',
  cyanDim:   '#1f3a5f',
  green:     '#3fb950',
  greenDim:  '#1a3a22',
  yellow:    '#d29922',
  yellowDim: '#3a2e10',
  red:       '#f85149',
  redDim:    '#3a1a1a',
  dim:       '#6e7681',
  white:     '#e6edf3',
  text2:     '#8b949e',
  chatUser:  '#1f3a5f',
  chatBot:   '#161b22',
};

// ─────────────────────────────────────────────
//  FETCH HELPER
// ─────────────────────────────────────────────
async function apiFetch(path, opts = {}, ms = FETCH_MS) {
  const ctrl = new AbortController();
  const id   = setTimeout(() => ctrl.abort(), ms);
  try {
    const r = await fetch(API + path, { ...opts, signal: ctrl.signal });
    clearTimeout(id);
    return r;
  } catch (e) {
    clearTimeout(id);
    throw e;
  }
}

// ─────────────────────────────────────────────
//  ICONOS
// ─────────────────────────────────────────────
function ModuleIcon({ id, size = 44 }) {
  const map = {
    n8n:       { bg: '#1a2332', text: '∞',  color: '#e05d28', fs: size * 0.55 },
    ollama:    { bg: '#1a2a1a', text: '🦙', color: '#fff',    fs: size * 0.52 },
    claude:    { bg: '#2a1a1a', text: 'A\\', color: '#d4a027', fs: size * 0.45 },
    eas:       { bg: '#1a1a2a', text: '▲',  color: '#7c7cff', fs: size * 0.5  },
    python:    { bg: '#1a2a1a', text: '🐍', color: '#fff',    fs: size * 0.52 },
    ssh:       { bg: '#0d1f0d', text: '>_', color: '#3fb950', fs: size * 0.38 },
    backup:    { bg: '#1a2a2a', text: '☁',  color: '#58a6ff', fs: size * 0.52 },
    chat:      { bg: '#1a2a2a', text: '💬', color: '#58a6ff', fs: size * 0.52 },
  };
  const cfg = map[id] || { bg: '#1a1a1a', text: '?', color: '#fff', fs: size * 0.5 };
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
//  PILL ESTADO
// ─────────────────────────────────────────────
function StatusPill({ installed, running, isService }) {
  if (!installed) return (
    <View style={[P.base, { backgroundColor: C.surface, borderColor: C.border }]}>
      <Text style={[P.text, { color: C.dim }]}>no instalado</Text>
    </View>
  );
  if (isService && running) return (
    <View style={[P.base, { backgroundColor: C.greenDim, borderColor: C.green + '66' }]}>
      <View style={P.dot} />
      <Text style={[P.text, { color: C.green }]}>activo</Text>
    </View>
  );
  return (
    <View style={[P.base, { backgroundColor: C.yellowDim, borderColor: C.yellow + '66' }]}>
      <Text style={[P.text, { color: C.yellow }]}>listo</Text>
    </View>
  );
}
const P = StyleSheet.create({
  base: { flexDirection: 'row', alignItems: 'center', borderWidth: 1, borderRadius: 20, paddingHorizontal: 8, paddingVertical: 3 },
  dot:  { width: 6, height: 6, borderRadius: 3, backgroundColor: C.green, marginRight: 4 },
  text: { fontSize: 11, fontWeight: '600' },
});

// ─────────────────────────────────────────────
//  MODELOS PRESET
// ─────────────────────────────────────────────
const MODELS_PRESET = [
  { name: 'qwen2.5:0.5b',    size: '~400 MB',  tag: 'Más liviano' },
  { name: 'qwen2.5:1.5b',    size: '~986 MB',  tag: 'Recomendado' },
  { name: 'qwen:1.8b',       size: '~1.1 GB',  tag: 'Balance'     },
  { name: 'llama3.2:1b',     size: '~1.3 GB',  tag: 'Meta'        },
  { name: 'phi3:mini',       size: '~2.3 GB',  tag: 'Más calidad' },
  { name: 'moondream:1.8b',  size: '~1.7 GB',  tag: 'Visión'      },
];

// ─────────────────────────────────────────────
//  HELPERS UI
// ─────────────────────────────────────────────
function InfoRow({ k, v, kc, vc }) {
  return (
    <View style={{ flexDirection: 'row', justifyContent: 'space-between', marginBottom: 6 }}>
      <Text style={{ fontSize: 12, color: kc || C.dim, flex: 1 }}>{k}</Text>
      <Text style={{ fontSize: 12, color: vc || C.white, flex: 2, textAlign: 'right' }} selectable>{v}</Text>
    </View>
  );
}

function SectionLabel({ label }) {
  return <Text style={S.expLabel}>{label}</Text>;
}

function Divider() {
  return <View style={S.divider} />;
}

function CmdBox({ text }) {
  return (
    <View style={S.cmdBox}>
      <Text style={S.cmdText} selectable>{text}</Text>
    </View>
  );
}

function ActionBtn({ label, color = C.cyan, onPress, loading = false, danger = false }) {
  const bg = danger ? C.redDim : C.cyanDim;
  const bc = danger ? C.red + '55' : color + '55';
  const tc = danger ? C.red : color;
  return (
    <TouchableOpacity
      style={[S.actionBtn, { backgroundColor: bg, borderColor: bc }]}
      onPress={onPress}
      disabled={loading}
    >
      {loading
        ? <ActivityIndicator color={tc} size="small" />
        : <Text style={[S.actionBtnText, { color: tc }]}>{label}</Text>
      }
    </TouchableOpacity>
  );
}

// ─────────────────────────────────────────────
//  APP PRINCIPAL
// ─────────────────────────────────────────────
export default function App() {
  const [status,       setStatus]      = useState(null);
  const [connErr,      setConnErr]     = useState(false);
  const [refreshing,   setRefreshing]  = useState(false);
  const [lastSync,     setLastSync]    = useState('--');
  const [actState,     setActState]    = useState({});
  const [expanded,     setExpanded]    = useState({});
  const [footerTab,    setFooterTab]   = useState('home');
  const [logs,         setLogs]        = useState([]);

  // Ollama
  const [ollamaModels, setOllamaModels]   = useState([]);
  const [ollamaDeleting, setOllamaDeleting] = useState({});

  // SSH
  const [sshInfo, setSshInfo] = useState(null);

  // N8N
  const [n8nUrl, setN8nUrl] = useState('');

  // Claude config
  const [claudeKey,      setClaudeKey]      = useState('');
  const [claudeEndpoint, setClaudeEndpoint] = useState('');
  const [claudeSaving,   setClaudeSaving]   = useState(false);
  const [claudeSaved,    setClaudeSaved]    = useState(false);

  // Chat
  const [chatMessages, setChatMessages]   = useState([]);
  const [chatInput,    setChatInput]      = useState('');
  const [chatModel,    setChatModel]      = useState('qwen2.5:0.5b');
  const [chatLoading,  setChatLoading]    = useState(false);
  const [chatNumCtx,   setChatNumCtx]     = useState(4096);
  const chatScrollRef = useRef(null);

  const pollRef = useRef({});

  // ── BackHandler ─────────────────────────────
  useEffect(() => {
    const h = () => {
      if (footerTab === 'chat') { setFooterTab('home'); return true; }
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
      const d = await r.json();
      setStatus(d);
      setConnErr(false);
      setLastSync(new Date().toLocaleTimeString());
      // Sync claude config fields
      if (d.claude_cfg) {
        if (d.claude_cfg.api_key)  setClaudeKey(d.claude_cfg.api_key);
        if (d.claude_cfg.endpoint) setClaudeEndpoint(d.claude_cfg.endpoint);
      }
    } catch {
      setConnErr(true);
    } finally {
      if (manual) setRefreshing(false);
    }
  }, []);

  const fetchLogs = useCallback(async () => {
    try {
      const r = await apiFetch('/api/logs');
      if (r.ok) { const d = await r.json(); setLogs(d.logs || []); }
    } catch {}
  }, []);

  const fetchOllama = useCallback(async () => {
    try {
      const r = await apiFetch('/api/ollama/models');
      if (r.ok) { const d = await r.json(); setOllamaModels(d.models || []); }
    } catch {}
  }, []);

  const fetchSsh = useCallback(async () => {
    try {
      const r = await apiFetch('/api/ssh/info');
      if (r.ok) setSshInfo(await r.json());
    } catch {}
  }, []);

  const fetchN8n = useCallback(async () => {
    try {
      const r = await apiFetch('/api/n8n/url');
      if (r.ok) { const d = await r.json(); setN8nUrl(d.url || ''); }
    } catch {}
  }, []);

  const fetchChatHistory = useCallback(async () => {
    try {
      const r = await apiFetch(`/api/chat/history?chat_id=${CHAT_ID}&limit=40`);
      if (r.ok) {
        const d = await r.json();
        const msgs = (d.messages || []).map((m, i) => ({
          id:   String(i),
          role: m.rol,
          text: m.content,
        }));
        setChatMessages(msgs);
      }
    } catch {}
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
          setStatus(d);
          setLastSync(new Date().toLocaleTimeString());
          clearInterval(timer);
          delete pollRef.current[id];
          setActState(s => ({ ...s, [id]: 'ok' }));
          if (id === 'ollama') fetchOllama();
          setTimeout(() => setActState(s => ({ ...s, [id]: null })), 2000);
          return;
        }
      } catch {}
      if (n >= POLL_MAX) {
        clearInterval(timer);
        delete pollRef.current[id];
        setActState(s => ({ ...s, [id]: 'error' }));
        setTimeout(() => setActState(s => ({ ...s, [id]: null })), 3000);
      }
    }, POLL_ACT_MS);
    pollRef.current[id] = timer;
  }, [fetchOllama]);

  // ── Acción start/stop ─────────────────────────
  const doAction = useCallback(async (moduleId, action) => {
    if (pollRef.current[moduleId]) {
      clearInterval(pollRef.current[moduleId]);
      delete pollRef.current[moduleId];
    }
    setActState(s => ({ ...s, [moduleId]: 'pending' }));
    try {
      const r = await apiFetch('/api/action', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ module: moduleId, action }),
      });
      const d = await r.json();
      if (d.ok) startPoll(moduleId, action === 'start');
      else {
        setActState(s => ({ ...s, [moduleId]: 'error' }));
        setTimeout(() => setActState(s => ({ ...s, [moduleId]: null })), 3000);
      }
    } catch {
      setActState(s => ({ ...s, [moduleId]: 'error' }));
      setTimeout(() => setActState(s => ({ ...s, [moduleId]: null })), 3000);
    }
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
    Alert.alert('Descargar modelo', `¿Descargar ${name}?\nPuede tardar varios minutos según la conexión.`, [
      { text: 'Cancelar', style: 'cancel' },
      {
        text: 'Descargar', onPress: async () => {
          try {
            const r = await apiFetch('/api/action', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ module: 'ollama', action: `pull:${name}` }),
            });
            const d = await r.json();
            Alert.alert(d.ok ? '↓ Descarga iniciada' : 'Error', d.msg);
          } catch {
            Alert.alert('Error', 'Sin conexión con el dashboard');
          }
        },
      },
    ]);
  }, []);

  // ── Delete modelo ─────────────────────────────
  const deleteModel = useCallback(async (name) => {
    Alert.alert('Eliminar modelo', `¿Eliminar ${name}? No se puede deshacer.`, [
      { text: 'Cancelar', style: 'cancel' },
      {
        text: 'Eliminar', style: 'destructive', onPress: async () => {
          setOllamaDeleting(s => ({ ...s, [name]: true }));
          try {
            const r = await apiFetch('/api/action', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ module: 'ollama', action: `delete:${name}` }),
            });
            const d = await r.json();
            if (d.ok) {
              setOllamaModels(prev => prev.filter(m => m.name !== name));
            }
            Alert.alert(d.ok ? '✓ Eliminado' : 'Error', d.msg || name);
          } catch {
            Alert.alert('Error', 'Sin conexión');
          } finally {
            setOllamaDeleting(s => ({ ...s, [name]: false }));
          }
        },
      },
    ]);
  }, []);

  // ── Backup ─────────────────────────────────────
  const doBackup = useCallback(() => {
    Alert.alert('Backup', '¿Crear backup ahora?\nSe guardará en /sdcard/termux-backup/', [
      { text: 'Cancelar', style: 'cancel' },
      {
        text: 'Crear', onPress: async () => {
          try {
            const r = await apiFetch('/api/action', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ module: 'system', action: 'backup' }),
            });
            const d = await r.json();
            Alert.alert(d.ok ? '✓ Backup iniciado' : 'Error', d.msg);
          } catch {
            Alert.alert('Error', 'Sin conexión');
          }
        },
      },
    ]);
  }, []);

  // ── Guardar config Claude ─────────────────────
  const saveClaudeConfig = useCallback(async () => {
    if (!claudeKey.trim() && !claudeEndpoint.trim()) return;
    setClaudeSaving(true);
    try {
      const r = await apiFetch('/api/claude/config', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ api_key: claudeKey.trim(), endpoint: claudeEndpoint.trim() }),
      });
      const d = await r.json();
      if (d.ok) {
        setClaudeSaved(true);
        setTimeout(() => setClaudeSaved(false), 2500);
      }
    } catch {} finally {
      setClaudeSaving(false);
    }
  }, [claudeKey, claudeEndpoint]);

  // ── Chat send ─────────────────────────────────
  const sendChat = useCallback(async () => {
    const text = chatInput.trim();
    if (!text || chatLoading) return;

    const userMsg = { id: Date.now().toString(), role: 'user', text };
    setChatMessages(prev => [...prev, userMsg]);
    setChatInput('');
    setChatLoading(true);

    try {
      const r = await apiFetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ model: chatModel, message: text, chat_id: CHAT_ID, num_ctx: chatNumCtx }),
      }, 130000);
      const d = await r.json();
      const botMsg = {
        id:   Date.now().toString() + '_bot',
        role: 'assistant',
        text: d.ok ? d.response : `[Error: ${d.error || 'Sin respuesta'}]`,
      };
      setChatMessages(prev => [...prev, botMsg]);
    } catch (e) {
      setChatMessages(prev => [...prev, {
        id: Date.now().toString() + '_err',
        role: 'assistant',
        text: '[Timeout o sin conexión — Ollama puede tardar en responder]',
      }]);
    } finally {
      setChatLoading(false);
      setTimeout(() => chatScrollRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [chatInput, chatLoading, chatModel, chatNumCtx]);

  // ── Limpiar chat ──────────────────────────────
  const clearChat = useCallback(() => {
    Alert.alert('Limpiar historial', '¿Borrar todo el historial de este chat?', [
      { text: 'Cancelar', style: 'cancel' },
      {
        text: 'Limpiar', style: 'destructive', onPress: async () => {
          try {
            await apiFetch('/api/chat/clear', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ chat_id: CHAT_ID }),
            });
          } catch {}
          setChatMessages([]);
        },
      },
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
      <View style={S.center}>
        <StatusBar style="light" />
        <Text style={S.offlineHex}>⬡</Text>
        <Text style={S.offlineTitle}>Dashboard offline</Text>
        <Text style={S.offlineSub}>Abre Termux y ejecuta:</Text>
        <View style={S.offlineCode}>
          <Text style={S.offlineCmd}>bash ~/dashboard_start.sh</Text>
        </View>
        <Text style={S.offlineHint}>Se reconecta automáticamente cada {POLL_MS / 1000}s</Text>
        <TouchableOpacity style={S.retryBtn} onPress={() => fetchStatus(true)}>
          <Text style={S.retryText}>↻  Reintentar ahora</Text>
        </TouchableOpacity>
      </View>
    );
  }

  if (!status) {
    return (
      <View style={S.center}>
        <StatusBar style="light" />
        <ActivityIndicator color={C.cyan} size="large" />
        <Text style={[S.offlineSub, { marginTop: 14 }]}>Conectando al dashboard...</Text>
      </View>
    );
  }

  // ══════════════════════════════════════════════
  //  EXPANDED CONTENT POR MÓDULO
  // ══════════════════════════════════════════════
  const renderExpanded = (m) => {

    // ── N8N ───────────────────────────────────
    if (m.id === 'n8n') return (
      <View style={S.expanded}>
        <Divider />
        <SectionLabel label="URL PÚBLICA — CLOUDFLARE TUNNEL" />
        {n8nUrl ? (
          <TouchableOpacity style={S.urlBox} onPress={() => Alert.alert('URL n8n', n8nUrl)}>
            <Text style={S.urlText} numberOfLines={1}>{n8nUrl}</Text>
            <Text style={S.urlCopy}>📋</Text>
          </TouchableOpacity>
        ) : (
          <Text style={S.expHint}>{m.running ? 'Tunnel iniciando... ↻ actualiza' : 'Inicia n8n para obtener URL'}</Text>
        )}
        <TouchableOpacity style={S.linkBtn} onPress={fetchN8n}>
          <Text style={S.linkBtnText}>↻ Actualizar URL</Text>
        </TouchableOpacity>
        <Divider />
        <SectionLabel label="INFO TÉCNICA" />
        <InfoRow k="Puerto interno" v="5678 (proot Debian)" />
        <InfoRow k="Acceso externo" v="443 via Cloudflare" />
        <InfoRow k="Node.js proot"  v="v20 LTS (fijo)" />
        <InfoRow k="Webhook URL"    v={n8nUrl || '—'} vc={C.cyan} />
        <Divider />
        <SectionLabel label="COMANDOS" />
        <CmdBox text="bash ~/start_servidor.sh" />
        <CmdBox text="bash ~/stop_servidor.sh" />
        <CmdBox text="# Logs n8n:" />
        <CmdBox text="cat ~/n8n_start.log" />
      </View>
    );

    // ── OLLAMA ────────────────────────────────
    if (m.id === 'ollama') return (
      <View style={S.expanded}>
        <Divider />
        <View style={S.warnBox}>
          <Text style={S.warnText}>⚠ Bug #27290 activo — rendimiento reducido hasta fix oficial de termux-packages.</Text>
        </View>
        <Divider />

        {/* Modelos instalados */}
        <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
          <SectionLabel label="MODELOS INSTALADOS" />
          <TouchableOpacity onPress={fetchOllama}>
            <Text style={{ color: C.cyan, fontSize: 13 }}>↻</Text>
          </TouchableOpacity>
        </View>
        {ollamaModels.length === 0 ? (
          <Text style={S.expHint}>{m.running ? 'No hay modelos descargados.' : 'Inicia Ollama para listar modelos.'}</Text>
        ) : (
          ollamaModels.map((mod) => (
            <View key={mod.name} style={S.modelRow}>
              <View style={S.modelDot} />
              <View style={{ flex: 1 }}>
                <Text style={S.modelName}>{mod.name}</Text>
                <Text style={S.modelSize}>{mod.size}</Text>
              </View>
              {/* Usar como modelo de chat */}
              <TouchableOpacity
                style={[S.smallBtn, chatModel === mod.name && S.smallBtnActive]}
                onPress={() => { setChatModel(mod.name); Alert.alert('✓ Modelo seleccionado', `${mod.name} se usará en el chat`); }}
              >
                <Text style={[S.smallBtnText, chatModel === mod.name && { color: C.cyan }]}>
                  {chatModel === mod.name ? '● chat' : 'chat'}
                </Text>
              </TouchableOpacity>
              {/* Eliminar */}
              <TouchableOpacity
                style={[S.smallBtn, { borderColor: C.red + '55', backgroundColor: C.redDim }]}
                onPress={() => deleteModel(mod.name)}
                disabled={ollamaDeleting[mod.name]}
              >
                {ollamaDeleting[mod.name]
                  ? <ActivityIndicator color={C.red} size="small" />
                  : <Text style={[S.smallBtnText, { color: C.red }]}>✕</Text>
                }
              </TouchableOpacity>
            </View>
          ))
        )}

        <Divider />

        {/* Memoria de contexto */}
        <SectionLabel label="MEMORIA DE CONTEXTO (num_ctx)" />
        <View style={{ flexDirection: 'row', gap: 8, flexWrap: 'wrap', marginBottom: 10 }}>
          {[512, 1024, 2048, 4096, 8192].map(n => (
            <TouchableOpacity
              key={n}
              style={[S.ctxBtn, chatNumCtx === n && S.ctxBtnActive]}
              onPress={() => setChatNumCtx(n)}
            >
              <Text style={[S.ctxBtnText, chatNumCtx === n && { color: C.cyan }]}>{n}</Text>
            </TouchableOpacity>
          ))}
        </View>
        <Text style={S.expHint}>Más contexto = más RAM usada. Para F5 con 11GB, máximo recomendado: 4096.</Text>

        <Divider />

        {/* Descargar modelos */}
        <SectionLabel label="DESCARGAR MODELO" />
        {MODELS_PRESET.map((p) => {
          const installed = ollamaModels.some(x => x.name === p.name);
          return (
            <TouchableOpacity
              key={p.name}
              style={[S.presetRow, installed && { opacity: 0.45 }]}
              onPress={() => !installed && pullModel(p.name)}
              disabled={installed}
            >
              <View style={{ flex: 1 }}>
                <Text style={S.presetName}>{p.name}</Text>
                <Text style={S.presetMeta}>{p.size} · {p.tag}</Text>
              </View>
              <Text style={{ color: installed ? C.green : C.cyan, fontSize: 20 }}>
                {installed ? '✓' : '↓'}
              </Text>
            </TouchableOpacity>
          );
        })}

        <Divider />
        <SectionLabel label="ACCESO RÁPIDO AL CHAT" />
        <ActionBtn
          label={`💬 Abrir chat con ${chatModel}`}
          onPress={() => setFooterTab('chat')}
        />
      </View>
    );

    // ── SSH ───────────────────────────────────
    if (m.id === 'ssh') {
      const info = sshInfo;
      return (
        <View style={S.expanded}>
          <Divider />
          {info ? (
            <>
              <SectionLabel label="CONEXIÓN" />
              <InfoRow k="IP WiFi"  v={info.ip} />
              <InfoRow k="Puerto"   v={info.port} />
              <InfoRow k="Usuario"  v={info.user} />
              <InfoRow k="Claves autorizadas" v={String(info.keys)} />
              <Divider />
              <SectionLabel label="COMANDOS — toca para copiar" />
              <TouchableOpacity style={S.urlBox} onPress={() => Alert.alert('Comando SSH', info.cmd)}>
                <Text style={S.urlText} numberOfLines={1}>{info.cmd}</Text>
                <Text style={S.urlCopy}>📋</Text>
              </TouchableOpacity>
              <TouchableOpacity style={S.urlBox} onPress={() => Alert.alert('Comando SCP', info.scp_cmd)}>
                <Text style={S.urlText} numberOfLines={1}>{info.scp_cmd}</Text>
                <Text style={S.urlCopy}>📋</Text>
              </TouchableOpacity>
            </>
          ) : (
            <View style={{ alignItems: 'center', padding: 16 }}>
              <ActivityIndicator color={C.cyan} />
            </View>
          )}
          <Divider />
          <Text style={S.expHint}>Para agregar claves públicas: menu → [6] SSH → [4]</Text>
          <CmdBox text={`cat ~/.ssh/authorized_keys`} />
        </View>
      );
    }

    // ── CLAUDE CODE ───────────────────────────
    if (m.id === 'claude') return (
      <View style={S.expanded}>
        <Divider />
        <SectionLabel label="CONFIGURACIÓN API" />
        <Text style={[S.expHint, { marginBottom: 8 }]}>API Key y endpoint para Claude Code en Termux.</Text>

        <Text style={S.inputLabel}>API Key</Text>
        <TextInput
          style={S.input}
          value={claudeKey}
          onChangeText={setClaudeKey}
          placeholder="sk-ant-..."
          placeholderTextColor={C.dim}
          secureTextEntry
          autoCapitalize="none"
          autoCorrect={false}
        />

        <Text style={S.inputLabel}>Endpoint (opcional)</Text>
        <TextInput
          style={S.input}
          value={claudeEndpoint}
          onChangeText={setClaudeEndpoint}
          placeholder="https://api.anthropic.com"
          placeholderTextColor={C.dim}
          autoCapitalize="none"
          autoCorrect={false}
          keyboardType="url"
        />

        <ActionBtn
          label={claudeSaved ? '✓ Guardado' : claudeSaving ? 'Guardando...' : 'Guardar configuración'}
          onPress={saveClaudeConfig}
          loading={claudeSaving}
          color={claudeSaved ? C.green : C.cyan}
        />

        <Divider />
        <SectionLabel label="INFO TÉCNICA" />
        <InfoRow k="Versión fija"    v="2.1.111" />
        <InfoRow k="Instalación"     v="GitHub Releases (no npm)" />
        <InfoRow k="Por qué fija"    v=">2.1.111 requiere glibc" />
        <Divider />
        <SectionLabel label="COMANDOS EN TERMUX" />
        <CmdBox text="claude" />
        <CmdBox text='claude -p "instrucción aquí"' />
        <CmdBox text="claude --version" />
      </View>
    );

    // ── EXPO / EAS ────────────────────────────
    if (m.id === 'eas') return (
      <View style={S.expanded}>
        <Divider />
        <SectionLabel label="INFO" />
        <InfoRow k="Versión"   v={m.version ? `v${m.version}` : '—'} />
        <InfoRow k="Builds"    v="expo.dev (nube gratuita)" />
        <InfoRow k="projectId" v="7a6bb3e5..." />
        <Divider />
        <SectionLabel label="COMPILAR APK" />
        <CmdBox text="cd ~/termux-stack-ui" />
        <CmdBox text="EAS_SKIP_AUTO_FINGERPRINT=1 eas build \\" />
        <CmdBox text="  --platform android --profile preview" />
        <Divider />
        <SectionLabel label="OTROS COMANDOS" />
        <CmdBox text="eas build:list" />
        <CmdBox text="eas whoami" />
        <Text style={[S.expHint, { marginTop: 6 }]}>Flag EAS_SKIP_AUTO_FINGERPRINT=1 obligatorio en Termux.</Text>
      </View>
    );

    // ── PYTHON ────────────────────────────────
    if (m.id === 'python') return (
      <View style={S.expanded}>
        <Divider />
        <SectionLabel label="INFO" />
        <InfoRow k="Versión" v={m.version ? `v${m.version}` : '—'} />
        <InfoRow k="Uso"     v="dashboard · bots · trading scripts" />
        <Divider />
        <SectionLabel label="COMANDOS" />
        <CmdBox text="python3 script.py" />
        <CmdBox text="pip install pkg --break-system-packages" />
        <CmdBox text="python3 -c 'import sqlite3; print(sqlite3.version)'" />
      </View>
    );

    return null;
  };

  // ══════════════════════════════════════════════
  //  RENDER CARD
  // ══════════════════════════════════════════════
  const renderCard = (m) => {
    if (!m) return null;
    const isService  = ['n8n', 'ollama', 'ssh'].includes(m.id);
    const aState     = actState[m.id];
    const isPending  = aState === 'pending' || aState === 'confirming';
    const isExpanded = !!expanded[m.id];

    const onSwitch = (v) => {
      if (!m.installed) return;
      doAction(m.id, v ? 'start' : 'stop');
    };

    const extraFetch = m.id === 'ollama' ? fetchOllama
                     : m.id === 'ssh'    ? fetchSsh
                     : m.id === 'n8n'    ? fetchN8n
                     : null;

    let actionBtn = null;
    if (!m.installed) {
      actionBtn = (
        <TouchableOpacity
          style={[S.cardBtn, S.cardBtnInstall]}
          onPress={() => Alert.alert('Instalar', `Abre Termux y ejecuta:\n\nmenu\n\nLuego selecciona el módulo correspondiente.`)}
        >
          <Text style={S.cardBtnText}>Instalar</Text>
        </TouchableOpacity>
      );
    } else {
      actionBtn = (
        <TouchableOpacity
          style={[S.cardBtn, S.cardBtnSub]}
          onPress={() => toggleExpand(m.id, extraFetch)}
        >
          <Text style={S.cardBtnText}>{isExpanded ? 'Cerrar' : isService ? 'Submenú' : 'Info'}</Text>
        </TouchableOpacity>
      );
    }

    return (
      <View key={m.id} style={[S.card, isExpanded && S.cardExpanded]}>
        <TouchableOpacity
          style={S.cardRow}
          onPress={() => m.installed && toggleExpand(m.id, extraFetch)}
          activeOpacity={0.7}
        >
          <ModuleIcon id={m.id} size={44} />
          <View style={S.cardMid}>
            <Text style={S.cardName}>{m.name}</Text>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 3 }}>
              <StatusPill installed={m.installed} running={m.running} isService={isService} />
              {m.version ? <Text style={S.cardVer}>v{m.version}</Text> : null}
            </View>
          </View>
          <View style={S.cardRight}>
            {isService && m.installed ? (
              isPending ? (
                <ActivityIndicator color={C.cyan} size="small" style={{ marginRight: 6 }} />
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

        {aState === 'ok'    && <Text style={S.feedOk}>✓ Confirmado</Text>}
        {aState === 'error' && <Text style={S.feedErr}>✗ Sin respuesta — reintenta</Text>}
        {aState === 'confirming' && m.id === 'n8n' && (
          <Text style={S.feedPending}>⏳ n8n puede tardar ~35s en arrancar...</Text>
        )}

        {isExpanded && renderExpanded(m)}
      </View>
    );
  };

  // ══════════════════════════════════════════════
  //  PESTAÑA: CHAT OLLAMA
  // ══════════════════════════════════════════════
  const renderChat = () => {
    const ollamaModule = fm('ollama');
    const isRunning    = ollamaModule?.running;

    return (
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}
      >
        {/* Header chat */}
        <View style={S.chatHeader}>
          <View style={{ flex: 1 }}>
            <Text style={S.chatHeaderTitle}>Chat · {chatModel}</Text>
            <Text style={S.chatHeaderSub}>
              {isRunning ? `● activo · ctx ${chatNumCtx}` : '○ Ollama no está corriendo'}
            </Text>
          </View>
          <TouchableOpacity onPress={clearChat} style={S.chatClearBtn}>
            <Text style={{ color: C.red, fontSize: 12 }}>Limpiar</Text>
          </TouchableOpacity>
          <TouchableOpacity
            onPress={() => { fetchChatHistory(); }}
            style={[S.chatClearBtn, { marginLeft: 6 }]}
          >
            <Text style={{ color: C.cyan, fontSize: 13 }}>↻</Text>
          </TouchableOpacity>
        </View>

        {/* Mensajes */}
        <ScrollView
          ref={chatScrollRef}
          style={{ flex: 1 }}
          contentContainerStyle={{ padding: 12, paddingBottom: 8 }}
          onContentSizeChange={() => chatScrollRef.current?.scrollToEnd({ animated: true })}
        >
          {!isRunning && (
            <View style={[S.warnBox, { marginBottom: 12 }]}>
              <Text style={S.warnText}>⚠ Ollama no está activo. Actívalo desde la pestaña Módulos.</Text>
            </View>
          )}

          {chatMessages.length === 0 && (
            <View style={{ alignItems: 'center', paddingTop: 40 }}>
              <Text style={{ fontSize: 28, marginBottom: 12 }}>🦙</Text>
              <Text style={{ color: C.dim, fontSize: 14, textAlign: 'center' }}>
                Empieza una conversación con {chatModel}
              </Text>
              <Text style={{ color: C.dim, fontSize: 12, textAlign: 'center', marginTop: 6 }}>
                El historial se guarda en SQLite localmente
              </Text>
            </View>
          )}

          {chatMessages.map((msg) => (
            <View
              key={msg.id}
              style={[
                S.chatBubble,
                msg.role === 'user' ? S.chatBubbleUser : S.chatBubbleBot,
              ]}
            >
              <Text style={[S.chatBubbleLabel, { color: msg.role === 'user' ? C.cyan : C.green }]}>
                {msg.role === 'user' ? 'Tú' : chatModel}
              </Text>
              <Text style={S.chatBubbleText} selectable>{msg.text}</Text>
            </View>
          ))}

          {chatLoading && (
            <View style={[S.chatBubble, S.chatBubbleBot, { flexDirection: 'row', alignItems: 'center', gap: 8 }]}>
              <ActivityIndicator color={C.green} size="small" />
              <Text style={{ color: C.dim, fontSize: 13 }}>Pensando...</Text>
            </View>
          )}
        </ScrollView>

        {/* Input */}
        <View style={S.chatInputRow}>
          <TextInput
            style={S.chatInput}
            value={chatInput}
            onChangeText={setChatInput}
            placeholder="Escribe un mensaje..."
            placeholderTextColor={C.dim}
            multiline
            maxLength={2000}
            returnKeyType="send"
            blurOnSubmit={false}
          />
          <TouchableOpacity
            style={[S.chatSendBtn, (!chatInput.trim() || chatLoading) && { opacity: 0.4 }]}
            onPress={sendChat}
            disabled={!chatInput.trim() || chatLoading}
          >
            <Text style={S.chatSendIcon}>↑</Text>
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    );
  };

  // ══════════════════════════════════════════════
  //  PESTAÑA: SISTEMA
  // ══════════════════════════════════════════════
  const renderSystem = () => {
    const ram = status.ram || {};
    return (
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 14 }}>
        <View style={S.sysCard}>
          <Text style={S.sysLabel}>SISTEMA</Text>
          <InfoRow k="IP WiFi"   v={status.ip || '—'} />
          <InfoRow k="RAM libre" v={ram.available_mb ? `${ram.available_mb} MB` : '--'} />
          <InfoRow k="RAM total" v={ram.total_mb ? `${(ram.total_mb / 1024).toFixed(1)} GB` : '--'} />
          <InfoRow k="Dashboard" v=":8080 activo" vc={C.green} />
          <InfoRow k="Sync"      v={lastSync} />
        </View>

        <View style={S.sysCard}>
          <Text style={S.sysLabel}>MÓDULOS</Text>
          {(status.modules || []).map(m => {
            const isService = ['n8n', 'ollama', 'ssh'].includes(m.id);
            const color     = !m.installed ? C.dim : (isService && m.running) ? C.green : C.yellow;
            const label     = !m.installed ? 'no instalado' : isService ? (m.running ? 'activo' : 'listo') : `listo · v${m.version || '?'}`;
            return <InfoRow key={m.id} k={`${m.running ? '●' : '○'} ${m.name}`} v={label} kc={color} vc={color} />;
          })}
        </View>

        <View style={S.sysCard}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
            <Text style={S.sysLabel}>ACCIONES RECIENTES</Text>
            <TouchableOpacity onPress={fetchLogs}><Text style={{ color: C.cyan, fontSize: 13 }}>↻</Text></TouchableOpacity>
          </View>
          {logs.length === 0 ? (
            <Text style={{ color: C.dim, fontSize: 13 }}>Sin acciones registradas.</Text>
          ) : (
            logs.slice().reverse().map((l, i) => (
              <View key={i} style={{ flexDirection: 'row', marginBottom: 5, gap: 8 }}>
                <Text style={{ color: C.dim, fontSize: 11, width: 60 }}>{l.ts}</Text>
                <Text style={{ color: l.ok ? C.green : C.red, fontSize: 11, flex: 1 }}>
                  {l.module} · {l.action} {l.ok ? '✓' : '✗'} {l.msg ? `· ${l.msg}` : ''}
                </Text>
              </View>
            ))
          )}
        </View>

        <View style={S.sysCard}>
          <Text style={S.sysLabel}>COMANDOS RÁPIDOS</Text>
          {['bash ~/dashboard_start.sh', 'menu', 'bash ~/backup.sh', 'bash ~/restore.sh'].map((c, i) => (
            <CmdBox key={i} text={c} />
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
        { title: 'Sin conexión al dashboard', body: 'El servidor debe estar corriendo en Termux. Ejecuta:\n\nbash ~/dashboard_start.sh\n\nLa app se reconecta automáticamente.' },
        { title: 'n8n start no responde', body: 'n8n puede tardar hasta 35s. Ollama ~5-10s. SSH ~1s. El spinner desaparece cuando el proceso confirma estado activo.' },
        { title: 'Claude "no instalado"', body: 'Presiona [r] en el menú de Termux para refrescar el registry. Si persiste: menu → [2] Claude Code → [2] GitHub Releases.' },
        { title: 'Chat sin respuesta', body: 'El modelo debe estar activo (Ollama corriendo). El timeout del chat es 2 minutos. Modelos recomendados: qwen2.5:0.5b o qwen2.5:1.5b.' },
        { title: 'Ollama rendimiento lento', body: 'Bug #27290 activo en termux-packages. Sin workaround por ahora — esperar fix oficial.' },
        { title: 'Backup', body: 'Guarda ~/.android_server_registry + configs en /sdcard/termux-backup/. Toca el botón Backup en la sección SISTEMA de la pestaña Módulos.' },
      ].map((item, i) => (
        <View key={i} style={S.sysCard}>
          <Text style={{ color: C.cyan, fontSize: 13, fontWeight: '700', marginBottom: 6 }}>{item.title}</Text>
          <Text style={{ color: C.text2, fontSize: 12, lineHeight: 18 }}>{item.body}</Text>
        </View>
      ))}
      <View style={S.sysCard}>
        <Text style={S.sysLabel}>VERSIÓN</Text>
        <InfoRow k="App"           v="v1.6.0" />
        <InfoRow k="SDK Expo"      v="50.0.0" />
        <InfoRow k="React Native"  v="0.73.6" />
        <InfoRow k="Dashboard"     v="v2.0.0" />
      </View>
      <View style={{ height: 40 }} />
    </ScrollView>
  );

  // ══════════════════════════════════════════════
  //  RENDER PRINCIPAL
  // ══════════════════════════════════════════════
  const ram    = status.ram || {};
  const ramStr = ram.available_mb ? `${(ram.available_mb / 1024).toFixed(1)} GB` : '--';

  return (
    <View style={S.root}>
      <StatusBar style="light" />

      {/* ── HEADER ───────────────────────────── */}
      <View style={S.header}>
        <View style={S.headerTop}>
          <View style={S.headerDot}>
            <View style={[S.dotInner, { backgroundColor: !connErr ? C.green : C.red }]} />
            <Text style={S.headerBrand}>TERMUX · AI · STACK</Text>
          </View>
          <Text style={S.syncText}>sync {lastSync}</Text>
        </View>
        <View style={S.statsRow}>
          <StatChip icon="⚡" label={`RAM: ${ramStr}`} />
          <StatChip icon="📡" label={`IP: ${status.ip || '—'}`} />
          {ram.total_mb ? <StatChip icon="💾" label={`${(ram.total_mb / 1024).toFixed(0)} GB total`} /> : null}
        </View>
        {connErr && (
          <View style={S.offlineBanner}>
            <Text style={S.offlineBannerText}>⚠ Sin conexión — reintentando...</Text>
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
          <Text style={S.sectionLabel}>MÓDULOS</Text>
          {(status.modules || []).map(m => renderCard(m))}

          <Text style={[S.sectionLabel, { marginTop: 6 }]}>SISTEMA</Text>
          <View style={S.card}>
            <TouchableOpacity style={S.cardRow} onPress={doBackup} activeOpacity={0.7}>
              <ModuleIcon id="backup" size={44} />
              <View style={S.cardMid}>
                <Text style={S.cardName}>Backup / Restore</Text>
                <Text style={S.cardVer}>registry + configs → /sdcard</Text>
              </View>
              <TouchableOpacity style={[S.cardBtn, S.cardBtnSub]} onPress={doBackup}>
                <Text style={S.cardBtnText}>Backup</Text>
              </TouchableOpacity>
            </TouchableOpacity>
            <Divider />
            <TouchableOpacity
              onPress={() => Alert.alert('Restore', 'Ejecuta en Termux:\n\nbash ~/restore.sh\n\nO: menú → [0] → Restore')}
              style={{ paddingVertical: 8, paddingHorizontal: 14 }}
            >
              <Text style={{ color: C.cyan, fontSize: 13 }}>♻️  Ver instrucciones de restore →</Text>
            </TouchableOpacity>
          </View>
        </ScrollView>
      )}

      {footerTab === 'chat'   && renderChat()}
      {footerTab === 'system' && renderSystem()}
      {footerTab === 'help'   && renderHelp()}

      {/* ── FOOTER NAV ───────────────────────── */}
      <View style={S.footer}>
        {[
          { key: 'home',   icon: '⊞', label: 'Módulos' },
          { key: 'chat',   icon: '💬', label: 'Chat IA' },
          { key: 'system', icon: '◎', label: 'Sistema'  },
          { key: 'help',   icon: '?', label: 'Ayuda'    },
        ].map(tab => (
          <TouchableOpacity
            key={tab.key}
            style={S.footerTab}
            onPress={() => {
              setFooterTab(tab.key);
              if (tab.key === 'system') fetchLogs();
              if (tab.key === 'chat')   fetchChatHistory();
            }}
          >
            <Text style={[S.footerIcon, footerTab === tab.key && S.footerIconActive]}>
              {tab.icon}
            </Text>
            <Text style={[S.footerLabel, footerTab === tab.key && S.footerLabelActive]}>
              {tab.label}
            </Text>
            {footerTab === tab.key && <View style={S.footerIndicator} />}
          </TouchableOpacity>
        ))}
      </View>
    </View>
  );
}

// ─────────────────────────────────────────────
//  HELPERS COMPONENTES
// ─────────────────────────────────────────────
function StatChip({ icon, label }) {
  return (
    <View style={S.statChip}>
      <Text style={{ fontSize: 10, marginRight: 3 }}>{icon}</Text>
      <Text style={S.statText}>{label}</Text>
    </View>
  );
}

// ─────────────────────────────────────────────
//  ESTILOS
// ─────────────────────────────────────────────
const S = StyleSheet.create({
  root: { flex: 1, backgroundColor: C.bg },

  // Offline
  center:        { flex: 1, backgroundColor: C.bg, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 32 },
  offlineHex:    { fontSize: 56, color: C.cyan, marginBottom: 16 },
  offlineTitle:  { fontSize: 22, fontWeight: '700', color: C.white, marginBottom: 8 },
  offlineSub:    { fontSize: 14, color: C.dim, marginBottom: 16 },
  offlineCode:   { backgroundColor: C.surface, borderWidth: 1, borderColor: C.border, borderRadius: 10, paddingVertical: 12, paddingHorizontal: 20, marginBottom: 14 },
  offlineCmd:    { fontSize: 13, color: C.green, fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier' },
  offlineHint:   { fontSize: 12, color: C.dim, textAlign: 'center', marginBottom: 24 },
  retryBtn:      { backgroundColor: C.cyanDim, borderWidth: 1, borderColor: C.cyan + '66', borderRadius: 10, paddingVertical: 12, paddingHorizontal: 28 },
  retryText:     { fontSize: 14, fontWeight: '600', color: C.cyan },

  // Header
  header:           { paddingTop: Platform.OS === 'android' ? 40 : 52, paddingHorizontal: 14, paddingBottom: 10, backgroundColor: C.surface, borderBottomWidth: 1, borderBottomColor: C.border },
  headerTop:        { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 },
  headerDot:        { flexDirection: 'row', alignItems: 'center', gap: 8 },
  dotInner:         { width: 8, height: 8, borderRadius: 4 },
  headerBrand:      { fontSize: 13, fontWeight: '700', color: C.cyan, letterSpacing: 2 },
  syncText:         { fontSize: 11, color: C.dim },
  statsRow:         { flexDirection: 'row', gap: 6, flexWrap: 'wrap' },
  statChip:         { flexDirection: 'row', alignItems: 'center', backgroundColor: C.card, borderWidth: 1, borderColor: C.border, borderRadius: 20, paddingHorizontal: 10, paddingVertical: 4 },
  statText:         { fontSize: 11, color: C.text2 },
  offlineBanner:    { marginTop: 8, backgroundColor: C.yellowDim, borderRadius: 6, paddingVertical: 4, paddingHorizontal: 10 },
  offlineBannerText:{ fontSize: 11, color: C.yellow },

  // Section
  sectionLabel: { fontSize: 11, color: C.dim, fontWeight: '700', letterSpacing: 1, marginBottom: 8, marginLeft: 2 },

  // Cards
  card:        { backgroundColor: C.card, borderRadius: 14, borderWidth: 1, borderColor: C.border, marginBottom: 8, overflow: 'hidden' },
  cardExpanded:{ borderColor: C.cyan + '44' },
  cardRow:     { flexDirection: 'row', alignItems: 'center', padding: 12, gap: 10 },
  cardMid:     { flex: 1 },
  cardName:    { fontSize: 15, fontWeight: '700', color: C.white },
  cardVer:     { fontSize: 11, color: C.dim, marginTop: 1 },
  cardRight:   { flexDirection: 'row', alignItems: 'center', gap: 6 },
  cardBtn:         { paddingHorizontal: 12, paddingVertical: 7, borderRadius: 8, borderWidth: 1 },
  cardBtnSub:      { backgroundColor: C.cyanDim, borderColor: C.cyan + '55' },
  cardBtnInstall:  { backgroundColor: '#1f3a1f', borderColor: C.green + '55' },
  cardBtnText:     { fontSize: 12, fontWeight: '600', color: C.white },

  // Feedback
  feedOk:      { fontSize: 11, color: C.green,  paddingHorizontal: 14, paddingBottom: 6 },
  feedErr:     { fontSize: 11, color: C.red,    paddingHorizontal: 14, paddingBottom: 6 },
  feedPending: { fontSize: 11, color: C.yellow, paddingHorizontal: 14, paddingBottom: 6 },

  // Expandido
  expanded:      { paddingHorizontal: 14, paddingBottom: 12 },
  divider:       { height: 1, backgroundColor: C.border, marginVertical: 10 },
  expLabel:      { fontSize: 10, color: C.dim, fontWeight: '700', letterSpacing: 0.8, marginBottom: 8 },
  expHint:       { fontSize: 12, color: C.dim, lineHeight: 18 },
  expRowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },

  warnBox:  { backgroundColor: C.yellowDim, borderWidth: 1, borderColor: C.yellow + '44', borderRadius: 8, padding: 10 },
  warnText: { fontSize: 12, color: C.yellow, lineHeight: 18 },

  urlBox:  { backgroundColor: C.bg, borderRadius: 8, borderWidth: 1, borderColor: C.border, paddingVertical: 8, paddingHorizontal: 10, marginBottom: 6, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  urlText: { fontSize: 12, color: C.cyan, flex: 1, fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier' },
  urlCopy: { fontSize: 14, marginLeft: 8 },

  linkBtn:     { alignSelf: 'flex-start', marginTop: 4, marginBottom: 4 },
  linkBtnText: { color: C.cyan, fontSize: 12 },

  modelRow:  { flexDirection: 'row', alignItems: 'center', paddingVertical: 7, gap: 8 },
  modelDot:  { width: 6, height: 6, borderRadius: 3, backgroundColor: C.green },
  modelName: { fontSize: 13, color: C.white, fontWeight: '600' },
  modelSize: { fontSize: 11, color: C.dim },

  smallBtn:       { paddingHorizontal: 8, paddingVertical: 4, borderRadius: 6, borderWidth: 1, borderColor: C.border, backgroundColor: C.surface },
  smallBtnActive: { borderColor: C.cyan + '66', backgroundColor: C.cyanDim },
  smallBtnText:   { fontSize: 11, color: C.dim, fontWeight: '600' },

  ctxBtn:       { paddingHorizontal: 10, paddingVertical: 5, borderRadius: 8, borderWidth: 1, borderColor: C.border, backgroundColor: C.surface },
  ctxBtnActive: { borderColor: C.cyan + '66', backgroundColor: C.cyanDim },
  ctxBtnText:   { fontSize: 12, color: C.dim },

  presetRow:  { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, paddingHorizontal: 4, borderBottomWidth: 1, borderBottomColor: C.border + '55' },
  presetName: { fontSize: 13, color: C.white, fontWeight: '600' },
  presetMeta: { fontSize: 11, color: C.dim, marginTop: 2 },

  cmdBox:  { backgroundColor: C.bg, borderRadius: 7, borderWidth: 1, borderColor: C.border, paddingVertical: 7, paddingHorizontal: 10, marginBottom: 5 },
  cmdText: { fontSize: 11, color: C.green, fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier' },

  inputLabel: { fontSize: 11, color: C.dim, fontWeight: '600', marginBottom: 4, letterSpacing: 0.5 },
  input:      { backgroundColor: C.bg, borderWidth: 1, borderColor: C.border, borderRadius: 8, paddingVertical: 9, paddingHorizontal: 12, color: C.white, fontSize: 13, marginBottom: 10 },

  actionBtn:     { paddingVertical: 10, paddingHorizontal: 16, borderRadius: 8, borderWidth: 1, alignItems: 'center', justifyContent: 'center', marginTop: 4, minHeight: 40 },
  actionBtnText: { fontSize: 13, fontWeight: '600' },

  // Sistema
  sysCard:  { backgroundColor: C.card, borderRadius: 12, borderWidth: 1, borderColor: C.border, padding: 14, marginBottom: 10 },
  sysLabel: { fontSize: 10, color: C.dim, fontWeight: '700', letterSpacing: 0.8, marginBottom: 10 },

  // Chat
  chatHeader:      { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 14, paddingVertical: 10, backgroundColor: C.surface, borderBottomWidth: 1, borderBottomColor: C.border },
  chatHeaderTitle: { fontSize: 14, fontWeight: '700', color: C.white },
  chatHeaderSub:   { fontSize: 11, color: C.dim, marginTop: 2 },
  chatClearBtn:    { paddingHorizontal: 10, paddingVertical: 6, borderRadius: 8, backgroundColor: C.card, borderWidth: 1, borderColor: C.border },

  chatBubble:     { borderRadius: 12, padding: 10, marginBottom: 8, maxWidth: '92%' },
  chatBubbleUser: { backgroundColor: C.chatUser, alignSelf: 'flex-end', borderBottomRightRadius: 4 },
  chatBubbleBot:  { backgroundColor: C.chatBot,  alignSelf: 'flex-start', borderBottomLeftRadius: 4, borderWidth: 1, borderColor: C.border },
  chatBubbleLabel:{ fontSize: 10, fontWeight: '700', marginBottom: 4, letterSpacing: 0.5 },
  chatBubbleText: { fontSize: 13, color: C.white, lineHeight: 20 },

  chatInputRow: { flexDirection: 'row', padding: 10, gap: 8, backgroundColor: C.surface, borderTopWidth: 1, borderTopColor: C.border },
  chatInput:    { flex: 1, backgroundColor: C.card, borderWidth: 1, borderColor: C.border, borderRadius: 12, paddingHorizontal: 14, paddingVertical: 10, color: C.white, fontSize: 14, maxHeight: 100 },
  chatSendBtn:  { width: 44, height: 44, borderRadius: 22, backgroundColor: C.cyan, alignItems: 'center', justifyContent: 'center', alignSelf: 'flex-end' },
  chatSendIcon: { fontSize: 18, color: C.bg, fontWeight: '700' },

  // Footer
  footer:           { flexDirection: 'row', backgroundColor: C.bg, borderTopWidth: 1, borderTopColor: C.border, paddingBottom: Platform.OS === 'android' ? 12 : 20, paddingTop: 8 },
  footerTab:        { flex: 1, alignItems: 'center', position: 'relative', paddingVertical: 2 },
  footerIcon:       { fontSize: 18, color: C.dim, marginBottom: 3 },
  footerIconActive: { color: C.cyan },
  footerLabel:      { fontSize: 10, color: C.dim, fontWeight: '500' },
  footerLabelActive:{ color: C.cyan, fontWeight: '700' },
  footerIndicator:  { position: 'absolute', top: 0, width: 24, height: 2, backgroundColor: C.cyan, borderRadius: 2 },
});
