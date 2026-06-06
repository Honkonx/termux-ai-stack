import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  Switch, ActivityIndicator, Alert, RefreshControl, Platform, Clipboard,
} from 'react-native';
import { useTheme } from '../../../theme/ThemeContext';
import { useStatus } from '../../../hooks/useStatus';
import { getOpenCodeInfo } from '../../../services/dashboard';

const OC_ACCENT = '#60a5fa';
const OC_DIM    = '#1a2744';

const WS_PORT = 8081;

async function apiFetch(ip, path, opts = {}, ms = 8000) {
  const ctrl = new AbortController();
  const tid = setTimeout(() => ctrl.abort(), ms);
  try {
    const res = await fetch(`http://${ip}:8080${path}`, {
      ...opts,
      signal: ctrl.signal,
      headers: { 'Content-Type': 'application/json', ...(opts.headers || {}) },
    });
    clearTimeout(tid);
    return await res.json();
  } catch (e) {
    clearTimeout(tid);
    throw e;
  }
}

const SectionLabel = ({ children, t }) => (
  <Text style={{
    fontSize: 10, fontWeight: '700', letterSpacing: 1.2,
    color: t.textMuted || '#52525b',
    textTransform: 'uppercase', marginBottom: 8, marginTop: 4,
  }}>{children}</Text>
);

const Divider = ({ t }) => (
  <View style={{ height: 1, backgroundColor: t.border, marginVertical: 2 }} />
);

const InfoRow = ({ label, value, valueColor, t }) => (
  <View style={{
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 8, paddingHorizontal: 14,
  }}>
    <Text style={{
      flex: 1, fontSize: 12, fontWeight: '500',
      color: t.textSecond || '#8b949e',
    }}>{label}</Text>
    <Text style={{
      fontSize: 12, fontWeight: '600',
      color: valueColor || t.textPrimary || t.text || '#f4f4f5',
      textAlign: 'right', maxWidth: '55%',
    }} numberOfLines={1}>{value}</Text>
  </View>
);

const ProjectRow = ({ project, t, isLast, onOpen, onDelete }) => (
  <View>
    <View style={{
      flexDirection: 'row', alignItems: 'center',
      paddingVertical: 10, paddingHorizontal: 14,
    }}>
      <Text style={{
        flex: 1, fontSize: 13, fontWeight: '500',
        color: t.textPrimary || t.text || '#f4f4f5',
        fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
      }} numberOfLines={1}>{project.name}</Text>
      {project.is_symlink ? (
        <Text style={{
          fontSize: 10, fontWeight: '600', color: OC_ACCENT,
          marginRight: 8,
        }}>↗</Text>
      ) : null}
      <TouchableOpacity
        onPress={onOpen}
        activeOpacity={0.75}
        style={{
          paddingHorizontal: 12, paddingVertical: 6,
          borderRadius: 6, backgroundColor: OC_DIM,
          borderWidth: 1, borderColor: OC_ACCENT + '44',
          marginRight: 6,
        }}
      >
        <Text style={{ fontSize: 11, fontWeight: '600', color: OC_ACCENT }}>abrir</Text>
      </TouchableOpacity>
      <TouchableOpacity
        onPress={onDelete}
        activeOpacity={0.75}
        style={{
          width: 28, height: 28, borderRadius: 6,
          backgroundColor: (t.errorDim || '#2d0707'),
          borderWidth: 1, borderColor: (t.error || '#ef4444') + '44',
          alignItems: 'center', justifyContent: 'center',
        }}
      >
        <Text style={{ fontSize: 12, color: t.error || '#ef4444' }}>✕</Text>
      </TouchableOpacity>
    </View>
    {!isLast && <Divider t={t} />}
  </View>
);

export function OpenCodeScreen({ goBack }) {
  const { theme: t } = useTheme();
  const { status } = useStatus();

  const ip = status?.ip || '127.0.0.1';
  const mod = status?.modules?.find(m => m.id === 'opencode');

  const [info, setInfo] = useState(null);
  const [loading, setLoading] = useState(true);
  const [toggling, setToggling] = useState(false);
  const [feedback, setFeedback] = useState(null);
  const [projects, setProjects] = useState([]);

  const fbTimer = useRef(null);

  const showFeedback = useCallback((type, msg) => {
    if (fbTimer.current) clearTimeout(fbTimer.current);
    setFeedback({ type, msg });
    fbTimer.current = setTimeout(() => setFeedback(null), 3000);
  }, []);

  useEffect(() => () => { if (fbTimer.current) clearTimeout(fbTimer.current); }, []);

  const loadInfo = useCallback(async () => {
    try {
      const data = await apiFetch(ip, '/api/opencode/info');
      setInfo(data);
      setProjects(data.projects || []);
    } catch {
      // silent
    } finally {
      setLoading(false);
    }
  }, [ip]);

  useEffect(() => { loadInfo(); }, [loadInfo]);

  const handleToggle = useCallback(async (val) => {
    setToggling(true);
    try {
      const action = val ? 'start' : 'stop';
      const data = await apiFetch(ip, '/api/action', {
        method: 'POST',
        body: JSON.stringify({ action, module: 'opencode' }),
      });
      if (data.ok) {
        showFeedback('ok', val ? '✓ Iniciando...' : '✓ Detenido');
        setTimeout(loadInfo, 2000);
      } else {
        showFeedback('err', data.msg || 'Error');
      }
    } catch {
      showFeedback('err', 'Sin conexión al dashboard');
    } finally {
      setToggling(false);
    }
  }, [ip, loadInfo, showFeedback]);

  const openTerminal = useCallback((projectDir) => {
    const wsUrl = `ws://${ip}:${WS_PORT}?project=${encodeURIComponent(projectDir || '')}&cols=80&rows=30`;
    Alert.alert(
      'Terminal OpenCode',
      `Conectando a:\n${wsUrl}\n\nUsa un WebSocket client para interactuar.`,
      [{ text: 'OK' }]
    );
  }, [ip]);

  const deleteProject = useCallback((name) => {
    Alert.alert(
      'Eliminar proyecto',
      `¿Eliminar "${name}"? Solo borra el symlink, no la carpeta original.`,
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Eliminar', style: 'destructive',
          onPress: async () => {
            try {
              const data = await apiFetch(ip, '/api/claude/project/delete', {
                method: 'POST',
                body: JSON.stringify({ name }),
              });
              if (data.ok) {
                showFeedback('ok', `✓ ${name} eliminado`);
                loadInfo();
              } else {
                showFeedback('err', data.msg || 'Error');
              }
            } catch {
              showFeedback('err', 'Sin conexión');
            }
          },
        },
      ]
    );
  }, [ip, loadInfo, showFeedback]);

  const running = info?.running ?? mod?.running ?? false;
  const version = info?.version || mod?.version || '';
  const url = info?.url || '';

  const s = createStyles(t);

  return (
    <View style={s.root}>
      <View style={s.topBar}>
        <TouchableOpacity onPress={goBack} style={s.backBtn} activeOpacity={0.7}>
          <Text style={s.backTxt}>‹ Módulos</Text>
        </TouchableOpacity>
        <Text style={s.topTitle}>OpenCode</Text>
        <View style={s.topRight}>
          <View style={[s.pill, running ? s.pillActive : s.pillOff]}>
            <Text style={[s.pillDot, { color: running ? OC_ACCENT : (t.textMuted || '#52525b') }]}>●</Text>
            <Text style={[s.pillLbl, { color: running ? OC_ACCENT : (t.textMuted || '#52525b') }]}>
              {running ? 'activo' : 'detenido'}
            </Text>
          </View>
          <Switch
            value={running}
            onValueChange={handleToggle}
            disabled={toggling}
            trackColor={{ false: t.border, true: OC_ACCENT + '66' }}
            thumbColor={running ? OC_ACCENT : (t.textMuted || '#52525b')}
            style={{ marginLeft: 8 }}
          />
        </View>
      </View>

      {feedback && (
        <View style={[s.feedbackBanner, {
          backgroundColor: feedback.type === 'ok' ? (t.successDim || '#052e16') : (t.errorDim || '#2d0707'),
          borderColor: feedback.type === 'ok' ? (t.success || '#22c55e') : (t.error || '#ef4444'),
        }]}>
          <Text style={{
            fontSize: 12, fontWeight: '600',
            color: feedback.type === 'ok' ? (t.success || '#22c55e') : (t.error || '#ef4444'),
          }}>{feedback.msg}</Text>
        </View>
      )}

      <ScrollView
        style={s.scroll}
        contentContainerStyle={{ paddingBottom: 32 }}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl refreshing={loading} onRefresh={loadInfo} tintColor={OC_ACCENT} colors={[OC_ACCENT]} />
        }
      >
        {/* ── Sección: Servidor Web ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Servidor Web</SectionLabel>
          <View style={s.card}>
            {url ? (
              <TouchableOpacity
                onPress={() => {
                  Clipboard.setString(url);
                  showFeedback('ok', '✓ URL copiada');
                }}
                activeOpacity={0.7}
                style={{ paddingHorizontal: 14, paddingVertical: 14, flexDirection: 'row', alignItems: 'center' }}
              >
                <Text style={{
                  flex: 1, fontSize: 13, fontWeight: '500',
                  color: OC_ACCENT, fontFamily: 'monospace',
                }}>{url}</Text>
                <Text style={{ fontSize: 12, color: t.textMuted }}>⧉</Text>
              </TouchableOpacity>
            ) : (
              <View style={{ padding: 20, alignItems: 'center' }}>
                <Text style={{ fontSize: 13, color: t.textMuted || '#52525b' }}>
                  {running ? 'Obteniendo URL...' : 'Inicia el servidor web'}
                </Text>
              </View>
            )}
          </View>
        </View>

        {/* ── Sección: Proyectos ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Proyectos (~/proyectos)</SectionLabel>
          <View style={s.card}>
            {loading ? (
              <View style={{ padding: 20, alignItems: 'center' }}>
                <ActivityIndicator size="small" color={OC_ACCENT} />
              </View>
            ) : projects.length === 0 ? (
              <View style={{ padding: 20, alignItems: 'center' }}>
                <Text style={{ fontSize: 13, color: t.textMuted || '#52525b' }}>
                  Sin proyectos. Crea symlinks desde Downloads.
                </Text>
              </View>
            ) : (
              projects.map((p, i) => (
                <ProjectRow
                  key={p.name}
                  project={p}
                  t={t}
                  isLast={i === projects.length - 1}
                  onOpen={() => openTerminal(p.target || p.name)}
                  onDelete={() => deleteProject(p.name)}
                />
              ))
            )}
          </View>
        </View>

        {/* ── Info técnica ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Info Técnica</SectionLabel>
          <View style={s.card}>
            <InfoRow label="Versión" value={version || '—'} t={t} />
            <Divider t={t} />
            <InfoRow label="Puerto" value="3000 (proot Debian)" t={t} />
            <Divider t={t} />
            <InfoRow label="Ubicación" value="proot Debian" t={t} />
            <Divider t={t} />
            <InfoRow label="Provider" value={mod?.version ? 'configurable' : '—'} t={t} />
          </View>
        </View>

        <View style={{ height: 24 }} />
      </ScrollView>
    </View>
  );
}

function createStyles(t) {
  return StyleSheet.create({
    root: { flex: 1, backgroundColor: t.bg },
    topBar: {
      flexDirection: 'row', alignItems: 'center',
      paddingTop: 10, paddingBottom: 12, paddingHorizontal: 16,
      backgroundColor: t.surface, borderBottomWidth: 1, borderBottomColor: t.border,
    },
    backBtn: { paddingRight: 12, paddingVertical: 4, minWidth: 70 },
    backTxt: { fontSize: 15, fontWeight: '500', color: OC_ACCENT },
    topTitle: { flex: 1, fontSize: 15, fontWeight: '700', color: t.textPrimary || t.text || '#f4f4f5', textAlign: 'center' },
    topRight: { flexDirection: 'row', alignItems: 'center', minWidth: 70, justifyContent: 'flex-end' },
    pill: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 999, borderWidth: 1 },
    pillActive: { backgroundColor: OC_DIM, borderColor: OC_ACCENT + '55' },
    pillOff: { backgroundColor: t.overlay || '#1a1a1a', borderColor: t.border },
    pillDot: { fontSize: 8, marginRight: 4 },
    pillLbl: { fontSize: 10, fontWeight: '600', letterSpacing: 0.3 },
    feedbackBanner: { marginHorizontal: 16, marginTop: 8, paddingHorizontal: 14, paddingVertical: 8, borderRadius: 8, borderWidth: 1 },
    scroll: { flex: 1 },
    section: { marginTop: 20, paddingHorizontal: 16 },
    card: { backgroundColor: t.card, borderRadius: 12, borderWidth: 1, borderColor: t.border, overflow: 'hidden' },
  });
}
