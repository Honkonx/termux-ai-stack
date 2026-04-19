import { useState, useEffect, useCallback, useRef } from 'react';
import {
  StyleSheet,
  View,
  Text,
  Switch,
  TouchableOpacity,
  ScrollView,
  RefreshControl,
  Platform,
  Linking,
  ActivityIndicator,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import * as FileSystem from 'expo-file-system';
import * as IntentLauncher from 'expo-intent-launcher';

const REGISTRY = 'file:///sdcard/termux_stack/registry';
const CMD_FILE = 'file:///sdcard/termux_stack/cmd';
const POLL_MS  = 3000;
const PKG      = 'com.honkonx.termuxaistack';

const MODULES = [
  { id: 'n8n',       label: 'n8n',       sub: 'Automatización · proot Debian · :5678' },
  { id: 'ollama',    label: 'Ollama',     sub: 'Modelos LLM · Termux nativo'           },
  { id: 'dashboard', label: 'Dashboard',  sub: 'Web UI · Python HTTP · :8080'          },
];

function parseRegistry(text) {
  const out = {};
  for (const line of text.split('\n')) {
    const eq = line.indexOf('=');
    if (eq < 0) continue;
    const key = line.slice(0, eq).trim();
    const val = line.slice(eq + 1).trim();
    out[key] = val;
  }
  return out;
}

async function readRegistry() {
  const info = await FileSystem.getInfoAsync(REGISTRY);
  if (!info.exists) return null;
  return FileSystem.readAsStringAsync(REGISTRY);
}

async function sendCommand(cmd) {
  await FileSystem.writeAsStringAsync(CMD_FILE, cmd, { encoding: FileSystem.EncodingType.UTF8 });
}

async function openAllFilesSettings() {
  try {
    await IntentLauncher.startActivityAsync(
      'android.settings.MANAGE_APP_ALL_FILES_ACCESS_PERMISSION',
      { data: `package:${PKG}` }
    );
  } catch {
    Linking.openSettings();
  }
}

// ── Sub-components ─────────────────────────────────────────────

function ModuleCard({ module, running, installing, onToggle }) {
  const isOn = running === true;
  return (
    <View style={styles.card}>
      <View style={styles.cardLeft}>
        <View style={[styles.dot, isOn ? styles.dotOn : styles.dotOff]} />
        <View>
          <Text style={styles.cardTitle}>{module.label}</Text>
          <Text style={styles.cardSub}>{module.sub}</Text>
          <Text style={[styles.cardStatus, isOn ? styles.statusOn : styles.statusOff]}>
            {running === null ? 'desconocido' : isOn ? 'activo' : 'detenido'}
          </Text>
        </View>
      </View>
      {installing
        ? <ActivityIndicator size="small" color="#79c0ff" />
        : (
          <Switch
            value={isOn}
            onValueChange={onToggle}
            trackColor={{ false: '#30363d', true: '#1f6feb' }}
            thumbColor={isOn ? '#79c0ff' : '#8b949e'}
          />
        )
      }
    </View>
  );
}

function PermissionScreen({ onGrant }) {
  return (
    <View style={styles.center}>
      <Text style={styles.permIcon}>⬡</Text>
      <Text style={styles.permTitle}>Acceso al almacenamiento</Text>
      <Text style={styles.permBody}>
        La app necesita acceso a todos los archivos para leer el estado del stack
        desde{'\n'}
        <Text style={styles.mono}>/sdcard/termux_stack/</Text>
      </Text>
      <TouchableOpacity style={styles.btn} onPress={onGrant}>
        <Text style={styles.btnText}>Conceder acceso</Text>
      </TouchableOpacity>
      <Text style={styles.permHint}>
        Ajustes → Aplicaciones → termux-ai-stack → Archivos y medios → Todos los archivos
      </Text>
    </View>
  );
}

// ── Main ────────────────────────────────────────────────────────

export default function App() {
  const [status, setStatus]       = useState({});   // moduleId → true/false/null
  const [pending, setPending]     = useState({});   // moduleId → bool (waiting for change)
  const [permOk, setPermOk]       = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [lastSync, setLastSync]   = useState(null);
  const intervalRef = useRef(null);

  const syncStatus = useCallback(async () => {
    try {
      const text = await readRegistry();
      if (text === null) {
        setStatus({});
        return;
      }
      const reg = parseRegistry(text);
      setStatus(prev => {
        const next = {};
        for (const m of MODULES) {
          const raw = reg[`${m.id}.running`];
          next[m.id] = raw === 'true' ? true : raw === 'false' ? false : null;
        }
        // Clear pending if state changed
        const newPending = { ...pending };
        let changed = false;
        for (const m of MODULES) {
          if (newPending[m.id] !== undefined && next[m.id] !== prev[m.id]) {
            delete newPending[m.id];
            changed = true;
          }
        }
        if (changed) setPending(newPending);
        return next;
      });
      setPermOk(true);
      setLastSync(new Date());
    } catch (e) {
      if (e.message?.includes('Permission') || e.message?.includes('EPERM')) {
        setPermOk(false);
      }
    }
  }, [pending]);

  useEffect(() => {
    syncStatus();
    intervalRef.current = setInterval(syncStatus, POLL_MS);
    return () => clearInterval(intervalRef.current);
  }, [syncStatus]);

  const handleToggle = useCallback(async (moduleId, currentlyOn) => {
    const cmd = currentlyOn ? `${moduleId}.stop` : `${moduleId}.start`;
    setPending(p => ({ ...p, [moduleId]: true }));
    try {
      await sendCommand(cmd);
    } catch {
      setPending(p => { const n = { ...p }; delete n[moduleId]; return n; });
    }
  }, []);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await syncStatus();
    setRefreshing(false);
  }, [syncStatus]);

  if (!permOk) {
    return (
      <View style={styles.container}>
        <StatusBar style="light" backgroundColor="#0d1117" />
        <PermissionScreen onGrant={openAllFilesSettings} />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <StatusBar style="light" backgroundColor="#0d1117" />

      <View style={styles.header}>
        <Text style={styles.headerTitle}>termux-ai-stack</Text>
        {lastSync && (
          <Text style={styles.headerSync}>
            {lastSync.toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}
          </Text>
        )}
      </View>

      <ScrollView
        contentContainerStyle={styles.scroll}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#79c0ff" />}
      >
        {MODULES.map(m => (
          <ModuleCard
            key={m.id}
            module={m}
            running={status[m.id] ?? null}
            installing={!!pending[m.id]}
            onToggle={() => handleToggle(m.id, status[m.id])}
          />
        ))}

        <View style={styles.footer}>
          <Text style={styles.footerText}>Arriba para refrescar · polling cada 3 s</Text>
          <Text style={styles.footerText}>IPC: /sdcard/termux_stack/</Text>
        </View>
      </ScrollView>
    </View>
  );
}

// ── Styles ──────────────────────────────────────────────────────

const C = {
  bg:       '#0d1117',
  surface:  '#161b22',
  border:   '#30363d',
  text:     '#e6edf3',
  muted:    '#7d8590',
  blue:     '#79c0ff',
  green:    '#3fb950',
  red:      '#f85149',
};

const styles = StyleSheet.create({
  container:  { flex: 1, backgroundColor: C.bg },
  header:     { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
                paddingHorizontal: 20, paddingTop: 52, paddingBottom: 16,
                borderBottomWidth: 1, borderBottomColor: C.border },
  headerTitle:{ color: C.blue, fontFamily: 'monospace', fontSize: 15, fontWeight: 'bold', letterSpacing: 1 },
  headerSync: { color: C.muted, fontFamily: 'monospace', fontSize: 11 },
  scroll:     { padding: 16, gap: 12 },
  card:       { backgroundColor: C.surface, borderRadius: 10, borderWidth: 1, borderColor: C.border,
                flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
                paddingVertical: 16, paddingHorizontal: 18 },
  cardLeft:   { flexDirection: 'row', alignItems: 'center', gap: 14, flex: 1 },
  dot:        { width: 10, height: 10, borderRadius: 5 },
  dotOn:      { backgroundColor: C.green },
  dotOff:     { backgroundColor: C.red },
  cardTitle:  { color: C.text, fontFamily: 'monospace', fontSize: 15, fontWeight: 'bold' },
  cardSub:    { color: C.muted, fontFamily: 'monospace', fontSize: 11, marginTop: 2 },
  cardStatus: { fontFamily: 'monospace', fontSize: 11, marginTop: 4 },
  statusOn:   { color: C.green },
  statusOff:  { color: C.muted },
  footer:     { paddingTop: 24, paddingBottom: 40, alignItems: 'center', gap: 4 },
  footerText: { color: C.muted, fontFamily: 'monospace', fontSize: 10 },
  // Permission screen
  center:     { flex: 1, justifyContent: 'center', alignItems: 'center', padding: 32, gap: 16 },
  permIcon:   { fontSize: 48, color: C.blue },
  permTitle:  { color: C.text, fontFamily: 'monospace', fontSize: 17, fontWeight: 'bold' },
  permBody:   { color: C.muted, fontFamily: 'monospace', fontSize: 13, textAlign: 'center', lineHeight: 22 },
  mono:       { color: C.green, fontFamily: 'monospace' },
  btn:        { backgroundColor: '#1f6feb', borderRadius: 8, paddingVertical: 12, paddingHorizontal: 32, marginTop: 8 },
  btnText:    { color: C.text, fontFamily: 'monospace', fontSize: 14, fontWeight: 'bold' },
  permHint:   { color: C.muted, fontFamily: 'monospace', fontSize: 10, textAlign: 'center', lineHeight: 18, marginTop: 8 },
});
