// src/screens/ollama/OllamaScreen.js — v2.0 (S18)
// Fix crítico: t.textPrimary || t.text || '#f4f4f5' en todos los textos
// Conectado a endpoints reales del dashboard
// Pasa modelo y num_ctx seleccionados a ChatScreen

import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  Switch, ActivityIndicator, Alert, RefreshControl,
} from 'react-native';
import { useTheme } from '../../../theme/ThemeContext';
import { useStatus } from '../../../hooks/useStatus';

// ── Constantes ────────────────────────────────────────────────

const OLLAMA_ACCENT = '#4ade80';
const OLLAMA_DIM    = '#1a2a1a';

const CTX_OPTIONS = [
  { label: '512',  value: 512,  note: 'mín RAM' },
  { label: '1K',   value: 1024, note: 'rápido' },
  { label: '2K',   value: 2048, note: '◉ recmd' },
  { label: '4K',   value: 4096, note: 'normal' },
  { label: '8K',   value: 8192, note: 'lento' },
];

const PRESETS_DESCARGA = [
  { name: 'gemma3:1b',    size: '~815 MB', maker: 'Google',    note: 'rápido' },
  { name: 'llama3.2:1b',  size: '~1.3 GB', maker: 'Meta',      note: 'equilibrado' },
  { name: 'phi3:mini',    size: '~2.3 GB', maker: 'Microsoft', note: 'razonamiento' },
  { name: 'qwen2.5:0.5b', size: '~398 MB', maker: 'Alibaba',   note: 'ultraligero' },
];

// ── Helper fetch con timeout ──────────────────────────────────

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

// ── Componentes internos ──────────────────────────────────────

const SectionLabel = ({ children, style, t }) => (
  <Text style={[{
    fontSize: 10, fontWeight: '700', letterSpacing: 1.2,
    color: t.textMuted || '#52525b',
    textTransform: 'uppercase', marginBottom: 8, marginTop: 4,
  }, style]}>
    {children}
  </Text>
);

const Divider = ({ t }) => (
  <View style={{ height: 1, backgroundColor: t.border, marginVertical: 2 }} />
);

// Chip de num_ctx
const CtxChip = ({ opt, selected, onPress, t }) => (
  <TouchableOpacity
    onPress={onPress}
    activeOpacity={0.7}
    style={{
      paddingHorizontal: 14, paddingVertical: 8,
      borderRadius: 999,
      backgroundColor: selected ? OLLAMA_DIM : t.card,
      borderWidth: 1,
      borderColor: selected ? OLLAMA_ACCENT : (t.border),
      marginRight: 8, marginBottom: 8,
      alignItems: 'center',
    }}
  >
    <Text style={{
      fontSize: 13, fontWeight: selected ? '700' : '500',
      color: selected ? OLLAMA_ACCENT : (t.textPrimary || t.text || '#f4f4f5'),
    }}>
      {opt.label}
    </Text>
    {opt.note ? (
      <Text style={{
        fontSize: 9, fontWeight: '500', letterSpacing: 0.3,
        color: selected ? (OLLAMA_ACCENT + 'aa') : (t.textMuted || '#52525b'),
        marginTop: 1,
      }}>
        {opt.note}
      </Text>
    ) : null}
  </TouchableOpacity>
);

// Fila de modelo instalado
const ModelRow = ({ model, onChat, onDelete, t, isLast }) => (
  <View>
    <View style={{
      flexDirection: 'row', alignItems: 'center',
      paddingVertical: 12, paddingHorizontal: 14,
    }}>
      {/* Icono hexágono Ollama */}
      <View style={{
        width: 36, height: 36, borderRadius: 8,
        backgroundColor: OLLAMA_DIM,
        borderWidth: 1, borderColor: OLLAMA_ACCENT + '44',
        alignItems: 'center', justifyContent: 'center',
        marginRight: 12,
      }}>
        <Text style={{ fontSize: 16, color: OLLAMA_ACCENT, fontWeight: '700' }}>⬡</Text>
      </View>

      {/* Nombre + tamaño */}
      <View style={{ flex: 1 }}>
        <Text style={{
          fontSize: 13, fontWeight: '600',
          color: t.textPrimary || t.text || '#f4f4f5',
          fontFamily: 'monospace',
        }} numberOfLines={1}>
          {model.name}
        </Text>
        <Text style={{
          fontSize: 11, fontWeight: '500',
          color: t.textMuted || '#52525b',
          marginTop: 2,
        }}>
          {model.size}
        </Text>
      </View>

      {/* Botón chat */}
      <TouchableOpacity
        onPress={onChat}
        activeOpacity={0.75}
        style={{
          paddingHorizontal: 14, paddingVertical: 8,
          borderRadius: 8,
          backgroundColor: t.accentDim || '#1a2d5a',
          borderWidth: 1,
          borderColor: (t.accent || '#3d7aed') + '55',
          marginRight: 8,
        }}
      >
        <Text style={{
          fontSize: 12, fontWeight: '600',
          color: t.accent || '#3d7aed',
        }}>
          chat →
        </Text>
      </TouchableOpacity>

      {/* Botón eliminar */}
      <TouchableOpacity
        onPress={onDelete}
        activeOpacity={0.75}
        style={{
          width: 32, height: 32, borderRadius: 8,
          backgroundColor: (t.errorDim || '#2d0707'),
          borderWidth: 1, borderColor: (t.error || '#ef4444') + '44',
          alignItems: 'center', justifyContent: 'center',
        }}
      >
        <Text style={{ fontSize: 14, color: t.error || '#ef4444' }}>✕</Text>
      </TouchableOpacity>
    </View>
    {!isLast && <Divider t={t} />}
  </View>
);

// Fila de preset descarga
const PresetRow = ({ preset, isInstalled, pulling, onPull, t, isLast }) => (
  <View>
    <View style={{
      flexDirection: 'row', alignItems: 'center',
      paddingVertical: 12, paddingHorizontal: 14,
    }}>
      <View style={{ flex: 1 }}>
        <Text style={{
          fontSize: 13, fontWeight: '500',
          color: t.textPrimary || t.text || '#f4f4f5',
          fontFamily: 'monospace',
        }}>
          {preset.name}
        </Text>
        <Text style={{
          fontSize: 11, fontWeight: '400',
          color: t.textMuted || '#52525b',
          marginTop: 2,
        }}>
          {preset.size} · {preset.maker} · {preset.note}
        </Text>
      </View>

      {isInstalled ? (
        <View style={{
          paddingHorizontal: 10, paddingVertical: 5,
          borderRadius: 999, backgroundColor: OLLAMA_DIM,
          borderWidth: 1, borderColor: OLLAMA_ACCENT + '55',
        }}>
          <Text style={{ fontSize: 11, fontWeight: '600', color: OLLAMA_ACCENT }}>instalado</Text>
        </View>
      ) : pulling ? (
        <ActivityIndicator size="small" color={OLLAMA_ACCENT} />
      ) : (
        <TouchableOpacity
          onPress={onPull}
          activeOpacity={0.75}
          style={{
            width: 36, height: 36, borderRadius: 8,
            backgroundColor: t.overlay || '#1a1a1a',
            borderWidth: 1, borderColor: t.border,
            alignItems: 'center', justifyContent: 'center',
          }}
        >
          <Text style={{ fontSize: 16, color: t.textSecond || '#8b949e' }}>↓</Text>
        </TouchableOpacity>
      )}
    </View>
    {!isLast && <Divider t={t} />}
  </View>
);

// ── Pantalla principal ────────────────────────────────────────

export default function OllamaScreen({ navigate, goBack }) {
  const { theme: t } = useTheme();
  const { status } = useStatus();

  const ip = status?.ip || '127.0.0.1';
  const ollamaRunning = status?.modules?.find(m => m.id === 'ollama')?.running ?? false;

  const [models,      setModels]      = useState([]);
  const [loadingMdl,  setLoadingMdl]  = useState(true);
  const [numCtx,      setNumCtx]      = useState(2048);
  const [toggling,    setToggling]    = useState(false);
  const [pullingMap,  setPullingMap]  = useState({});   // { 'model:tag': true }
  const [refreshing,  setRefreshing]  = useState(false);
  const [feedback,    setFeedback]    = useState(null); // { type: 'ok'|'err', msg }

  const feedbackTimer = useRef(null);

  // ── Feedback temporal ──────────────────────────────────────

  const showFeedback = useCallback((type, msg) => {
    if (feedbackTimer.current) clearTimeout(feedbackTimer.current);
    setFeedback({ type, msg });
    feedbackTimer.current = setTimeout(() => setFeedback(null), 3000);
  }, []);

  useEffect(() => () => {
    if (feedbackTimer.current) clearTimeout(feedbackTimer.current);
  }, []);

  // ── Cargar modelos ─────────────────────────────────────────

  const loadModels = useCallback(async () => {
    try {
      const data = await apiFetch(ip, '/api/ollama/models');
      // data.models: [{ name, size, digest }] o array de strings
      const raw = data.models || [];
      const normalized = raw.map(m =>
        typeof m === 'string'
          ? { name: m, size: '—' }
          : { name: m.name || m, size: m.size ? formatSize(m.size) : '—' }
      );
      setModels(normalized);
    } catch {
      // no mostrar error en carga silenciosa
    } finally {
      setLoadingMdl(false);
      setRefreshing(false);
    }
  }, [ip]);

  useEffect(() => { loadModels(); }, [loadModels]);

  const onRefresh = useCallback(() => {
    setRefreshing(true);
    loadModels();
  }, [loadModels]);

  // ── Toggle Ollama ──────────────────────────────────────────

  const handleToggle = useCallback(async (val) => {
    setToggling(true);
    try {
      const action = val ? 'start_ollama' : 'stop_ollama';
      await apiFetch(ip, '/api/action', {
        method: 'POST',
        body: JSON.stringify({ action }),
      });
    } catch (e) {
      showFeedback('err', 'Error al cambiar estado');
    } finally {
      setToggling(false);
    }
  }, [ip, showFeedback]);

  // ── Eliminar modelo ────────────────────────────────────────

  const handleDelete = useCallback((modelName) => {
    Alert.alert(
      'Eliminar modelo',
      `¿Eliminar ${modelName}? No se puede deshacer.`,
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Eliminar', style: 'destructive',
          onPress: async () => {
            try {
              const data = await apiFetch(ip, '/api/ollama/delete', {
                method: 'POST',
                body: JSON.stringify({ name: modelName }),
              });
              if (data.ok) {
                showFeedback('ok', `✓ ${modelName} eliminado`);
                loadModels();
              } else {
                showFeedback('err', data.error || 'Error al eliminar');
              }
            } catch {
              showFeedback('err', 'Sin conexión al dashboard');
            }
          },
        },
      ]
    );
  }, [ip, loadModels, showFeedback]);

  // ── Descargar modelo ───────────────────────────────────────

  const handlePull = useCallback(async (modelName) => {
    setPullingMap(p => ({ ...p, [modelName]: true }));
    try {
      const data = await apiFetch(ip, '/api/ollama/pull', {
        method: 'POST',
        body: JSON.stringify({ name: modelName }),
      }, 180_000); // 3 min — descarga puede tardar
      if (data.ok) {
        showFeedback('ok', `✓ ${modelName} descargado`);
        loadModels();
      } else {
        showFeedback('err', data.error || 'Error al descargar');
      }
    } catch {
      showFeedback('err', 'Timeout o sin conexión');
    } finally {
      setPullingMap(p => { const n = { ...p }; delete n[modelName]; return n; });
    }
  }, [ip, loadModels, showFeedback]);

  // ── Ir al chat ─────────────────────────────────────────────

  const handleGoChat = useCallback((modelName) => {
    if (!ollamaRunning) {
      showFeedback('err', 'Inicia Ollama primero');
      return;
    }
    navigate('Chat', { model: modelName, numCtx });
  }, [ollamaRunning, numCtx, navigate, showFeedback]);

  // ── Render ─────────────────────────────────────────────────

  const s = createStyles(t);

  const installedNames = new Set(models.map(m => m.name));

  return (
    <View style={s.root}>
      {/* ── TopBar ── */}
      <View style={s.topBar}>
        <TouchableOpacity onPress={goBack} style={s.backBtn} activeOpacity={0.7}>
          <Text style={s.backTxt}>‹ Módulos</Text>
        </TouchableOpacity>

        <Text style={s.topTitle}>Ollama</Text>

        <View style={s.topRight}>
          {/* Pill estado */}
          <View style={[s.pill, ollamaRunning ? s.pillActive : s.pillOff]}>
            <Text style={[s.pillDot, { color: ollamaRunning ? OLLAMA_ACCENT : (t.textMuted || '#52525b') }]}>●</Text>
            <Text style={[s.pillLbl, { color: ollamaRunning ? OLLAMA_ACCENT : (t.textMuted || '#52525b') }]}>
              {ollamaRunning ? 'activo' : 'detenido'}
            </Text>
          </View>

          {/* Switch */}
          <Switch
            value={ollamaRunning}
            onValueChange={handleToggle}
            disabled={toggling}
            trackColor={{ false: t.border, true: OLLAMA_ACCENT + '66' }}
            thumbColor={ollamaRunning ? OLLAMA_ACCENT : (t.textMuted || '#52525b')}
            style={{ marginLeft: 8 }}
          />
        </View>
      </View>

      {/* ── Feedback banner ── */}
      {feedback && (
        <View style={[s.feedbackBanner, {
          backgroundColor: feedback.type === 'ok' ? (t.successDim || '#052e16') : (t.errorDim || '#2d0707'),
          borderColor: feedback.type === 'ok' ? (t.success || '#22c55e') : (t.error || '#ef4444'),
        }]}>
          <Text style={{
            fontSize: 12, fontWeight: '600',
            color: feedback.type === 'ok' ? (t.success || '#22c55e') : (t.error || '#ef4444'),
          }}>
            {feedback.msg}
          </Text>
        </View>
      )}

      <ScrollView
        style={s.scroll}
        contentContainerStyle={{ paddingBottom: 32 }}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={OLLAMA_ACCENT}
            colors={[OLLAMA_ACCENT]}
          />
        }
      >
        {/* ── Sección: Modelos instalados ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Modelos instalados</SectionLabel>

          <View style={s.card}>
            {loadingMdl ? (
              <View style={s.loadingRow}>
                <ActivityIndicator size="small" color={OLLAMA_ACCENT} />
                <Text style={[s.loadingTxt, { color: t.textMuted || '#52525b' }]}>
                  Consultando Ollama…
                </Text>
              </View>
            ) : models.length === 0 ? (
              <View style={s.emptyRow}>
                <Text style={{ fontSize: 24, marginBottom: 8 }}>⬡</Text>
                <Text style={{ fontSize: 13, color: t.textMuted || '#52525b' }}>
                  No hay modelos instalados
                </Text>
                <Text style={{ fontSize: 11, color: t.textMuted || '#52525b', marginTop: 4 }}>
                  Descarga uno desde la sección inferior
                </Text>
              </View>
            ) : (
              models.map((m, i) => (
                <ModelRow
                  key={m.name}
                  model={m}
                  onChat={() => handleGoChat(m.name)}
                  onDelete={() => handleDelete(m.name)}
                  t={t}
                  isLast={i === models.length - 1}
                />
              ))
            )}
          </View>
        </View>

        {/* ── Sección: Contexto num_ctx ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Contexto (NUM_CTX)</SectionLabel>

          <View style={s.card}>
            <View style={{ paddingHorizontal: 14, paddingTop: 12, paddingBottom: 4 }}>
              <Text style={{
                fontSize: 12, fontWeight: '400',
                color: t.textSecond || '#8b949e',
                marginBottom: 12,
              }}>
                Tokens de contexto por sesión de chat
              </Text>

              <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
                {CTX_OPTIONS.map(opt => (
                  <CtxChip
                    key={opt.value}
                    opt={opt}
                    selected={numCtx === opt.value}
                    onPress={() => setNumCtx(opt.value)}
                    t={t}
                  />
                ))}
              </View>

              <Text style={{
                fontSize: 11, fontWeight: '500',
                color: t.textMuted || '#52525b',
                marginTop: 4, marginBottom: 8,
              }}>
                ✓ {numCtx.toLocaleString()} tokens — {ctxNote(numCtx)}
              </Text>
            </View>
          </View>
        </View>

        {/* ── Sección: Descargar modelo ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Descargar modelo</SectionLabel>

          <View style={s.card}>
            {PRESETS_DESCARGA.map((p, i) => (
              <PresetRow
                key={p.name}
                preset={p}
                isInstalled={installedNames.has(p.name)}
                pulling={!!pullingMap[p.name]}
                onPull={() => handlePull(p.name)}
                t={t}
                isLast={i === PRESETS_DESCARGA.length - 1}
              />
            ))}
          </View>
        </View>

        {/* ── Botón ir al chat ── */}
        <View style={[s.section, { marginTop: 8 }]}>
          <TouchableOpacity
            onPress={() => {
              const defaultModel = models[0]?.name || 'qwen2.5:0.5b';
              handleGoChat(defaultModel);
            }}
            activeOpacity={0.8}
            disabled={models.length === 0}
            style={[s.chatBtn, models.length === 0 && { opacity: 0.4 }]}
          >
            <Text style={s.chatBtnTxt}>→ Ir al Chat</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </View>
  );
}

// ── Helpers ───────────────────────────────────────────────────

function formatSize(bytes) {
  if (!bytes || bytes === 0) return '—';
  const gb = bytes / 1e9;
  if (gb >= 1) return `${gb.toFixed(1)} GB`;
  return `${(bytes / 1e6).toFixed(0)} MB`;
}

function ctxNote(n) {
  if (n <= 512)  return 'uso mínimo de RAM';
  if (n <= 1024) return 'uso bajo de RAM';
  if (n <= 2048) return 'uso moderado de RAM';
  if (n <= 4096) return 'uso alto de RAM';
  return 'uso máximo de RAM';
}

// ── Estilos ───────────────────────────────────────────────────

function createStyles(t) {
  return StyleSheet.create({
    root: {
      flex: 1,
      backgroundColor: t.bg,
    },
    topBar: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingTop: 10,
      paddingBottom: 12,
      paddingHorizontal: 16,
      backgroundColor: t.surface,
      borderBottomWidth: 1,
      borderBottomColor: t.border,
    },
    backBtn: {
      paddingRight: 12,
      paddingVertical: 4,
      minWidth: 70,
    },
    backTxt: {
      fontSize: 15,
      fontWeight: '500',
      color: OLLAMA_ACCENT,
    },
    topTitle: {
      flex: 1,
      fontSize: 15,
      fontWeight: '700',
      color: t.textPrimary || t.text || '#f4f4f5',
      textAlign: 'center',
    },
    topRight: {
      flexDirection: 'row',
      alignItems: 'center',
      minWidth: 70,
      justifyContent: 'flex-end',
    },
    pill: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: 8,
      paddingVertical: 4,
      borderRadius: 999,
      borderWidth: 1,
    },
    pillActive: {
      backgroundColor: OLLAMA_DIM,
      borderColor: OLLAMA_ACCENT + '55',
    },
    pillOff: {
      backgroundColor: t.overlay || '#1a1a1a',
      borderColor: t.border,
    },
    pillDot: {
      fontSize: 8,
      marginRight: 4,
    },
    pillLbl: {
      fontSize: 10,
      fontWeight: '600',
      letterSpacing: 0.3,
    },
    feedbackBanner: {
      marginHorizontal: 16,
      marginTop: 8,
      paddingHorizontal: 14,
      paddingVertical: 8,
      borderRadius: 8,
      borderWidth: 1,
    },
    scroll: {
      flex: 1,
    },
    section: {
      marginTop: 20,
      paddingHorizontal: 16,
    },
    card: {
      backgroundColor: t.card,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: t.border,
      overflow: 'hidden',
    },
    loadingRow: {
      flexDirection: 'row',
      alignItems: 'center',
      padding: 20,
      justifyContent: 'center',
    },
    loadingTxt: {
      fontSize: 13,
      fontWeight: '400',
      marginLeft: 10,
    },
    emptyRow: {
      alignItems: 'center',
      padding: 28,
    },
    chatBtn: {
      backgroundColor: OLLAMA_ACCENT,
      borderRadius: 12,
      paddingVertical: 16,
      alignItems: 'center',
    },
    chatBtnTxt: {
      fontSize: 15,
      fontWeight: '700',
      color: '#000000',
      letterSpacing: 0.3,
    },
  });
}
