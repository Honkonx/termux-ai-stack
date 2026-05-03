// src/screens/modules/ModulesScreen.js — v2.0.0
import React, { useCallback } from 'react';
import {
  View, Text, ScrollView, TouchableOpacity,
  RefreshControl, StyleSheet, Platform,
} from 'react-native';
import { useTheme } from '../../theme/ThemeContext';
import { useStatus } from '../../hooks/useStatus';
import { useAction } from '../../hooks/useAction';
import { OfflineScreen } from '../../components/OfflineScreen';
import { ModuleIcon } from '../../components/ModuleIcon';
import { StatusPill } from '../../components/StatusPill';
import { ROUTES } from '../../navigation/routes';

// ─── Helpers ─────────────────────────────────────────────────

function getModuleStatus(mod) {
  if (!mod || !mod.installed) return 'inactive';
  if (mod.running === true)   return 'active';
  if (mod.running === false)  return 'ready';
  return 'ready';
}

function formatRam(ram) {
  if (!ram) return '…';
  const mb = ram.available_mb;
  if (mb >= 1024) return `${(mb / 1024).toFixed(1)}GB`;
  return `${mb}MB`;
}

// ─── ModuleRow ───────────────────────────────────────────────

function ModuleRow({ mod, onSubMenu, onToggle, actionState, theme }) {
  const s      = rowStyles(theme);
  const status = getModuleStatus(mod);
  const hasMenu = mod.installed &&
    ['n8n', 'ollama', 'claude', 'ssh', 'python'].includes(mod.id);
  const isService = mod.running !== undefined;

  return (
    <View style={s.card}>
      <ModuleIcon id={mod.id} size={42} />
      <View style={s.info}>
        <Text style={s.name}>{mod.name}</Text>
        {mod.version ? <Text style={s.ver}>v{mod.version}</Text> : null}
      </View>
      <View style={s.right}>
        <StatusPill status={status} />
        {isService && mod.installed ? (
          <TouchableOpacity
            style={[s.toggle, mod.running ? s.toggleOn : s.toggleOff,
              actionState === 'loading' && s.disabled]}
            onPress={() => onToggle(mod.running ? 'stop' : 'start')}
            activeOpacity={0.75}
            disabled={actionState === 'loading'}
          >
            <View style={[s.thumb, mod.running && s.thumbOn]} />
          </TouchableOpacity>
        ) : !mod.installed ? (
          <View style={s.badge}>
            <Text style={s.badgeText}>no inst.</Text>
          </View>
        ) : null}
        {hasMenu ? (
          <TouchableOpacity style={s.menuBtn} onPress={onSubMenu} activeOpacity={0.75}>
            <Text style={s.menuIcon}>›</Text>
          </TouchableOpacity>
        ) : null}
      </View>
    </View>
  );
}

function rowStyles(t) {
  return StyleSheet.create({
    card:     { flexDirection:'row', alignItems:'center', backgroundColor:t.card,
                borderWidth:1, borderColor:t.border, borderRadius:10,
                paddingHorizontal:12, paddingVertical:12, marginBottom:8, gap:10 },
    info:     { flex:1 },
    name:     { fontSize:14, fontWeight:'600', color:t.textPrimary },
    ver:      { fontSize:11, color:t.textMuted, marginTop:2 },
    right:    { flexDirection:'row', alignItems:'center', gap:8 },
    toggle:   { width:40, height:22, borderRadius:11, justifyContent:'center', paddingHorizontal:2 },
    toggleOn: { backgroundColor:t.success },
    toggleOff:{ backgroundColor:t.overlay, borderWidth:1, borderColor:t.border },
    disabled: { opacity:0.5 },
    thumb:    { width:18, height:18, borderRadius:9, backgroundColor:t.textMuted },
    thumbOn:  { backgroundColor:'#fff', alignSelf:'flex-end' },
    menuBtn:  { width:32, height:32, borderRadius:8, backgroundColor:t.overlay,
                borderWidth:1, borderColor:t.border, alignItems:'center', justifyContent:'center' },
    menuIcon: { fontSize:20, color:t.accent, fontWeight:'700', lineHeight:24 },
    badge:    { paddingHorizontal:7, paddingVertical:3, borderRadius:6,
                borderWidth:1, borderColor:t.border },
    badgeText:{ fontSize:10, fontWeight:'600', color:t.textMuted },
  });
}

// ─── ModulesScreen ───────────────────────────────────────────

const ORDER = ['n8n', 'claude', 'ollama', 'ssh', 'eas', 'python'];

export function ModulesScreen({ navigate }) {
  const { theme }             = useTheme();
  const { status, connErr }   = useStatus();
  const n8nA    = useAction('n8n');
  const ollamaA = useAction('ollama');
  const sshA    = useAction('ssh');
  const s       = createStyles(theme);

  const actionFor = (id) => ({ n8n: n8nA, ollama: ollamaA, ssh: sshA }[id]
    || { actionState:'idle', trigger:()=>{} });

  const handleSubMenu = useCallback((id) => {
    const r = { n8n:ROUTES.N8N, ollama:ROUTES.OLLAMA, claude:ROUTES.CLAUDE, ssh:ROUTES.SSH, python:ROUTES.PYTHON }[id];
    if (r) navigate(r);
  }, [navigate]);

  if (connErr && !status) return <OfflineScreen onRetry={() => {}} />;

  const modules = status?.modules || [];
  const modMap  = Object.fromEntries(modules.map(m => [m.id, m]));
  const ram     = formatRam(status?.ram);
  const ip      = status?.ip || '…';

  return (
    <ScrollView style={s.root} contentContainerStyle={s.content}
      refreshControl={<RefreshControl refreshing={false} onRefresh={()=>{}} tintColor={theme.accent} />}
    >
      {/* Header sistema */}
      <View style={s.header}>
        <Text style={s.hTitle}>{status ? '● ' : '○ '}TERMUX·AI·STACK</Text>
        <Text style={s.hMeta}>RAM: {ram}{'  '}IP: {ip}</Text>
      </View>

      <Text style={s.label}>MÓDULOS</Text>

      {ORDER.map(id => {
        const mod = modMap[id];
        if (!mod) return null;
        const { actionState, trigger } = actionFor(id);
        return (
          <ModuleRow
            key={id}
            mod={mod}
            theme={theme}
            actionState={actionState}
            onToggle={(action) => trigger(action)}
            onSubMenu={() => handleSubMenu(id)}
          />
        );
      })}

      <Text style={[s.label, { marginTop: 20 }]}>SISTEMA</Text>

      {/* Backup card */}
      <View style={s.card}>
        <ModuleIcon id="backup" size={42} />
        <View style={{ flex:1 }}>
          <Text style={s.name}>Backup / Restore</Text>
          <Text style={s.ver}>sdcard</Text>
        </View>
        <TouchableOpacity style={s.menuBtn} activeOpacity={0.75}>
          <Text style={s.menuIcon}>›</Text>
        </TouchableOpacity>
      </View>

      <View style={{ height: 24 }} />
    </ScrollView>
  );
}

function createStyles(t) {
  return StyleSheet.create({
    root:    { flex:1, backgroundColor:t.bg },
    content: { padding:14, paddingTop: Platform.OS === 'android' ? 10 : 16 },
    header:  { backgroundColor:t.surface, borderWidth:1, borderColor:t.border,
               borderRadius:10, padding:12, marginBottom:16 },
    hTitle:  { fontSize:12, fontWeight:'700', color:t.textCode, letterSpacing:1,
               fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New' },
    hMeta:   { fontSize:11, color:t.textSecond, marginTop:3,
               fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New' },
    label:   { fontSize:10, fontWeight:'700', letterSpacing:1.2, textTransform:'uppercase',
               color:t.textMuted, marginBottom:8 },
    card:    { flexDirection:'row', alignItems:'center', backgroundColor:t.card,
               borderWidth:1, borderColor:t.border, borderRadius:10,
               paddingHorizontal:12, paddingVertical:12, marginBottom:8, gap:10 },
    name:    { fontSize:14, fontWeight:'600', color:t.textPrimary },
    ver:     { fontSize:11, color:t.textMuted, marginTop:2 },
    menuBtn: { width:32, height:32, borderRadius:8, backgroundColor:t.overlay,
               borderWidth:1, borderColor:t.border, alignItems:'center', justifyContent:'center' },
    menuIcon:{ fontSize:20, color:t.accent, fontWeight:'700', lineHeight:24 },
  });
}
