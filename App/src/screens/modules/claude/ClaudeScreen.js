// src/screens/modules/claude/ClaudeScreen.js — v2.0.0 (S15)
// + Selector de proyectos (crear symlink desde Download / eliminar)
// + Botón "Abrir Terminal" → TerminalModal con xterm.js + WebSocket PTY

import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, ScrollView, TouchableOpacity, StyleSheet,
  ActivityIndicator, Alert, Modal, FlatList,
} from 'react-native';
import { useTheme }      from '../../../theme/ThemeContext';
import { StatusPill }    from '../../../components/StatusPill';
import { InputField }    from '../../../components/InputField';
import { ActionButton }  from '../../../components/ActionButton';
import { SectionLabel }  from '../../../components/SectionLabel';
import { InfoRow }       from '../../../components/InfoRow';
import { Divider }       from '../../../components/Divider';
import { Icons }         from '../../../theme/icons';
import { useStatus }     from '../../../hooks/useStatus';
import { apiFetch }      from '../../../services/api';
import { TerminalModal } from './TerminalModal';

const DEFAULT_ENDPOINT = 'https://api.anthropic.com';
const CLAUDE_VERSION   = '@2.1.111';
const WS_PORT          = 8081;

export function ClaudeScreen({ navigate, goBack }) {
  const { theme }  = useTheme();
  const s          = createStyles(theme);
  const { status } = useStatus();

  // Config
  const [apiKey, setApiKey]               = useState('');
  const [apiKeyDirty, setApiKeyDirty]     = useState(false);
  const [apiKeySaving, setApiKeySaving]   = useState(false);
  const [apiKeyMsg, setApiKeyMsg]         = useState(null);
  const [endpoint, setEndpoint]           = useState(DEFAULT_ENDPOINT);
  const [endpointDirty, setEndpointDirty] = useState(false);
  const [endpointSaving, setEndpointSaving] = useState(false);
  const [endpointMsg, setEndpointMsg]     = useState(null);

  // Proyectos
  const [projects, setProjects]         = useState([]);
  const [projLoading, setProjLoading]   = useState(false);
  const [projErr, setProjErr]           = useState(null);
  const [selectedProj, setSelectedProj] = useState(null);

  // Modal crear symlink
  const [dlDirs, setDlDirs]           = useState([]);
  const [dlLoading, setDlLoading]     = useState(false);
  const [showDlModal, setShowDlModal] = useState(false);
  const [creatingLink, setCreatingLink] = useState(false);

  // Terminal
  const [termVisible, setTermVisible] = useState(false);
  const [termTitle, setTermTitle]     = useState('Terminal');

  const claudeModule = status?.modules?.find(m => m.id === 'claude');
  const pillStatus   = claudeModule?.status ?? 'inactive';
  const hasKey       = !!(status?.claude_cfg?.api_key);
  const deviceIp     = status?.ip ?? '127.0.0.1';
  const wsUrl        = `ws://${deviceIp}:${WS_PORT}`;

  useEffect(() => {
    const cfg = status?.claude_cfg;
    if (!cfg) return;
    if (cfg.api_key && !apiKeyDirty)    setApiKey(cfg.api_key);
    if (cfg.endpoint && !endpointDirty) setEndpoint(cfg.endpoint);
  }, [status]);

  useEffect(() => { loadProjects(); }, []);

  const loadProjects = useCallback(async () => {
    setProjLoading(true); setProjErr(null);
    try {
      const res = await apiFetch('/api/claude/projects');
      const list = res.projects || [];
      setProjects(list);
      if (selectedProj && !list.find(p => p.name === selectedProj.name)) setSelectedProj(null);
    } catch { setProjErr('No se pudieron cargar los proyectos'); }
    finally   { setProjLoading(false); }
  }, [selectedProj]);

  const handleSelectProject = useCallback((proj) => {
    setSelectedProj(prev => prev?.name === proj.name ? null : proj);
  }, []);

  const handleDeleteProject = useCallback((proj) => {
    Alert.alert('Eliminar symlink', `¿Eliminar "${proj.name}"?\nSolo el symlink, no la carpeta original.`, [
      { text: 'Cancelar', style: 'cancel' },
      { text: 'Eliminar', style: 'destructive', onPress: async () => {
        try {
          await apiFetch('/api/claude/project/delete', { method: 'POST', body: JSON.stringify({ name: proj.name }) });
          if (selectedProj?.name === proj.name) setSelectedProj(null);
          loadProjects();
        } catch { Alert.alert('Error', 'No se pudo eliminar'); }
      }},
    ]);
  }, [selectedProj, loadProjects]);

  const openDlModal = useCallback(async () => {
    setShowDlModal(true); setDlLoading(true);
    try {
      const res = await apiFetch('/api/claude/download-dirs');
      setDlDirs(res.dirs || []);
    } catch { setDlDirs([]); }
    finally   { setDlLoading(false); }
  }, []);

  const handleCreateLink = useCallback(async (dirName) => {
    setCreatingLink(true);
    try {
      const res = await apiFetch('/api/claude/project/create', {
        method: 'POST', body: JSON.stringify({ name: dirName }),
      });
      if (res.ok) { setShowDlModal(false); loadProjects(); }
      else Alert.alert('Error', res.msg || 'No se pudo crear');
    } catch { Alert.alert('Error', 'Sin respuesta del dashboard'); }
    finally   { setCreatingLink(false); }
  }, [loadProjects]);

  const handleOpenTerminal = useCallback(() => {
    setTermTitle(selectedProj ? `claude · ${selectedProj.name}` : 'Terminal · bash');
    setTermVisible(true);
  }, [selectedProj]);

  const handleSaveKey = useCallback(async () => {
    if (!apiKey.trim()) { setApiKeyMsg({ ok: false, text: 'Campo vacío' }); return; }
    setApiKeySaving(true); setApiKeyMsg(null);
    try {
      const res = await apiFetch('/api/claude/config', { method: 'POST', body: JSON.stringify({ api_key: apiKey.trim(), endpoint }) });
      setApiKeyMsg({ ok: res.ok, text: res.ok ? 'API key guardada' : (res.msg || 'Error') });
      setApiKeyDirty(false);
    } catch { setApiKeyMsg({ ok: false, text: 'Sin respuesta' }); }
    finally   { setApiKeySaving(false); }
  }, [apiKey, endpoint]);

  const handleSaveEndpoint = useCallback(async () => {
    if (!endpoint.trim()) { setEndpointMsg({ ok: false, text: 'Campo vacío' }); return; }
    setEndpointSaving(true); setEndpointMsg(null);
    try {
      const res = await apiFetch('/api/claude/config', { method: 'POST', body: JSON.stringify({ api_key: apiKey, endpoint: endpoint.trim() }) });
      setEndpointMsg({ ok: res.ok, text: res.ok ? 'Endpoint guardado' : (res.msg || 'Error') });
      setEndpointDirty(false);
    } catch { setEndpointMsg({ ok: false, text: 'Sin respuesta' }); }
    finally   { setEndpointSaving(false); }
  }, [endpoint, apiKey]);

  return (
    <View style={s.root}>
      {/* TopBar */}
      <View style={s.topBar}>
        <TouchableOpacity onPress={goBack} style={s.backBtn} hitSlop={{ top:10,bottom:10,left:10,right:10 }}>
          <Text style={s.backIcon}>{Icons.back}</Text>
          <Text style={s.backLabel}>Módulos</Text>
        </TouchableOpacity>
        <View style={s.topBarCenter}><Text style={s.topBarTitle}>Claude Code</Text></View>
        <StatusPill status={pillStatus} />
      </View>

      <ScrollView style={s.scroll} contentContainerStyle={s.scrollContent}
        keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>

        {/* Botón Terminal */}
        <TouchableOpacity onPress={handleOpenTerminal} style={s.termBtn} activeOpacity={0.8}>
          <View style={s.termBtnIcon}><Text style={s.termBtnGlyph}>&gt;_</Text></View>
          <View style={{ flex: 1 }}>
            <Text style={s.termBtnLabel}>Abrir Terminal</Text>
            <Text style={s.termBtnSub} numberOfLines={1}>
              {selectedProj ? `proyecto: ${selectedProj.name}` : 'shell · directorio actual'}
            </Text>
          </View>
          <Text style={s.termBtnArrow}>{Icons.chevronRight}</Text>
        </TouchableOpacity>

        {/* Proyectos */}
        <View style={s.sectionRow}>
          <SectionLabel>PROYECTOS</SectionLabel>
          <View style={s.sectionBtns}>
            <TouchableOpacity onPress={openDlModal} style={s.pill} hitSlop={{ top:8,bottom:8,left:8,right:8 }}>
              <Text style={s.pillText}>+ Nuevo</Text>
            </TouchableOpacity>
            <TouchableOpacity onPress={loadProjects} style={s.pill} hitSlop={{ top:8,bottom:8,left:8,right:8 }}>
              <Text style={s.pillText}>{Icons.refresh}</Text>
            </TouchableOpacity>
          </View>
        </View>

        <View style={s.card}>
          <Text style={s.hint}>
            Symlinks en <Text style={s.mono}>~/proyectos/</Text> · Toca para seleccionar directorio de trabajo
          </Text>
          {projLoading ? (
            <View style={s.row}><ActivityIndicator size="small" color={theme.accent} /><Text style={s.muted}>Cargando...</Text></View>
          ) : projErr ? (
            <View style={s.rowBetween}>
              <Text style={[s.fb, { color: theme.error }]}>{Icons.error} {projErr}</Text>
              <TouchableOpacity onPress={loadProjects}><Text style={s.link}>{Icons.refresh} Reintentar</Text></TouchableOpacity>
            </View>
          ) : projects.length === 0 ? (
            <View style={s.emptyBox}>
              <Text style={s.muted}>No hay proyectos en ~/proyectos/</Text>
              <TouchableOpacity onPress={openDlModal} style={s.emptyBtn}>
                <Text style={s.pillText}>+ Crear desde Download</Text>
              </TouchableOpacity>
            </View>
          ) : projects.map((proj, i) => {
            const sel = selectedProj?.name === proj.name;
            return (
              <TouchableOpacity key={proj.name} onPress={() => handleSelectProject(proj)} activeOpacity={0.75}
                style={[s.projRow, i > 0 && { borderTopWidth:1, borderTopColor: theme.border }, sel && s.projRowSel]}>
                <View style={[s.selBar, sel && s.selBarOn]} />
                <View style={s.projIconBox}><Text style={[s.projIconGlyph, sel && { color: theme.accent }]}>⎋</Text></View>
                <View style={{ flex:1 }}>
                  <Text style={[s.projName, sel && { color: theme.accent }]}>{proj.name}</Text>
                  {proj.is_symlink && proj.target
                    ? <Text style={s.projTarget} numberOfLines={1}>→ {proj.target}</Text>
                    : null}
                </View>
                {sel && <View style={s.selBadge}><Text style={s.selBadgeText}>{Icons.check} activo</Text></View>}
                <TouchableOpacity onPress={() => handleDeleteProject(proj)} style={s.delBtn} hitSlop={{ top:8,bottom:8,left:8,right:8 }}>
                  <Text style={s.delIcon}>✕</Text>
                </TouchableOpacity>
              </TouchableOpacity>
            );
          })}
        </View>

        {/* API Key */}
        <SectionLabel style={{ marginTop: 20 }}>API KEY</SectionLabel>
        <View style={s.card}>
          <View style={s.row}>
            <Text style={[s.statusDot, { color: hasKey ? theme.success : theme.textMuted }]}>{hasKey ? Icons.check : Icons.dot}</Text>
            <Text style={[s.statusText, { color: hasKey ? theme.success : theme.textMuted }]}>{hasKey ? 'API key configurada' : 'Sin API key'}</Text>
          </View>
          <Divider style={{ marginVertical: 10 }} />
          <InputField label="ANTHROPIC API KEY" value={apiKey}
            onChangeText={v => { setApiKey(v); setApiKeyDirty(true); setApiKeyMsg(null); }}
            placeholder="sk-ant-..." secureTextEntry />
          {apiKeyMsg && <Text style={[s.fb, { color: apiKeyMsg.ok ? theme.success : theme.error, marginTop:6 }]}>{apiKeyMsg.ok ? `${Icons.check} ` : `${Icons.error} `}{apiKeyMsg.text}</Text>}
          <ActionButton label="Guardar API key" onPress={handleSaveKey} state={apiKeySaving ? 'loading' : 'idle'} variant="primary" style={{ marginTop:10 }} />
        </View>

        {/* Endpoint */}
        <SectionLabel style={{ marginTop: 20 }}>ENDPOINT</SectionLabel>
        <View style={s.card}>
          <InputField label="URL BASE" value={endpoint}
            onChangeText={v => { setEndpoint(v); setEndpointDirty(true); setEndpointMsg(null); }}
            placeholder={DEFAULT_ENDPOINT} />
          <Text style={s.monoHint}>Default: {DEFAULT_ENDPOINT}</Text>
          {endpointMsg && <Text style={[s.fb, { color: endpointMsg.ok ? theme.success : theme.error, marginTop:6 }]}>{endpointMsg.ok ? `${Icons.check} ` : `${Icons.error} `}{endpointMsg.text}</Text>}
          <ActionButton label="Guardar endpoint" onPress={handleSaveEndpoint} state={endpointSaving ? 'loading' : 'idle'} variant="primary" style={{ marginTop:10 }} />
        </View>

        {/* Info técnica */}
        <SectionLabel style={{ marginTop: 20 }}>INFO TÉCNICA</SectionLabel>
        <View style={s.card}>
          <InfoRow label="Versión"      value={CLAUDE_VERSION} />
          <InfoRow label="Entorno"      value="Termux nativo · Bionic libc" />
          <InfoRow label="Arquitectura" value="ARM64 (aarch64)" />
          <InfoRow label="WS Terminal"  value={`ws://${deviceIp}:${WS_PORT}`} />
          <InfoRow label="Fix versión"  value=">2.1.111 usa binario nativo incompatible con Bionic" valueColor={theme.warning} />
          <InfoRow label="Comando"      value="claude" isLast />
        </View>

        <View style={{ height: 32 }} />
      </ScrollView>

      {/* Modal: Crear symlink */}
      <Modal visible={showDlModal} transparent animationType="slide" onRequestClose={() => setShowDlModal(false)}>
        <View style={s.dlOverlay}>
          <View style={s.dlPanel}>
            <View style={s.dlHeader}>
              <Text style={s.dlTitle}>Crear symlink desde Download</Text>
              <TouchableOpacity onPress={() => setShowDlModal(false)} hitSlop={{ top:10,bottom:10,left:10,right:10 }}>
                <Text style={s.dlClose}>{Icons.close}</Text>
              </TouchableOpacity>
            </View>
            <Text style={s.dlSub}>Carpetas en <Text style={s.mono}>/sdcard/Download/</Text></Text>
            {dlLoading ? (
              <View style={[s.row, { padding:24 }]}><ActivityIndicator size="small" color={theme.accent} /><Text style={s.muted}>Cargando...</Text></View>
            ) : dlDirs.length === 0 ? (
              <Text style={[s.muted, { padding:20, textAlign:'center' }]}>No hay carpetas en Download</Text>
            ) : (
              <FlatList data={dlDirs} keyExtractor={i => i} style={{ maxHeight:340 }}
                renderItem={({ item }) => {
                  const linked = projects.some(p => p.name === item);
                  return (
                    <TouchableOpacity onPress={() => !linked && handleCreateLink(item)}
                      disabled={linked || creatingLink}
                      style={[s.dlRow, linked && { opacity:0.4 }]}>
                      <Text style={{ fontSize:18 }}>📁</Text>
                      <View style={{ flex:1 }}>
                        <Text style={s.dlDirName}>{item}</Text>
                        {linked && <Text style={[s.hint, { color: theme.success }]}>ya existe symlink</Text>}
                      </View>
                      {creatingLink ? <ActivityIndicator size="small" color={theme.accent} />
                        : !linked ? <Text style={s.dlArrow}>+</Text>
                        : <Text style={[s.dlArrow, { color: theme.success }]}>{Icons.check}</Text>}
                    </TouchableOpacity>
                  );
                }}
              />
            )}
          </View>
        </View>
      </Modal>

      {/* Terminal */}
      <TerminalModal visible={termVisible} onClose={() => setTermVisible(false)} wsUrl={wsUrl} title={termTitle} projectDir={selectedProj?.name || ''} />
    </View>
  );
}

function createStyles(t) {
  return StyleSheet.create({
    root:   { flex:1, backgroundColor: t.bg },
    topBar: { paddingTop:10, paddingBottom:10, paddingHorizontal:14, backgroundColor: t.surface, borderBottomWidth:1, borderBottomColor: t.border, flexDirection:'row', alignItems:'center' },
    backBtn: { flexDirection:'row', alignItems:'center', minWidth:72 },
    backIcon: { fontSize:22, color: t.accent, marginRight:4, lineHeight:28 },
    backLabel: { fontSize:13, color: t.accent, fontWeight:'500' },
    topBarCenter: { flex:1, alignItems:'center' },
    topBarTitle: { fontSize:15, fontWeight:'700', color: t.text, letterSpacing:0.2 },
    scroll: { flex:1 },
    scrollContent: { paddingHorizontal:14, paddingTop:16 },

    termBtn: { flexDirection:'row', alignItems:'center', backgroundColor: t.card, borderRadius:12, borderWidth:1, borderColor:'rgba(212,160,39,0.35)', padding:14, marginBottom:20, gap:12 },
    termBtnIcon: { width:44, height:44, borderRadius:10, backgroundColor:'#1a1400', borderWidth:1, borderColor:'rgba(212,160,39,0.3)', alignItems:'center', justifyContent:'center' },
    termBtnGlyph: { fontSize:14, color:'#d4a027', fontFamily:'monospace', fontWeight:'700' },
    termBtnLabel: { fontSize:15, fontWeight:'700', color: t.text },
    termBtnSub:   { fontSize:11, color: t.textMuted, marginTop:2, fontFamily:'monospace' },
    termBtnArrow: { fontSize:18, color:'#d4a027', fontWeight:'700' },

    sectionRow: { flexDirection:'row', alignItems:'center', justifyContent:'space-between', marginBottom:6 },
    sectionBtns: { flexDirection:'row', gap:6 },
    pill: { paddingHorizontal:10, paddingVertical:4, backgroundColor: t.surface, borderRadius:6, borderWidth:1, borderColor: t.border },
    pillText: { fontSize:12, color: t.accent, fontWeight:'600' },

    card: { backgroundColor: t.card, borderRadius:12, borderWidth:1, borderColor: t.border, padding:14, marginBottom:4 },
    hint: { fontSize:11, color: t.textMuted, marginBottom:10, lineHeight:16 },
    mono: { fontFamily:'monospace', color: t.textSecondary },
    monoHint: { fontSize:11, color: t.textMuted, marginTop:6, fontFamily:'monospace' },
    row: { flexDirection:'row', alignItems:'center', gap:8, paddingVertical:6 },
    rowBetween: { flexDirection:'row', alignItems:'center', justifyContent:'space-between', paddingVertical:6 },
    muted: { fontSize:12, color: t.textMuted },
    fb:    { fontSize:12, fontWeight:'500' },
    link:  { fontSize:12, color: t.accent, fontWeight:'500' },
    emptyBox: { alignItems:'center', paddingVertical:16, gap:10 },
    emptyBtn: { paddingHorizontal:14, paddingVertical:7, backgroundColor: t.surface, borderRadius:8, borderWidth:1, borderColor: t.border },

    projRow: { flexDirection:'row', alignItems:'center', paddingVertical:11, gap:10, borderRadius:8 },
    projRowSel: { backgroundColor:'rgba(212,160,39,0.07)', borderRadius:8, paddingHorizontal:6, marginHorizontal:-6 },
    selBar: { width:3, height:32, borderRadius:2, backgroundColor:'transparent' },
    selBarOn: { backgroundColor:'#d4a027' },
    projIconBox: { width:34, height:34, borderRadius:8, backgroundColor: t.surface, borderWidth:1, borderColor: t.border, alignItems:'center', justifyContent:'center' },
    projIconGlyph: { fontSize:14, color: t.textMuted },
    projName:   { fontSize:13, fontWeight:'600', color: t.text },
    projTarget: { fontSize:10, color: t.textMuted, fontFamily:'monospace', marginTop:1 },
    selBadge:  { paddingHorizontal:6, paddingVertical:2, backgroundColor:'rgba(212,160,39,0.15)', borderRadius:4, borderWidth:1, borderColor:'rgba(212,160,39,0.35)' },
    selBadgeText: { fontSize:10, color:'#d4a027', fontWeight:'700' },
    delBtn: { width:28, height:28, borderRadius:6, backgroundColor: t.surface, borderWidth:1, borderColor: t.border, alignItems:'center', justifyContent:'center' },
    delIcon: { fontSize:11, color: t.error, fontWeight:'700' },

    statusDot:  { fontSize:16, lineHeight:22 },
    statusText: { fontSize:13, fontWeight:'500' },

    dlOverlay: { flex:1, backgroundColor:'rgba(0,0,0,0.75)', justifyContent:'flex-end' },
    dlPanel: { backgroundColor: t.surface, borderTopLeftRadius:16, borderTopRightRadius:16, borderTopWidth:1, borderColor: t.border, paddingBottom:24 },
    dlHeader: { flexDirection:'row', alignItems:'center', justifyContent:'space-between', paddingHorizontal:16, paddingVertical:14, borderBottomWidth:1, borderBottomColor: t.border },
    dlTitle:  { fontSize:14, fontWeight:'700', color: t.text },
    dlClose:  { fontSize:18, color: t.textMuted, fontWeight:'700' },
    dlSub:    { fontSize:12, color: t.textMuted, paddingHorizontal:16, paddingVertical:8 },
    dlRow:    { flexDirection:'row', alignItems:'center', gap:10, paddingHorizontal:16, paddingVertical:12, borderBottomWidth:1, borderBottomColor: t.border },
    dlDirName: { fontSize:13, fontWeight:'600', color: t.text },
    dlArrow:   { fontSize:16, color: t.accent, fontWeight:'700' },
  });
}
