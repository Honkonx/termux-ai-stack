// src/screens/modules/claude/ClaudeScreen.js — v1.0.0 (S14)
// SURFACE:   bg raíz + surface topBar + card sections. Tono ámbar para acento Claude.
// JERARQUÍA: topBarTitle(lg/700) > sectionLabel(xs/700/UPPER) > label(sm/600) > value(base/400)
// ACENTO:    #d4a027 (ámbar Claude) — solo en StatusPill, íconos de estado, bordes activos
// BORDES:    1px rgba — nunca hex sólido. cards sin sombra, border sutil
// DENSIDAD:  Media — pantalla de configuración, no urgencia, pero campos claros y táctiles

import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  View, Text, ScrollView, TouchableOpacity,
  StyleSheet, ActivityIndicator, FlatList,
} from 'react-native';
import { useTheme } from '../../../theme/ThemeContext';
import { StatusPill } from '../../../components/StatusPill';
import { InputField } from '../../../components/InputField';
import { ActionButton } from '../../../components/ActionButton';
import { SectionLabel } from '../../../components/SectionLabel';
import { InfoRow } from '../../../components/InfoRow';
import { Divider } from '../../../components/Divider';
import { Icons } from '../../../theme/icons';
import { useStatus } from '../../../hooks/useStatus';
import { apiFetch } from '../../../services/api';

// ─── Constantes ──────────────────────────────────────────────────────────────
const DEFAULT_ENDPOINT = 'https://api.anthropic.com';
const CLAUDE_VERSION   = '@2.1.111';

// ─── Componente principal ─────────────────────────────────────────────────────
export function ClaudeScreen({ navigate, goBack }) {
  const { theme }         = useTheme();
  const s                 = createStyles(theme);
  const { status }        = useStatus();

  // API Key
  const [apiKey, setApiKey]           = useState('');
  const [apiKeyDirty, setApiKeyDirty] = useState(false);
  const [apiKeySaving, setApiKeySaving] = useState(false);
  const [apiKeyMsg, setApiKeyMsg]     = useState(null); // { ok, text }

  // Endpoint
  const [endpoint, setEndpoint]         = useState(DEFAULT_ENDPOINT);
  const [endpointDirty, setEndpointDirty] = useState(false);
  const [endpointSaving, setEndpointSaving] = useState(false);
  const [endpointMsg, setEndpointMsg]   = useState(null);

  // Proyectos
  const [projects, setProjects]       = useState([]);
  const [projLoading, setProjLoading] = useState(false);
  const [projExpanded, setProjExpanded] = useState(false);
  const [projErr, setProjErr]         = useState(null);

  // Precarga desde status
  useEffect(() => {
    const cfg = status?.claude_cfg;
    if (!cfg) return;
    if (cfg.api_key && !apiKeyDirty)  setApiKey(cfg.api_key);
    if (cfg.endpoint && !endpointDirty) setEndpoint(cfg.endpoint);
  }, [status]);

  // ── Handlers API Key ─────────────────────────────────────────────
  const handleSaveKey = useCallback(async () => {
    if (!apiKey.trim()) {
      setApiKeyMsg({ ok: false, text: 'Campo vacío' });
      return;
    }
    setApiKeySaving(true);
    setApiKeyMsg(null);
    try {
      const res = await apiFetch('/api/claude/config', {
        method: 'POST',
        body: JSON.stringify({ api_key: apiKey.trim(), endpoint }),
      });
      setApiKeyMsg({ ok: res.ok, text: res.ok ? 'API key guardada' : (res.msg || 'Error al guardar') });
      setApiKeyDirty(false);
    } catch {
      setApiKeyMsg({ ok: false, text: 'Sin respuesta del dashboard' });
    } finally {
      setApiKeySaving(false);
    }
  }, [apiKey, endpoint]);

  // ── Handlers Endpoint ────────────────────────────────────────────
  const handleSaveEndpoint = useCallback(async () => {
    if (!endpoint.trim()) {
      setEndpointMsg({ ok: false, text: 'Campo vacío' });
      return;
    }
    setEndpointSaving(true);
    setEndpointMsg(null);
    try {
      const res = await apiFetch('/api/claude/config', {
        method: 'POST',
        body: JSON.stringify({ api_key: apiKey, endpoint: endpoint.trim() }),
      });
      setEndpointMsg({ ok: res.ok, text: res.ok ? 'Endpoint guardado' : (res.msg || 'Error al guardar') });
      setEndpointDirty(false);
    } catch {
      setEndpointMsg({ ok: false, text: 'Sin respuesta del dashboard' });
    } finally {
      setEndpointSaving(false);
    }
  }, [endpoint, apiKey]);

  // ── Proyectos ────────────────────────────────────────────────────
  const loadProjects = useCallback(async () => {
    setProjLoading(true);
    setProjErr(null);
    try {
      const res = await apiFetch('/api/claude/projects');
      setProjects(res.projects || []);
    } catch {
      setProjErr('No se pudieron cargar los proyectos');
    } finally {
      setProjLoading(false);
    }
  }, []);

  const toggleProjects = useCallback(() => {
    if (!projExpanded && projects.length === 0) loadProjects();
    setProjExpanded(v => !v);
  }, [projExpanded, projects.length, loadProjects]);

  // ── Estado de módulo claude ──────────────────────────────────────
  const claudeModule = status?.modules?.find(m => m.id === 'claude');
  const pillStatus   = claudeModule?.status ?? 'inactive';
  const hasKey       = !!(status?.claude_cfg?.api_key);

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
          <Text style={s.topBarTitle}>Claude Code</Text>
        </View>
        <StatusPill status={pillStatus} />
      </View>

      <ScrollView
        style={s.scroll}
        contentContainerStyle={s.scrollContent}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        {/* ── Sección 1: API Key ── */}
        <SectionLabel>API KEY</SectionLabel>
        <View style={s.card}>
          {/* Estado actual */}
          <View style={s.keyStatusRow}>
            <Text style={[s.keyStatusDot, { color: hasKey ? theme.success : theme.textMuted }]}>
              {hasKey ? Icons.check : Icons.dot}
            </Text>
            <Text style={[s.keyStatusText, { color: hasKey ? theme.success : theme.textMuted }]}>
              {hasKey ? 'API key configurada' : 'Sin API key'}
            </Text>
          </View>
          <Divider style={{ marginVertical: 12 }} />
          <InputField
            label="ANTHROPIC API KEY"
            value={apiKey}
            onChangeText={v => { setApiKey(v); setApiKeyDirty(true); setApiKeyMsg(null); }}
            placeholder="sk-ant-..."
            secureTextEntry
          />
          {apiKeyMsg && (
            <Text style={[s.feedbackText, { color: apiKeyMsg.ok ? theme.success : theme.error }]}>
              {apiKeyMsg.ok ? `${Icons.check} ` : `${Icons.error} `}{apiKeyMsg.text}
            </Text>
          )}
          <ActionButton
            label="Guardar API key"
            onPress={handleSaveKey}
            state={apiKeySaving ? 'loading' : 'idle'}
            variant="primary"
            style={{ marginTop: 10 }}
          />
        </View>

        {/* ── Sección 2: Endpoint ── */}
        <SectionLabel style={{ marginTop: 20 }}>ENDPOINT</SectionLabel>
        <View style={s.card}>
          <InputField
            label="URL BASE"
            value={endpoint}
            onChangeText={v => { setEndpoint(v); setEndpointDirty(true); setEndpointMsg(null); }}
            placeholder={DEFAULT_ENDPOINT}
          />
          <Text style={s.endpointHint}>
            Default: {DEFAULT_ENDPOINT}
          </Text>
          {endpointMsg && (
            <Text style={[s.feedbackText, { color: endpointMsg.ok ? theme.success : theme.error }]}>
              {endpointMsg.ok ? `${Icons.check} ` : `${Icons.error} `}{endpointMsg.text}
            </Text>
          )}
          <ActionButton
            label="Guardar endpoint"
            onPress={handleSaveEndpoint}
            state={endpointSaving ? 'loading' : 'idle'}
            variant="primary"
            style={{ marginTop: 10 }}
          />
        </View>

        {/* ── Sección 3: Proyectos ── */}
        <SectionLabel style={{ marginTop: 20 }}>PROYECTOS</SectionLabel>
        <View style={s.card}>
          <View style={s.projHeader}>
            <View style={{ flex: 1 }}>
              <Text style={s.projHint}>
                Symlinks a carpetas de{' '}
                <Text style={s.monoInline}>/sdcard/Download/</Text>
              </Text>
              <Text style={s.projHint2}>Ruta: ~/proyectos/</Text>
            </View>
            <TouchableOpacity onPress={toggleProjects} style={s.projToggleBtn} hitSlop={{ top:8, bottom:8, left:8, right:8 }}>
              <Text style={s.projToggleText}>
                {projExpanded ? 'Cerrar' : 'Ver proyectos'} {projExpanded ? Icons.chevronDown : Icons.chevronRight}
              </Text>
            </TouchableOpacity>
          </View>

          {projExpanded && (
            <>
              <Divider style={{ marginTop: 10, marginBottom: 8 }} />
              {projLoading ? (
                <View style={s.projLoadingRow}>
                  <ActivityIndicator size="small" color={theme.accent} />
                  <Text style={s.projLoadingText}>Cargando...</Text>
                </View>
              ) : projErr ? (
                <View style={s.projErrRow}>
                  <Text style={[s.feedbackText, { color: theme.error }]}>
                    {Icons.error} {projErr}
                  </Text>
                  <TouchableOpacity onPress={loadProjects} hitSlop={{ top:8, bottom:8, left:8, right:8 }}>
                    <Text style={s.projRetry}>{Icons.refresh} Reintentar</Text>
                  </TouchableOpacity>
                </View>
              ) : projects.length === 0 ? (
                <Text style={s.projEmpty}>No hay proyectos en ~/proyectos/</Text>
              ) : (
                projects.map((proj, i) => (
                  <View key={proj.name} style={[s.projRow, i > 0 && { borderTopWidth: 1, borderTopColor: theme.border }]}>
                    <View style={s.projIconBox}>
                      <Text style={s.projIcon}>⎋</Text>
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={s.projName}>{proj.name}</Text>
                      {proj.is_symlink && (
                        <Text style={s.projTarget} numberOfLines={1}>
                          → {proj.target}
                        </Text>
                      )}
                    </View>
                    {proj.is_symlink && (
                      <View style={s.projBadge}>
                        <Text style={s.projBadgeText}>link</Text>
                      </View>
                    )}
                  </View>
                ))
              )}
              <TouchableOpacity onPress={loadProjects} style={s.refreshRow} hitSlop={{ top:6, bottom:6, left:6, right:6 }}>
                <Text style={s.refreshText}>{Icons.refresh} Actualizar lista</Text>
              </TouchableOpacity>
            </>
          )}
        </View>

        {/* ── Sección 4: Info técnica ── */}
        <SectionLabel style={{ marginTop: 20 }}>INFO TÉCNICA</SectionLabel>
        <View style={s.card}>
          <InfoRow label="Versión"       value={CLAUDE_VERSION} />
          <InfoRow label="Entorno"       value="Termux nativo · Bionic libc" />
          <InfoRow label="Arquitectura"  value="ARM64 (aarch64)" />
          <InfoRow label="Puerto"        value="N/A (proceso en terminal)" />
          <InfoRow label="Fix versión"   value=">2.1.111 usa binario nativo incompatible con Bionic" valueColor={theme.warning} />
          <InfoRow label="Comando"       value="claude" isLast />
        </View>

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
    backBtn:   { flexDirection: 'row', alignItems: 'center', minWidth: 72 },
    backIcon:  { fontSize: 22, color: t.accent, marginRight: 4, lineHeight: 28 },
    backLabel: { fontSize: 13, color: t.accent, fontWeight: '500' },
    topBarCenter: { flex: 1, alignItems: 'center' },
    topBarTitle:  { fontSize: 15, fontWeight: '700', color: t.text, letterSpacing: 0.2 },

    // Scroll
    scroll:        { flex: 1 },
    scrollContent: { paddingHorizontal: 14, paddingTop: 16 },

    // Card base
    card: {
      backgroundColor: t.card,
      borderRadius: 12,
      borderWidth: 1,
      borderColor: t.border,
      padding: 14,
      marginBottom: 4,
    },

    // API Key — estado
    keyStatusRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
    keyStatusDot:  { fontSize: 16, lineHeight: 22 },
    keyStatusText: { fontSize: 13, fontWeight: '500' },

    // Endpoint hint
    endpointHint:  { fontSize: 11, color: t.textMuted, marginTop: 6, fontFamily: 'monospace' },

    // Feedback inline
    feedbackText: { fontSize: 12, fontWeight: '500', marginTop: 8 },

    // Proyectos
    projHeader:     { flexDirection: 'row', alignItems: 'center', gap: 10 },
    projHint:       { fontSize: 12, color: t.textMuted, lineHeight: 18 },
    projHint2:      { fontSize: 11, color: t.textMuted, marginTop: 2, fontFamily: 'monospace' },
    monoInline:     { fontFamily: 'monospace', color: t.textSecondary },
    projToggleBtn:  { paddingHorizontal: 10, paddingVertical: 6, backgroundColor: t.surface,
                      borderRadius: 6, borderWidth: 1, borderColor: t.border },
    projToggleText: { fontSize: 12, color: t.accent, fontWeight: '600' },

    projLoadingRow: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 8 },
    projLoadingText:{ fontSize: 12, color: t.textMuted },
    projErrRow:     { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 4 },
    projRetry:      { fontSize: 12, color: t.accent, fontWeight: '500' },
    projEmpty:      { fontSize: 12, color: t.textMuted, paddingVertical: 8, textAlign: 'center' },

    projRow: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingVertical: 10,
      gap: 10,
    },
    projIconBox: {
      width: 32, height: 32, borderRadius: 8,
      backgroundColor: t.surface,
      borderWidth: 1, borderColor: t.border,
      alignItems: 'center', justifyContent: 'center',
    },
    projIcon:   { fontSize: 14, color: t.accent },
    projName:   { fontSize: 13, fontWeight: '600', color: t.text },
    projTarget: { fontSize: 11, color: t.textMuted, fontFamily: 'monospace', marginTop: 1 },
    projBadge:  {
      paddingHorizontal: 6, paddingVertical: 2,
      borderRadius: 4, backgroundColor: t.surface,
      borderWidth: 1, borderColor: t.border,
    },
    projBadgeText: { fontSize: 10, color: t.textMuted, fontWeight: '600', letterSpacing: 0.5 },

    refreshRow: { paddingTop: 10, alignItems: 'flex-end' },
    refreshText:{ fontSize: 12, color: t.accent, fontWeight: '500' },
  });
}
