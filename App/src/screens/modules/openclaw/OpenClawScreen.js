import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  Switch, ActivityIndicator, Alert, RefreshControl, Platform, Clipboard,
} from 'react-native';
import { useTheme } from '../../../theme/ThemeContext';
import { useStatus } from '../../../hooks/useStatus';
import { getOpenClawInfo } from '../../../services/dashboard';

const CL_ACCENT = '#f59e0b';
const CL_DIM    = '#2a2215';

const WIZARD_PROVIDERS = [
  { id: 'ollama',     name: 'Ollama local',     desc: ':11434 · gratis',         accent: '#4ade80' },
  { id: 'anthropic',  name: 'Anthropic',         desc: 'API key · Claude',        accent: '#d97706' },
  { id: 'openai',     name: 'OpenAI',            desc: 'API key · GPT',           accent: '#10b981' },
  { id: 'openrouter', name: 'OpenRouter',        desc: 'API key · varios',        accent: '#8b5cf6' },
];

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

const ProviderChip = ({ prov, selected, onPress, t }) => (
  <TouchableOpacity
    onPress={onPress}
    activeOpacity={0.7}
    style={{
      paddingHorizontal: 14, paddingVertical: 10,
      borderRadius: 10,
      backgroundColor: selected ? CL_DIM : t.card,
      borderWidth: 1,
      borderColor: selected ? CL_ACCENT : t.border,
      marginRight: 8, marginBottom: 8,
      alignItems: 'center', minWidth: 80,
    }}
  >
    <Text style={{
      fontSize: 13, fontWeight: selected ? '700' : '500',
      color: selected ? CL_ACCENT : (t.textPrimary || t.text || '#f4f4f5'),
    }}>{prov.name}</Text>
    <Text style={{
      fontSize: 9, fontWeight: '500',
      color: selected ? (CL_ACCENT + 'aa') : (t.textMuted || '#52525b'),
      marginTop: 2,
    }}>{prov.desc}</Text>
  </TouchableOpacity>
);

export function OpenClawScreen({ goBack }) {
  const { theme: t } = useTheme();
  const { status } = useStatus();

  const ip = status?.ip || '127.0.0.1';
  const mod = status?.modules?.find(m => m.id === 'openclaw');

  const [info, setInfo] = useState(null);
  const [loading, setLoading] = useState(true);
  const [toggling, setToggling] = useState(false);
  const [feedback, setFeedback] = useState(null);
  const [selectedProv, setSelectedProv] = useState(null);
  const [savingProv, setSavingProv] = useState(false);

  const fbTimer = useRef(null);

  const showFeedback = useCallback((type, msg) => {
    if (fbTimer.current) clearTimeout(fbTimer.current);
    setFeedback({ type, msg });
    fbTimer.current = setTimeout(() => setFeedback(null), 3000);
  }, []);

  useEffect(() => () => { if (fbTimer.current) clearTimeout(fbTimer.current); }, []);

  const loadInfo = useCallback(async () => {
    try {
      const data = await getOpenClawInfo();
      setInfo(data);
      if (data?.model) {
        const found = WIZARD_PROVIDERS.find(p => data.model.includes(p.id) || p.id === 'ollama');
        if (found) setSelectedProv(found.id);
      }
    } catch {
      // silent
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadInfo(); }, [loadInfo]);

  useEffect(() => {
    if (mod?.running) {
      const t = setTimeout(loadInfo, 3000);
      return () => clearTimeout(t);
    }
  }, [mod?.running]);

  const handleToggle = useCallback(async (val) => {
    setToggling(true);
    try {
      const action = val ? 'start' : 'stop';
      const data = await apiFetch(ip, '/api/action', {
        method: 'POST',
        body: JSON.stringify({ action, module: 'openclaw' }),
      });
      if (data.ok) {
        showFeedback('ok', val ? '✓ Iniciando gateway...' : '✓ Detenido');
        setTimeout(loadInfo, 4000);
      } else {
        showFeedback('err', data.msg || 'Error');
      }
    } catch {
      showFeedback('err', 'Sin conexión al dashboard');
    } finally {
      setToggling(false);
    }
  }, [ip, loadInfo, showFeedback]);

  const handleSetProvider = useCallback(async (provId) => {
    setSavingProv(true);
    try {
      const data = await apiFetch(ip, '/api/action', {
        method: 'POST',
        body: JSON.stringify({ action: `provider:${provId}`, module: 'openclaw' }),
      });
      showFeedback(data.ok ? 'ok' : 'err', data.msg || (data.ok ? '✓ Proveedor cambiado' : 'Error'));
      if (data.ok) {
        setSelectedProv(provId);
        setTimeout(loadInfo, 2000);
      }
    } catch {
      showFeedback('err', 'Sin conexión');
    } finally {
      setSavingProv(false);
    }
  }, [ip, loadInfo, showFeedback]);

  const running = info?.running ?? mod?.running ?? false;
  const token = info?.token || '';
  const model = info?.model || '';
  const wsUrl = info?.url || '';

  const s = createStyles(t);

  return (
    <View style={s.root}>
      <View style={s.topBar}>
        <TouchableOpacity onPress={goBack} style={s.backBtn} activeOpacity={0.7}>
          <Text style={s.backTxt}>‹ Módulos</Text>
        </TouchableOpacity>
        <Text style={s.topTitle}>OpenClaw</Text>
        <View style={s.topRight}>
          <View style={[s.pill, running ? s.pillActive : s.pillOff]}>
            <Text style={[s.pillDot, { color: running ? CL_ACCENT : (t.textMuted || '#52525b') }]}>●</Text>
            <Text style={[s.pillLbl, { color: running ? CL_ACCENT : (t.textMuted || '#52525b') }]}>
              {running ? 'activo' : 'detenido'}
            </Text>
          </View>
          <Switch
            value={running}
            onValueChange={handleToggle}
            disabled={toggling}
            trackColor={{ false: t.border, true: CL_ACCENT + '66' }}
            thumbColor={running ? CL_ACCENT : (t.textMuted || '#52525b')}
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
          <RefreshControl refreshing={loading} onRefresh={loadInfo} tintColor={CL_ACCENT} colors={[CL_ACCENT]} />
        }
      >
        {/* ── Dashboard URL ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Dashboard Web</SectionLabel>
          <View style={s.card}>
            {wsUrl ? (
              <TouchableOpacity
                onPress={() => {
                  Clipboard.setString(wsUrl);
                  showFeedback('ok', '✓ URL copiada');
                }}
                activeOpacity={0.7}
                style={{ paddingHorizontal: 14, paddingVertical: 14, flexDirection: 'row', alignItems: 'center' }}
              >
                <Text style={{
                  flex: 1, fontSize: 13, fontWeight: '500',
                  color: CL_ACCENT, fontFamily: 'monospace',
                }} numberOfLines={1}>{wsUrl}</Text>
                <Text style={{ fontSize: 12, color: t.textMuted }}>⧉</Text>
              </TouchableOpacity>
            ) : (
              <View style={{ padding: 20, alignItems: 'center' }}>
                <Text style={{ fontSize: 13, color: t.textMuted || '#52525b' }}>
                  {running ? 'Obteniendo URL...' : 'Inicia el gateway'}
                </Text>
              </View>
            )}
          </View>
        </View>

        {/* ── Token ── */}
        {token ? (
          <View style={s.section}>
            <SectionLabel t={t}>Token de Autenticación</SectionLabel>
            <View style={s.card}>
              <TouchableOpacity
                onPress={() => {
                  Clipboard.setString(token);
                  showFeedback('ok', '✓ Token copiado');
                }}
                activeOpacity={0.7}
                style={{ paddingHorizontal: 14, paddingVertical: 14, flexDirection: 'row', alignItems: 'center' }}
              >
                <Text style={{
                  flex: 1, fontSize: 12, fontWeight: '500',
                  color: t.textSecond || '#8b949e', fontFamily: 'monospace',
                }} numberOfLines={1}>{token.substring(0, 32)}...</Text>
                <Text style={{ fontSize: 12, color: t.textMuted }}>⧉</Text>
              </TouchableOpacity>
            </View>
          </View>
        ) : null}

        {/* ── Proveedor IA ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Proveedor IA</SectionLabel>
          <View style={s.card}>
            <View style={{ paddingHorizontal: 14, paddingTop: 12, paddingBottom: 4 }}>
              <Text style={{
                fontSize: 12, fontWeight: '400',
                color: t.textSecond || '#8b949e',
                marginBottom: 12,
              }}>
                {model ? `Modelo activo: ${model}` : 'Selecciona un proveedor'}
              </Text>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
                {WIZARD_PROVIDERS.map(prov => (
                  <ProviderChip
                    key={prov.id}
                    prov={prov}
                    selected={selectedProv === prov.id}
                    onPress={() => handleSetProvider(prov.id)}
                    t={t}
                  />
                ))}
              </View>
              {savingProv && (
                <ActivityIndicator size="small" color={CL_ACCENT} style={{ marginTop: 8 }} />
              )}
            </View>
          </View>
        </View>

        {/* ── Info técnica ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Info Técnica</SectionLabel>
          <View style={s.card}>
            <InfoRow label="Puerto" value="18789 (proot Debian)" t={t} />
            <Divider t={t} />
            <InfoRow label="Ubicación" value="proot Debian" t={t} />
            <Divider t={t} />
            <InfoRow label="Modelo" value={model || '—'} t={t} />
            <Divider t={t} />
            <InfoRow label="Auth" value={token ? 'Token configurado' : 'Sin token'} t={t}
              valueColor={token ? t.success : t.textMuted} />
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
    backTxt: { fontSize: 15, fontWeight: '500', color: CL_ACCENT },
    topTitle: { flex: 1, fontSize: 15, fontWeight: '700', color: t.textPrimary || t.text || '#f4f4f5', textAlign: 'center' },
    topRight: { flexDirection: 'row', alignItems: 'center', minWidth: 70, justifyContent: 'flex-end' },
    pill: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 999, borderWidth: 1 },
    pillActive: { backgroundColor: CL_DIM, borderColor: CL_ACCENT + '55' },
    pillOff: { backgroundColor: t.overlay || '#1a1a1a', borderColor: t.border },
    pillDot: { fontSize: 8, marginRight: 4 },
    pillLbl: { fontSize: 10, fontWeight: '600', letterSpacing: 0.3 },
    feedbackBanner: { marginHorizontal: 16, marginTop: 8, paddingHorizontal: 14, paddingVertical: 8, borderRadius: 8, borderWidth: 1 },
    scroll: { flex: 1 },
    section: { marginTop: 20, paddingHorizontal: 16 },
    card: { backgroundColor: t.card, borderRadius: 12, borderWidth: 1, borderColor: t.border, overflow: 'hidden' },
  });
}
