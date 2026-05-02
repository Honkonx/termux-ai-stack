// src/screens/modules/ollama/OllamaScreen.js — v1.0.0 (S14)
// SURFACE:   bg + surface + card. Acento verde #4ade80 — terminal/IA local
// JERARQUÍA: topBarTitle > sectionLabel > modelName > modelMeta/caption
// ACENTO:    #4ade80 (verde Ollama) — chips seleccionados, botón chat, íconos activos
// BORDES:    1px rgba sutil. Chips seleccionados con borderColor acento.
// DENSIDAD:  Media-alta. Lista de modelos + chips compactos + descargar con presets.

import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, ScrollView, TouchableOpacity,
  StyleSheet, ActivityIndicator, Alert,
} from 'react-native';
import { useTheme }       from '../../../theme/ThemeContext';
import { StatusPill }     from '../../../components/StatusPill';
import { ActionButton }   from '../../../components/ActionButton';
import { SectionLabel }   from '../../../components/SectionLabel';
import { Divider }        from '../../../components/Divider';
import { Icons }          from '../../../theme/icons';
import { useStatus }      from '../../../hooks/useStatus';
import { useAction }      from '../../../hooks/useAction';
import { apiFetch }       from '../../../services/api';
import { ROUTES }         from '../../../navigation/routes';

// ─── Constantes ──────────────────────────────────────────────────────────────
const CTX_OPTIONS = [512, 1024, 2048, 4096, 8192];
const MODEL_PRESETS = [
  { id: 'gemma3:1b',     label: 'gemma3:1b',     size: '~815MB', note: 'Google · rápido' },
  { id: 'llama3.2:1b',   label: 'llama3.2:1b',   size: '~1.3GB', note: 'Meta · equilibrado' },
  { id: 'phi3:mini',     label: 'phi3:mini',      size: '~2.3GB', note: 'Microsoft · razonamiento' },
  { id: 'qwen2.5:0.5b',  label: 'qwen2.5:0.5b',  size: '~398MB', note: 'Alibaba · ultraligero' },
];

// ─── Componente principal ─────────────────────────────────────────────────────
export function OllamaScreen({ navigate, goBack }) {
  const { theme }   = useTheme();
  const s           = createStyles(theme);
  const { status }  = useStatus();
  const { trigger } = useAction();

  // Modelos instalados
  const [models, setModels]       = useState([]);
  const [modelsLoading, setModelsLoading] = useState(false);
  const [modelsErr, setModelsErr] = useState(null);

  // num_ctx seleccionado
  const [selectedCtx, setSelectedCtx] = useState(2048);

  // Descarga
  const [downloadingId, setDownloadingId] = useState(null);
  const [downloadMsg, setDownloadMsg]     = useState({}); // { [modelId]: { ok, text } }

  // Eliminar
  const [deletingId, setDeletingId] = useState(null);

  // Switch start/stop
  const [toggling, setToggling] = useState(false);

  const ollamaModule = status?.modules?.find(m => m.id === 'ollama');
  const isActive     = ollamaModule?.status === 'active';

  // Carga modelos al montar
  useEffect(() => {
    loadModels();
  }, []);

  // ── Carga modelos ────────────────────────────────────────────────
  const loadModels = useCallback(async () => {
    setModelsLoading(true);
    setModelsErr(null);
    try {
      const res = await apiFetch('/api/ollama/models');
      setModels(res.models || []);
    } catch {
      setModelsErr('No se pudo conectar con Ollama');
    } finally {
      setModelsLoading(false);
    }
  }, []);

  // ── Toggle start/stop ────────────────────────────────────────────
  const handleToggle = useCallback(async () => {
    if (toggling) return;
    setToggling(true);
    const action = isActive ? 'stop' : 'start';
    await trigger('ollama', action);
    setToggling(false);
  }, [toggling, isActive, trigger]);

  // ── Eliminar modelo ──────────────────────────────────────────────
  const handleDelete = useCallback((modelName) => {
    Alert.alert(
      'Eliminar modelo',
      `¿Eliminar "${modelName}"?\nEsta acción no se puede deshacer.`,
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Eliminar',
          style: 'destructive',
          onPress: async () => {
            setDeletingId(modelName);
            try {
              await apiFetch('/api/ollama/delete', {
                method: 'POST',
                body: JSON.stringify({ model: modelName }),
              });
              setModels(prev => prev.filter(m => m.name !== modelName));
            } catch {
              // silencioso — usuario puede recargar
            } finally {
              setDeletingId(null);
            }
          },
        },
      ]
    );
  }, []);

  // ── Descargar modelo ─────────────────────────────────────────────
  const handleDownload = useCallback(async (modelId) => {
    if (downloadingId) return;
    setDownloadingId(modelId);
    setDownloadMsg(prev => ({ ...prev, [modelId]: null }));
    try {
      const res = await apiFetch('/api/ollama/pull', {
        method: 'POST',
        body: JSON.stringify({ model: modelId }),
      });
      setDownloadMsg(prev => ({
        ...prev,
        [modelId]: { ok: res.ok, text: res.ok ? 'Descarga iniciada en Ollama' : (res.msg || 'Error') },
      }));
      if (res.ok) setTimeout(loadModels, 3000);
    } catch {
      setDownloadMsg(prev => ({
        ...prev,
        [modelId]: { ok: false, text: 'Sin respuesta del dashboard' },
      }));
    } finally {
      setDownloadingId(null);
    }
  }, [downloadingId, loadModels]);

  // ── Ir al Chat ───────────────────────────────────────────────────
  const handleGoChat = useCallback(() => {
    navigate(ROUTES.CHAT);
  }, [navigate]);

  // ─────────────────────────────────────────────────────────────────
  return (
    <View style={s.root}>
      {/* TopBar */}
      <View style={s.topBar}>
        <TouchableOpacity onPress={goBack} style={s.backBtn} hitSlop={{ top:10, bottom:10, left:10, right:10 }}>
          <Text style={s.backIcon}>{Icons.back}</Text>
          <Text style={s.backLabel}>Módulos</Text>
        </TouchableOpacity>
        <View style={s.topBarCenter}>
          <Text style={s.topBarTitle}>Ollama</Text>
        </View>
        <View style={s.topBarRight}>
          <StatusPill status={ollamaModule?.status ?? 'inactive'} />
          <TouchableOpacity
            onPress={handleToggle}
            disabled={toggling}
            style={[s.switchBtn, { backgroundColor: isActive ? theme.success + '22' : theme.surface }]}
            hitSlop={{ top:8, bottom:8, left:8, right:8 }}
          >
            {toggling
              ? <ActivityIndicator size="small" color={theme.accent} />
              : <Text style={[s.switchText, { color: isActive ? theme.success : theme.textMuted }]}>
                  {isActive ? 'ON' : 'OFF'}
                </Text>
            }
          </TouchableOpacity>
        </View>
      </View>

      <ScrollView
        style={s.scroll}
        contentContainerStyle={s.scrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* ── Sección 1: Modelos instalados ── */}
        <View style={s.sectionRow}>
          <SectionLabel>MODELOS INSTALADOS</SectionLabel>
          <TouchableOpacity onPress={loadModels} hitSlop={{ top:8, bottom:8, left:8, right:8 }}>
            <Text style={s.refreshBtn}>{Icons.refresh}</Text>
          </TouchableOpacity>
        </View>

        <View style={s.card}>
          {modelsLoading ? (
            <View style={s.centerRow}>
              <ActivityIndicator size="small" color={theme.accent} />
              <Text style={s.loadingText}>Cargando modelos...</Text>
            </View>
          ) : modelsErr ? (
            <View style={s.centerRow}>
              <Text style={[s.statusText, { color: theme.error }]}>{Icons.error} {modelsErr}</Text>
            </View>
          ) : models.length === 0 ? (
            <Text style={s.emptyText}>No hay modelos instalados</Text>
          ) : (
            models.map((model, i) => (
              <View
                key={model.name}
                style={[s.modelRow, i > 0 && { borderTopWidth: 1, borderTopColor: theme.border }]}
              >
                <View style={s.modelIconBox}>
                  <Text style={s.modelIcon}>⬡</Text>
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={s.modelName} numberOfLines={1}>{model.name}</Text>
                  {model.size && <Text style={s.modelMeta}>{model.size}</Text>}
                </View>
                {/* Botón Chat */}
                <TouchableOpacity
                  onPress={handleGoChat}
                  style={s.modelChatBtn}
                  hitSlop={{ top:6, bottom:6, left:6, right:6 }}
                >
                  <Text style={s.modelChatText}>chat →</Text>
                </TouchableOpacity>
                {/* Botón Eliminar */}
                <TouchableOpacity
                  onPress={() => handleDelete(model.name)}
                  disabled={deletingId === model.name}
                  style={s.modelDeleteBtn}
                  hitSlop={{ top:6, bottom:6, left:6, right:6 }}
                >
                  {deletingId === model.name
                    ? <ActivityIndicator size="small" color={theme.error} />
                    : <Text style={s.modelDeleteText}>✕</Text>
                  }
                </TouchableOpacity>
              </View>
            ))
          )}
        </View>

        {/* ── Sección 2: num_ctx ── */}
        <SectionLabel style={{ marginTop: 20 }}>CONTEXTO (num_ctx)</SectionLabel>
        <View style={s.card}>
          <Text style={s.ctxHint}>Tokens de contexto por sesión de chat</Text>
          <View style={s.chipsRow}>
            {CTX_OPTIONS.map(ctx => (
              <TouchableOpacity
                key={ctx}
                onPress={() => setSelectedCtx(ctx)}
                style={[
                  s.chip,
                  selectedCtx === ctx && { borderColor: theme.accent, backgroundColor: theme.accent + '18' },
                ]}
              >
                <Text style={[s.chipText, selectedCtx === ctx && { color: theme.accent, fontWeight: '700' }]}>
                  {ctx >= 1024 ? `${ctx / 1024}k` : ctx}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
          <Text style={s.ctxNote}>
            {selectedCtx >= 4096
              ? `⚠ ${selectedCtx} tokens puede saturar RAM en POCO F5`
              : `✓ ${selectedCtx} tokens — uso moderado de RAM`}
          </Text>
        </View>

        {/* ── Sección 3: Descargar modelo ── */}
        <SectionLabel style={{ marginTop: 20 }}>DESCARGAR MODELO</SectionLabel>
        <View style={s.card}>
          {MODEL_PRESETS.map((preset, i) => {
            const msg       = downloadMsg[preset.id];
            const isLoading = downloadingId === preset.id;
            const installed = models.some(m => m.name === preset.id);
            return (
              <View key={preset.id}>
                {i > 0 && <Divider />}
                <View style={s.presetRow}>
                  <View style={{ flex: 1 }}>
                    <View style={s.presetNameRow}>
                      <Text style={s.presetName}>{preset.label}</Text>
                      {installed && (
                        <View style={s.installedBadge}>
                          <Text style={s.installedText}>instalado</Text>
                        </View>
                      )}
                    </View>
                    <Text style={s.presetMeta}>{preset.size} · {preset.note}</Text>
                    {msg && (
                      <Text style={[s.presetMsg, { color: msg.ok ? theme.success : theme.error }]}>
                        {msg.ok ? `${Icons.check} ` : `${Icons.error} `}{msg.text}
                      </Text>
                    )}
                  </View>
                  <TouchableOpacity
                    onPress={() => handleDownload(preset.id)}
                    disabled={isLoading || !!downloadingId || installed}
                    style={[
                      s.downloadBtn,
                      (installed || !!downloadingId) && { opacity: 0.4 },
                    ]}
                  >
                    {isLoading
                      ? <ActivityIndicator size="small" color={theme.accent} />
                      : <Text style={s.downloadText}>{installed ? Icons.check : Icons.download}</Text>
                    }
                  </TouchableOpacity>
                </View>
              </View>
            );
          })}
        </View>

        {/* ── Botón ir al Chat ── */}
        <ActionButton
          label="→ Ir al Chat"
          onPress={handleGoChat}
          variant="primary"
          style={{ marginTop: 20, marginBottom: 4 }}
        />

        <View style={{ height: 32 }} />
      </ScrollView>
    </View>
  );
}

// ─── Estilos ──────────────────────────────────────────────────────────────────
function createStyles(t) {
  return StyleSheet.create({
    root:   { flex: 1, backgroundColor: t.bg },

    // TopBar
    topBar: {
      paddingTop: 10,
      paddingBottom: 10,
      paddingHorizontal: 14,
      backgroundColor: t.surface,
      borderBottomWidth: 1,
      borderBottomColor: t.border,
      flexDirection: 'row',
      alignItems: 'center',
    },
    backBtn:    { flexDirection: 'row', alignItems: 'center', minWidth: 72 },
    backIcon:   { fontSize: 22, color: t.accent, marginRight: 4, lineHeight: 28 },
    backLabel:  { fontSize: 13, color: t.accent, fontWeight: '500' },
    topBarCenter: { flex: 1, alignItems: 'center' },
    topBarTitle:  { fontSize: 15, fontWeight: '700', color: t.text, letterSpacing: 0.2 },
    topBarRight:  { flexDirection: 'row', alignItems: 'center', gap: 8 },
    switchBtn: {
      paddingHorizontal: 10, paddingVertical: 4,
      borderRadius: 6, borderWidth: 1, borderColor: t.border,
      minWidth: 44, alignItems: 'center', justifyContent: 'center', minHeight: 30,
    },
    switchText: { fontSize: 11, fontWeight: '700', letterSpacing: 0.5 },

    // Scroll
    scroll:        { flex: 1 },
    scrollContent: { paddingHorizontal: 14, paddingTop: 16 },

    // Sección row con botón refresh
    sectionRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 },
    refreshBtn: { fontSize: 16, color: t.accent, fontWeight: '700' },

    // Card base
    card: {
      backgroundColor: t.card,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: t.border,
      padding: 14,
      marginBottom: 4,
    },

    // Modelos
    centerRow:   { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 8 },
    loadingText: { fontSize: 12, color: t.textMuted },
    statusText:  { fontSize: 12, fontWeight: '500' },
    emptyText:   { fontSize: 12, color: t.textMuted, textAlign: 'center', paddingVertical: 8 },

    modelRow: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingVertical: 10,
      gap: 10,
    },
    modelIconBox: {
      width: 36, height: 36, borderRadius: 8,
      backgroundColor: '#1a2a1a',
      borderWidth: 1, borderColor: '#4ade8033',
      alignItems: 'center', justifyContent: 'center',
    },
    modelIcon:   { fontSize: 15, color: '#4ade80' },
    modelName:   { fontSize: 13, fontWeight: '600', color: t.text },
    modelMeta:   { fontSize: 11, color: t.textMuted, marginTop: 1 },
    modelChatBtn: {
      paddingHorizontal: 8, paddingVertical: 4,
      borderRadius: 6, backgroundColor: t.accent + '18',
      borderWidth: 1, borderColor: t.accent + '44',
    },
    modelChatText:  { fontSize: 11, color: t.accent, fontWeight: '600' },
    modelDeleteBtn: {
      width: 32, height: 32,
      borderRadius: 6, backgroundColor: t.surface,
      borderWidth: 1, borderColor: t.border,
      alignItems: 'center', justifyContent: 'center',
    },
    modelDeleteText: { fontSize: 13, color: t.error, fontWeight: '700' },

    // Chips num_ctx
    ctxHint:  { fontSize: 12, color: t.textMuted, marginBottom: 10 },
    chipsRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
    chip: {
      paddingHorizontal: 14, paddingVertical: 7,
      borderRadius: 20, borderWidth: 1, borderColor: t.border,
      backgroundColor: t.surface,
    },
    chipText: { fontSize: 12, color: t.textSecondary, fontWeight: '500', fontFamily: 'monospace' },
    ctxNote:  { fontSize: 11, color: t.textMuted, marginTop: 10 },

    // Presets descarga
    presetRow:     { flexDirection: 'row', alignItems: 'center', paddingVertical: 10, gap: 10 },
    presetNameRow: { flexDirection: 'row', alignItems: 'center', gap: 6 },
    presetName:    { fontSize: 13, fontWeight: '600', color: t.text, fontFamily: 'monospace' },
    presetMeta:    { fontSize: 11, color: t.textMuted, marginTop: 2 },
    presetMsg:     { fontSize: 11, fontWeight: '500', marginTop: 4 },
    installedBadge: {
      paddingHorizontal: 5, paddingVertical: 1,
      borderRadius: 4, backgroundColor: t.success + '22',
      borderWidth: 1, borderColor: t.success + '44',
    },
    installedText: { fontSize: 10, color: t.success, fontWeight: '600' },
    downloadBtn: {
      width: 36, height: 36,
      borderRadius: 8, backgroundColor: t.surface,
      borderWidth: 1, borderColor: t.border,
      alignItems: 'center', justifyContent: 'center',
    },
    downloadText: { fontSize: 15, color: t.accent, fontWeight: '700' },
  });
}
