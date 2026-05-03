// App/src/screens/modules/ssh/SshScreen.js
// v1.0.0 — S19
// SURFACE:   tema activo del proyecto — acento verde terminal #22c55e
// JERARQUÍA: header título+estado · sección UPPERCASE · InfoRow · cmd monospace copiable
// ACENTO:    #22c55e — SSH es herramienta de terminal, verde es semántico
// BORDES:    rgba(255,255,255,0.07) — nunca hex sólido
// DENSIDAD:  compacta — pantalla de referencia técnica, info para copiar rápido

import { useState, useEffect, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, ScrollView,
  StyleSheet, Platform, Alert, Clipboard,
} from 'react-native';
import { useTheme }  from '../../../theme/ThemeContext';
import { useStatus } from '../../../hooks/useStatus';
import { useAction } from '../../../hooks/useAction';

const SSH_ACCENT = '#22c55e';
const BASE_URL   = 'http://127.0.0.1:8080';

// ── CodeBox copiable ──────────────────────────────────────────
function CopyBox({ value, label, t }) {
  const [copied, setCopied] = useState(false);
  const handleCopy = () => {
    Clipboard.setString(value);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  };
  const s = copyBoxStyles(t);
  return (
    <View style={s.wrap}>
      {label && <Text style={s.label}>{label}</Text>}
      <View style={s.row}>
        <Text style={s.code} numberOfLines={1} selectable>{value}</Text>
        <TouchableOpacity style={s.btn} onPress={handleCopy} activeOpacity={0.7}>
          <Text style={[s.btnText, copied && s.btnTextCopied]}>
            {copied ? '✓' : '⧉'}
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}
function copyBoxStyles(t) {
  return StyleSheet.create({
    wrap:  { marginBottom: 10 },
    label: { fontSize: 11, color: t.textMuted || '#52525b', letterSpacing: 0.8,
             textTransform: 'uppercase', marginBottom: 5 },
    row:   { flexDirection: 'row', alignItems: 'center',
             backgroundColor: t.card || '#111',
             borderRadius: 8, borderWidth: 1,
             borderColor: 'rgba(255,255,255,0.07)', overflow: 'hidden' },
    code:  { flex: 1, paddingHorizontal: 12, paddingVertical: 11,
             fontSize: 12, color: SSH_ACCENT,
             fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New' },
    btn:   { paddingHorizontal: 14, paddingVertical: 11,
             borderLeftWidth: 1, borderLeftColor: 'rgba(255,255,255,0.07)' },
    btnText:       { fontSize: 16, color: t.textMuted || '#52525b' },
    btnTextCopied: { color: SSH_ACCENT },
  });
}

// ── SectionLabel ──────────────────────────────────────────────
function SLabel({ text, t }) {
  return (
    <Text style={{
      fontSize: 11, fontWeight: '600', letterSpacing: 1.2,
      textTransform: 'uppercase', color: t.textMuted || '#52525b',
      marginBottom: 8, marginTop: 4,
    }}>
      {text}
    </Text>
  );
}

// ── InfoRow ───────────────────────────────────────────────────
function InfoRow({ label, value, accent, t }) {
  return (
    <View style={{
      flexDirection: 'row', justifyContent: 'space-between',
      alignItems: 'center', paddingVertical: 11, paddingHorizontal: 14,
      borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.05)',
    }}>
      <Text style={{ fontSize: 13, color: t.textMuted || '#71717a' }}>{label}</Text>
      <Text style={{ fontSize: 13, fontWeight: '600',
                     color: accent || t.textPrimary || t.text || '#f4f4f5',
                     fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New' }}>
        {value}
      </Text>
    </View>
  );
}

// ── SshScreen ─────────────────────────────────────────────────
export function SshScreen({ goBack }) {
  const { theme: t }  = useTheme();
  const { status }    = useStatus();
  const { trigger, loading: actionLoading } = useAction();

  const [sshInfo, setSshInfo]     = useState(null);
  const [infoLoading, setLoading] = useState(true);
  const [newKey, setNewKey]       = useState('');

  // Módulo SSH del status
  const sshModule  = status?.modules?.find(m => m.id === 'ssh');
  const isRunning  = sshModule?.running === true;
  const version    = sshModule?.version || 'OpenSSH';

  // Cargar info SSH desde dashboard
  const loadInfo = useCallback(() => {
    setLoading(true);
    const ctrl = new AbortController();
    setTimeout(() => ctrl.abort(), 5000);
    fetch(`${BASE_URL}/api/ssh/info`, { signal: ctrl.signal })
      .then(r => r.json())
      .then(d => { setSshInfo(d); setLoading(false); })
      .catch(() => setLoading(false));
  }, []);

  useEffect(() => { loadInfo(); }, []);

  // Switch SSH
  const handleToggle = useCallback(async () => {
    const action = isRunning ? 'stop' : 'start';
    await trigger({ action, module: 'ssh' });
  }, [isRunning, trigger]);

  const s = styles(t);

  const ip     = sshInfo?.ip   || status?.ip || '–';
  const port   = sshInfo?.port || '8022';
  const user   = sshInfo?.user || '–';
  const keys   = sshInfo?.keys ?? '–';
  const cmd    = sshInfo?.cmd    || `ssh -p ${port} ${user}@${ip}`;
  const scpCmd = sshInfo?.scp_cmd || `scp -P ${port} archivo.txt ${user}@${ip}:~/`;

  return (
    <View style={s.root}>
      {/* ── Header ─── */}
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={goBack} activeOpacity={0.7}>
          <Text style={s.backIcon}>‹</Text>
        </TouchableOpacity>
        <View style={s.headerCenter}>
          <Text style={s.headerTitle}>SSH</Text>
          <Text style={s.headerSub}>{version}</Text>
        </View>
        {/* Switch */}
        <TouchableOpacity
          style={[s.switchWrap, isRunning && s.switchOn]}
          onPress={handleToggle}
          disabled={actionLoading}
          activeOpacity={0.8}
        >
          <View style={[s.switchThumb, isRunning && s.switchThumbOn]} />
        </TouchableOpacity>
      </View>

      {/* ── Status pill ─── */}
      <View style={s.pillRow}>
        <View style={[s.pill, isRunning ? s.pillActive : s.pillReady]}>
          <Text style={[s.pillText, isRunning ? s.pillTextActive : s.pillTextReady]}>
            {isRunning ? '● activo' : '○ detenido'}
          </Text>
        </View>
        <Text style={s.portLabel}>:8022</Text>
      </View>

      <ScrollView style={s.scroll} contentContainerStyle={s.scrollContent}>

        {/* ── Conexión ─── */}
        <View style={s.card}>
          <SLabel text="Conexión" t={t} />
          <InfoRow label="IP" value={ip} accent={SSH_ACCENT} t={t} />
          <InfoRow label="Puerto" value={port} t={t} />
          <InfoRow label="Usuario" value={user} accent={SSH_ACCENT} t={t} />
          <InfoRow label="Llaves autorizadas" value={String(keys)} t={t} />
        </View>

        {/* ── Comandos copiables ─── */}
        <View style={s.card}>
          <SLabel text="Comandos" t={t} />
          <CopyBox label="Conectar" value={cmd} t={t} />
          <CopyBox label="Copiar archivo (SCP)" value={scpCmd} t={t} />
        </View>

        {/* ── Instrucciones rápidas ─── */}
        <View style={s.card}>
          <SLabel text="Desde PC / Mac" t={t} />
          <View style={s.instructBox}>
            <Text style={s.instructStep}>
              <Text style={s.instructNum}>1  </Text>
              Asegúrate que PC y teléfono estén en la misma WiFi
            </Text>
            <Text style={s.instructStep}>
              <Text style={s.instructNum}>2  </Text>
              Copia el comando de arriba y pégalo en tu terminal
            </Text>
            <Text style={s.instructStep}>
              <Text style={s.instructNum}>3  </Text>
              Primera vez: acepta la huella del host (yes)
            </Text>
            <Text style={s.instructStep}>
              <Text style={s.instructNum}>4  </Text>
              Ingresa la contraseña de Termux si se pide
            </Text>
          </View>
        </View>

        {/* ── Acciones ─── */}
        <View style={s.card}>
          <SLabel text="Acciones" t={t} />
          <TouchableOpacity
            style={s.actionBtn}
            onPress={() => Alert.alert(
              'Agregar llave SSH',
              'Para agregar una llave pública, ejecuta en Termux:\n\ncat ~/.ssh/id_ed25519.pub >> ~/.ssh/authorized_keys\n\nO pega tu llave pública en:\n~/.ssh/authorized_keys',
              [{ text: 'OK' }]
            )}
            activeOpacity={0.8}
          >
            <Text style={s.actionIcon}>⚿</Text>
            <Text style={s.actionText}>Gestionar llaves</Text>
            <Text style={s.actionChevron}>›</Text>
          </TouchableOpacity>
          <TouchableOpacity
            style={s.actionBtn}
            onPress={() => Alert.alert(
              'Cambiar contraseña',
              'Ejecuta en Termux:\n\npasswd\n\nY sigue las instrucciones.',
              [{ text: 'OK' }]
            )}
            activeOpacity={0.8}
          >
            <Text style={s.actionIcon}>✎</Text>
            <Text style={s.actionText}>Cambiar contraseña</Text>
            <Text style={s.actionChevron}>›</Text>
          </TouchableOpacity>
        </View>

      </ScrollView>
    </View>
  );
}

function styles(t) {
  return StyleSheet.create({
    root:   { flex: 1, backgroundColor: t.bg || '#0a0a0a' },
    header: {
      flexDirection: 'row', alignItems: 'center',
      paddingHorizontal: 12, paddingVertical: 12,
      backgroundColor: t.surface || '#111',
      borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.06)',
    },
    backBtn: { width: 36, height: 36, alignItems: 'center', justifyContent: 'center' },
    backIcon:{ fontSize: 26, color: t.textPrimary || t.text || '#f4f4f5', lineHeight: 30 },
    headerCenter: { flex: 1, marginLeft: 4 },
    headerTitle:  { fontSize: 17, fontWeight: '700', letterSpacing: 0.2,
                    color: t.textPrimary || t.text || '#f4f4f5' },
    headerSub:    { fontSize: 11, color: t.textMuted || '#52525b', marginTop: 1 },
    // Switch manual (sin Switch nativo — consistente con el resto de la app)
    switchWrap: {
      width: 44, height: 26, borderRadius: 13,
      backgroundColor: 'rgba(255,255,255,0.1)',
      borderWidth: 1, borderColor: 'rgba(255,255,255,0.12)',
      justifyContent: 'center', paddingHorizontal: 3,
    },
    switchOn:  { backgroundColor: SSH_ACCENT + '33', borderColor: SSH_ACCENT + '66' },
    switchThumb: {
      width: 20, height: 20, borderRadius: 10,
      backgroundColor: t.textMuted || '#52525b',
      alignSelf: 'flex-start',
    },
    switchThumbOn: { backgroundColor: SSH_ACCENT, alignSelf: 'flex-end' },
    pillRow:   { flexDirection: 'row', alignItems: 'center', gap: 10,
                 paddingHorizontal: 16, paddingVertical: 10,
                 borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.04)' },
    pill:      { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 999,
                 borderWidth: 1 },
    pillActive:     { backgroundColor: SSH_ACCENT + '18', borderColor: SSH_ACCENT + '55' },
    pillReady:      { backgroundColor: 'rgba(255,255,255,0.05)', borderColor: 'rgba(255,255,255,0.1)' },
    pillText:       { fontSize: 12, fontWeight: '600' },
    pillTextActive: { color: SSH_ACCENT },
    pillTextReady:  { color: t.textMuted || '#71717a' },
    portLabel: { fontSize: 12, color: t.textMuted || '#52525b',
                 fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New' },
    scroll:        { flex: 1 },
    scrollContent: { padding: 16, gap: 12 },
    card:  {
      backgroundColor: t.surface || '#111',
      borderRadius: 12, borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.07)',
      padding: 14, marginBottom: 4,
    },
    instructBox:  { gap: 6, marginTop: 2 },
    instructStep: { fontSize: 13, color: t.textSecond || '#a1a1aa', lineHeight: 19 },
    instructNum:  { color: SSH_ACCENT, fontWeight: '700' },
    actionBtn: {
      flexDirection: 'row', alignItems: 'center', gap: 10,
      paddingVertical: 12, borderBottomWidth: 1,
      borderBottomColor: 'rgba(255,255,255,0.05)',
    },
    actionIcon:    { fontSize: 16, color: SSH_ACCENT, width: 20, textAlign: 'center' },
    actionText:    { flex: 1, fontSize: 14, color: t.textPrimary || t.text || '#f4f4f5' },
    actionChevron: { fontSize: 18, color: t.textMuted || '#52525b' },
  });
}
