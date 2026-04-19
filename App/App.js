import { useState, useEffect, useCallback, useRef } from 'react';
import {
  StyleSheet,
  View,
  Text,
  TouchableOpacity,
  FlatList,
  ActivityIndicator,
  SafeAreaView,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';

const API = 'http://localhost:8080';
const POLL_MS = 5000;

// Módulos con acciones start/stop habilitadas
const CONTROLLABLE = new Set(['n8n', 'ollama', 'ssh']);

// ── API calls ───────────────────────────────────────────────────

async function fetchStatus() {
  const res = await fetch(`${API}/api/status`, {
    method: 'GET',
    headers: { Accept: 'application/json' },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

async function postAction(module, action) {
  const res = await fetch(`${API}/api/action`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, module }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

// ── Helpers ─────────────────────────────────────────────────────

function badge(installed, running) {
  if (running)    return { label: 'activo',        color: C.green  };
  if (installed)  return { label: 'listo',         color: C.yellow };
  return            { label: 'no instalado',  color: C.muted  };
}

function fmtRam(ram) {
  if (!ram || ram.error) return '— MB libre';
  return `${ram.available_mb ?? ram.free_mb} MB libre`;
}

// ── Sub-components ──────────────────────────────────────────────

function Banner({ ip, ram, lastSync }) {
  return (
    <View style={styles.banner}>
      <View style={styles.bannerRow}>
        <Text style={styles.bannerLabel}>IP</Text>
        <Text style={styles.bannerValue}>{ip || '—'}</Text>
        <Text style={styles.bannerSep}>·</Text>
        <Text style={styles.bannerLabel}>RAM</Text>
        <Text style={styles.bannerValue}>{fmtRam(ram)}</Text>
      </View>
      {lastSync && (
        <Text style={styles.syncText}>
          sync {lastSync.toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
        </Text>
      )}
    </View>
  );
}

function ModuleRow({ item, onAction, pending }) {
  const b = badge(item.installed, item.running);
  const canControl = CONTROLLABLE.has(item.id);
  const isBusy = pending === item.id;

  return (
    <View style={styles.row}>
      <View style={styles.rowLeft}>
        <Text style={styles.rowIcon}>{item.icon}</Text>
        <View style={styles.rowInfo}>
          <View style={styles.rowNameLine}>
            <Text style={styles.rowName}>{item.name}</Text>
            <View style={[styles.badge, { borderColor: b.color }]}>
              <Text style={[styles.badgeText, { color: b.color }]}>{b.label}</Text>
            </View>
          </View>
          {item.version ? (
            <Text style={styles.rowSub}>v{item.version}{item.detail ? `  ${item.detail}` : ''}</Text>
          ) : item.detail ? (
            <Text style={styles.rowSub}>{item.detail}</Text>
          ) : null}
        </View>
      </View>

      {canControl && (
        isBusy ? (
          <ActivityIndicator size="small" color={C.blue} style={styles.rowAction} />
        ) : (
          <TouchableOpacity
            style={[styles.btn, item.running ? styles.btnStop : styles.btnStart]}
            onPress={() => onAction(item.id, item.running ? 'stop' : 'start')}
            activeOpacity={0.7}
          >
            <Text style={styles.btnText}>{item.running ? 'stop' : 'start'}</Text>
          </TouchableOpacity>
        )
      )}
    </View>
  );
}

function ErrorScreen() {
  return (
    <View style={styles.center}>
      <Text style={styles.errIcon}>⬡</Text>
      <Text style={styles.errTitle}>Dashboard no responde</Text>
      <Text style={styles.errBody}>Abre Termux y ejecuta:</Text>
      <View style={styles.codeBox}>
        <Text style={styles.code}>bash ~/dashboard_start.sh</Text>
      </View>
      <Text style={styles.errHint}>Luego regresa a esta app — se reconecta automáticamente.</Text>
    </View>
  );
}

// ── Main ────────────────────────────────────────────────────────

export default function App() {
  const [data, setData]       = useState(null);   // respuesta completa de /api/status
  const [error, setError]     = useState(false);
  const [pending, setPending] = useState(null);   // id del módulo con acción en vuelo
  const [lastSync, setLastSync] = useState(null);
  const timerRef = useRef(null);

  const poll = useCallback(async () => {
    try {
      const res = await fetchStatus();
      setData(res);
      setError(false);
      setLastSync(new Date());
    } catch {
      setError(true);
    }
  }, []);

  useEffect(() => {
    poll();
    timerRef.current = setInterval(poll, POLL_MS);
    return () => clearInterval(timerRef.current);
  }, [poll]);

  const handleAction = useCallback(async (moduleId, action) => {
    setPending(moduleId);
    try {
      await postAction(moduleId, action);
      // Esperar 2s para que el proceso arranque/pare antes de re-polling
      await new Promise(r => setTimeout(r, 2000));
      await poll();
    } catch {
      // Silenciar — el siguiente poll refrescará el estado real
    } finally {
      setPending(null);
    }
  }, [poll]);

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="light" backgroundColor={C.bg} />

      <View style={styles.header}>
        <Text style={styles.headerTitle}>termux-ai-stack</Text>
        {!error && data && <Banner ip={data.ip} ram={data.ram} lastSync={lastSync} />}
      </View>

      {error ? (
        <ErrorScreen />
      ) : !data ? (
        <View style={styles.center}>
          <ActivityIndicator size="large" color={C.blue} />
          <Text style={styles.loadText}>conectando...</Text>
        </View>
      ) : (
        <FlatList
          data={data.modules}
          keyExtractor={item => item.id}
          renderItem={({ item }) => (
            <ModuleRow item={item} onAction={handleAction} pending={pending} />
          )}
          contentContainerStyle={styles.list}
          ItemSeparatorComponent={() => <View style={styles.sep} />}
        />
      )}
    </SafeAreaView>
  );
}

// ── Styles ──────────────────────────────────────────────────────

const C = {
  bg:      '#0d1117',
  surface: '#161b22',
  border:  '#30363d',
  text:    '#e6edf3',
  muted:   '#7d8590',
  blue:    '#79c0ff',
  green:   '#3fb950',
  yellow:  '#e3b341',
  red:     '#f85149',
};

const styles = StyleSheet.create({
  root:         { flex: 1, backgroundColor: C.bg },
  header:       { paddingHorizontal: 16, paddingTop: 16, paddingBottom: 12,
                  borderBottomWidth: 1, borderBottomColor: C.border },
  headerTitle:  { color: C.blue, fontFamily: 'monospace', fontSize: 16,
                  fontWeight: 'bold', letterSpacing: 1, marginBottom: 8 },
  banner:       { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  bannerRow:    { flexDirection: 'row', alignItems: 'center', gap: 6 },
  bannerLabel:  { color: C.muted, fontFamily: 'monospace', fontSize: 11 },
  bannerValue:  { color: C.text,  fontFamily: 'monospace', fontSize: 11 },
  bannerSep:    { color: C.border,fontFamily: 'monospace', fontSize: 11 },
  syncText:     { color: C.muted, fontFamily: 'monospace', fontSize: 10 },
  list:         { padding: 12 },
  sep:          { height: 1, backgroundColor: C.border, marginHorizontal: 4 },
  row:          { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
                  paddingVertical: 14, paddingHorizontal: 8 },
  rowLeft:      { flexDirection: 'row', alignItems: 'center', flex: 1, gap: 12 },
  rowIcon:      { fontSize: 20, width: 28, textAlign: 'center' },
  rowInfo:      { flex: 1 },
  rowNameLine:  { flexDirection: 'row', alignItems: 'center', gap: 8 },
  rowName:      { color: C.text, fontFamily: 'monospace', fontSize: 14, fontWeight: 'bold' },
  rowSub:       { color: C.muted, fontFamily: 'monospace', fontSize: 11, marginTop: 2 },
  badge:        { borderWidth: 1, borderRadius: 4, paddingHorizontal: 6, paddingVertical: 1 },
  badgeText:    { fontFamily: 'monospace', fontSize: 10 },
  rowAction:    { marginLeft: 8 },
  btn:          { borderRadius: 6, paddingVertical: 6, paddingHorizontal: 14, marginLeft: 8 },
  btnStart:     { backgroundColor: '#1f6feb' },
  btnStop:      { backgroundColor: '#21262d', borderWidth: 1, borderColor: C.border },
  btnText:      { color: C.text, fontFamily: 'monospace', fontSize: 12, fontWeight: 'bold' },
  center:       { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 32, gap: 14 },
  loadText:     { color: C.muted, fontFamily: 'monospace', fontSize: 12, letterSpacing: 2 },
  errIcon:      { fontSize: 44, color: C.blue },
  errTitle:     { color: C.text, fontFamily: 'monospace', fontSize: 16, fontWeight: 'bold' },
  errBody:      { color: C.muted, fontFamily: 'monospace', fontSize: 13 },
  codeBox:      { backgroundColor: C.surface, borderRadius: 8, borderWidth: 1,
                  borderColor: C.border, paddingVertical: 10, paddingHorizontal: 18 },
  code:         { color: C.green, fontFamily: 'monospace', fontSize: 13 },
  errHint:      { color: C.muted, fontFamily: 'monospace', fontSize: 11,
                  textAlign: 'center', lineHeight: 18 },
});
