// src/screens/modules/n8n/N8nScreen.js — v2.1.1
// Fix: campos correctos del dashboard (url/cf_mode/webhook_url)
// Header: sin compensación sbHeight propia — App.js ya lo maneja globalmente
import React, { useState, useEffect } from 'react';
import {
  View, Text, ScrollView, TouchableOpacity,
  Switch, StyleSheet, Alert, Clipboard,
} from 'react-native';
import { useTheme }     from '../../../theme/ThemeContext';
import { useStatus }    from '../../../hooks/useStatus';
import { useAction }    from '../../../hooks/useAction';
import { InputField }   from '../../../components/InputField';
import { ActionButton } from '../../../components/ActionButton';
import { StatusPill }   from '../../../components/StatusPill';
import { SectionLabel } from '../../../components/SectionLabel';
import { Divider }      from '../../../components/Divider';
import { InfoRow }      from '../../../components/InfoRow';
import { CodeBox }      from '../../../components/CodeBox';
import { LogsModal }    from '../../logs/LogsModal';
import { getN8nInfo, postN8nToken, postN8nWebhook } from '../../../services/dashboard';

// ─── Helper ──────────────────────────────────────────────────

function getModStatus(mod) {
  if (!mod || !mod.installed) return 'inactive';
  if (mod.running === true)   return 'active';
  return 'ready';
}

// ─── N8nScreen ───────────────────────────────────────────────

export function N8nScreen({ goBack }) {
  const { theme }                = useTheme();
  const { status }               = useStatus();
  const { actionState, trigger } = useAction('n8n');
  const s = createStyles(theme);

  const mod = status?.modules?.find(m => m.id === 'n8n');

  const [n8nInfo, setN8nInfo]         = useState(null);
  const [token, setToken]             = useState('');
  const [tokenMsg, setTokenMsg]       = useState('');
  const [webhook, setWebhook]         = useState('');
  const [webhookMsg, setWebhookMsg]   = useState('');
  const [logsVisible, setLogsVisible] = useState(false);
  const [saving, setSaving]           = useState(false);

  useEffect(() => { loadInfo(); }, []);

  // Recargar URL cuando n8n se activa — cloudflared tarda ~3s en generar URL
  useEffect(() => {
    if (mod?.running) {
      const t = setTimeout(loadInfo, 3500);
      return () => clearTimeout(t);
    }
  }, [mod?.running]);

  const loadInfo = async () => {
    try {
      const data = await getN8nInfo();
      // /api/n8n/info devuelve: { url, cf_mode, webhook_url }
      // cf_mode: "fija" (con token) | "temporal" (free/sin token)
      setN8nInfo(data);
      if (data?.webhook_url && !webhook) setWebhook(data.webhook_url);
    } catch { /* dashboard offline */ }
  };

  // ── Token ─────────────────────────────────────────────────

  const handleSaveToken = async () => {
    if (!token.trim()) return;
    setSaving(true);
    try {
      await postN8nToken(token.trim());
      setTokenMsg('✓ Guardado — reinicia n8n para aplicar');
      setToken('');
      setTimeout(() => { setTokenMsg(''); loadInfo(); }, 3500);
    } catch {
      setTokenMsg('✗ Error al guardar');
      setTimeout(() => setTokenMsg(''), 3000);
    } finally { setSaving(false); }
  };

  const handleRemoveToken = () => {
    Alert.alert(
      'Quitar token',
      'n8n usará URL temporal gratuita. Cambia cada vez que reinicias.',
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Quitar', style: 'destructive',
          onPress: async () => {
            setSaving(true);
            try {
              await postN8nToken('', true);
              setTokenMsg('✓ Token eliminado — modo free activo');
              setTimeout(() => { setTokenMsg(''); loadInfo(); }, 3000);
            } catch {
              setTokenMsg('✗ Error al quitar');
              setTimeout(() => setTokenMsg(''), 3000);
            } finally { setSaving(false); }
          },
        },
      ]
    );
  };

  // ── Webhook ───────────────────────────────────────────────

  const handleSaveWebhook = async () => {
    if (!webhook.trim()) return;
    setSaving(true);
    try {
      await postN8nWebhook(webhook.trim());
      setWebhookMsg('✓ Webhook guardado — reinicia n8n');
      setTimeout(() => setWebhookMsg(''), 3500);
    } catch {
      setWebhookMsg('✗ Error al guardar');
      setTimeout(() => setWebhookMsg(''), 3000);
    } finally { setSaving(false); }
  };

  // ── Derivados de la respuesta del dashboard ───────────────
  // Fuente primaria: /api/n8n/info → { url, cf_mode, webhook_url }
  // Fuente fallback: /api/status   → { n8n_url }
  const tunnelUrl    = n8nInfo?.url || status?.n8n_url || '';
  const cfMode       = n8nInfo?.cf_mode || '';   // "fija" | "temporal" | ""
  const hasToken     = cfMode === 'fija';
  const urlModeLabel = hasToken    ? '⚿ token fijo'
                     : tunnelUrl   ? '○ free (temporal)'
                     : '— sin URL';
  const urlModeColor = hasToken    ? theme.success
                     : tunnelUrl   ? theme.warning
                     : theme.textMuted;

  // ── Render ────────────────────────────────────────────────

  return (
    <View style={s.root}>

      {/* TopBar — sin compensación de status bar (App.js la maneja) */}
      <View style={s.topBar}>
        <TouchableOpacity onPress={goBack} style={s.backBtn} activeOpacity={0.7}>
          <Text style={s.backIcon}>‹</Text>
          <Text style={s.backText}>Módulos</Text>
        </TouchableOpacity>
      </View>

      <ScrollView style={s.scroll} contentContainerStyle={s.content}
        showsVerticalScrollIndicator={false}>

        {/* ── Header módulo ── */}
        <View style={s.moduleHeader}>
          <View style={s.moduleLeft}>
            <Text style={s.modIcon}>∞</Text>
            <View>
              <Text style={s.modName}>n8n</Text>
              {mod?.version ? <Text style={s.modVer}>v{mod.version}</Text> : null}
            </View>
          </View>
          <View style={s.moduleRight}>
            <StatusPill status={getModStatus(mod)} />
            {mod?.installed ? (
              <Switch
                value={mod?.running === true}
                onValueChange={val => trigger(val ? 'start' : 'stop')}
                trackColor={{ false: theme.overlay, true: theme.success }}
                thumbColor={mod?.running ? '#fff' : theme.textMuted}
                disabled={actionState === 'loading'}
              />
            ) : null}
          </View>
        </View>

        {actionState !== 'idle' && (
          <Text style={[s.feedback,
            actionState === 'success' ? { color: theme.success } :
            actionState === 'error'   ? { color: theme.error }   :
            { color: theme.warning }
          ]}>
            {actionState === 'loading' ? '⏳ Aplicando...' :
             actionState === 'success' ? '✓ Listo' : '✗ Sin respuesta'}
          </Text>
        )}

        <Divider />

        {/* ── URL pública ── */}
        <SectionLabel>URL PÚBLICA</SectionLabel>
        <View style={s.urlRow}>
          <View style={[s.modePill, { borderColor: urlModeColor + '55' }]}>
            <Text style={[s.modeText, { color: urlModeColor }]}>{urlModeLabel}</Text>
          </View>
          <TouchableOpacity style={s.iconBtn} onPress={loadInfo} activeOpacity={0.7}>
            <Text style={s.iconBtnText}>↻</Text>
          </TouchableOpacity>
        </View>
        {tunnelUrl ? (
          <CodeBox value={tunnelUrl} label="URL activa" onCopy={v => Clipboard.setString(v)} />
        ) : (
          <Text style={s.emptyNote}>
            {mod?.running ? 'Obteniendo URL...' : 'Inicia n8n para ver la URL'}
          </Text>
        )}

        <Divider />

        {/* ── Token cloudflared ── */}
        <SectionLabel>TOKEN CLOUDFLARED</SectionLabel>
        <Text style={s.hint}>
          Con token: URL fija permanente.{'\n'}
          Sin token: URL temporal gratuita (cambia al reiniciar).
        </Text>
        <Text style={[s.tokenState,
          hasToken ? { color: theme.success } : { color: theme.textMuted }
        ]}>
          {hasToken ? '⚿ Token configurado — URL fija' : '○ Sin token (modo free)'}
        </Text>

        <InputField
          label="Nuevo token"
          value={token}
          onChangeText={setToken}
          placeholder="eyJhGxn0..."
          secureTextEntry
          style={{ marginTop: 10 }}
        />
        <View style={s.btnRow}>
          <ActionButton
            label="Guardar token"
            onPress={handleSaveToken}
            variant="primary"
            state={saving ? 'loading' : 'idle'}
            disabled={!token.trim()}
            style={{ flex: 1 }}
          />
          {hasToken ? (
            <ActionButton
              label="Quitar"
              onPress={handleRemoveToken}
              variant="danger"
              style={{ minWidth: 80 }}
            />
          ) : null}
        </View>
        {tokenMsg ? (
          <Text style={[s.feedback,
            tokenMsg.startsWith('✓') ? { color: theme.success } : { color: theme.error }
          ]}>{tokenMsg}</Text>
        ) : null}

        <Divider />

        {/* ── Webhook URL ── */}
        <SectionLabel>WEBHOOK URL</SectionLabel>
        <Text style={s.hint}>URL del workflow de Telegram en n8n.</Text>
        <InputField
          label="URL webhook"
          value={webhook}
          onChangeText={setWebhook}
          placeholder="https://tu-dominio.com/webhook/..."
        />
        <ActionButton
          label="Guardar webhook"
          onPress={handleSaveWebhook}
          variant="primary"
          state={saving ? 'loading' : 'idle'}
          disabled={!webhook.trim()}
        />
        {webhookMsg ? (
          <Text style={[s.feedback,
            webhookMsg.startsWith('✓') ? { color: theme.success } : { color: theme.error }
          ]}>{webhookMsg}</Text>
        ) : null}

        <Divider />

        {/* ── Logs ── */}
        <SectionLabel>LOGS</SectionLabel>
        <TouchableOpacity style={s.logsBtn} onPress={() => setLogsVisible(true)} activeOpacity={0.75}>
          <Text style={s.logsIcon}>≡</Text>
          <Text style={s.logsBtnText}>Ver logs de n8n</Text>
          <Text style={s.logsArrow}>›</Text>
        </TouchableOpacity>

        <Divider />

        {/* ── Info técnica ── */}
        <SectionLabel>INFO TÉCNICA</SectionLabel>
        <InfoRow label="Puerto"      value="5678 (proot Debian)" />
        <InfoRow label="Node.js"     value="v20 LTS (fijo)" />
        <InfoRow label="Protocolo"   value="HTTPS + cloudflared" />
        <InfoRow label="Modo tunnel"
          value={cfMode || '—'}
          valueColor={hasToken ? theme.success : cfMode ? theme.warning : theme.textMuted}
        />
        <InfoRow label="Webhook"
          value={n8nInfo?.webhook_url ? 'Configurado' : 'Sin configurar'}
          valueColor={n8nInfo?.webhook_url ? theme.success : theme.textMuted}
        />

        <View style={{ height: 32 }} />
      </ScrollView>

      <LogsModal visible={logsVisible} module="n8n" onClose={() => setLogsVisible(false)} />
    </View>
  );
}

// ─── Estilos — sin sbHeight, App.js lo maneja ────────────────

function createStyles(t) {
  return StyleSheet.create({
    root:  { flex: 1, backgroundColor: t.bg },

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
    backBtn:  { flexDirection: 'row', alignItems: 'center', gap: 4, padding: 4 },
    backIcon: { fontSize: 24, color: t.accent, fontWeight: '700', lineHeight: 28 },
    backText: { fontSize: 14, color: t.accent, fontWeight: '500' },

    scroll:  { flex: 1 },
    content: { padding: 16 },

    moduleHeader: {
      flexDirection: 'row', alignItems: 'center',
      justifyContent: 'space-between', marginBottom: 6,
    },
    moduleLeft:  { flexDirection: 'row', alignItems: 'center', gap: 12 },
    modIcon:     { fontSize: 34, color: '#e05d28' },
    modName:     { fontSize: 20, fontWeight: '700', color: t.textPrimary },
    modVer:      { fontSize: 11, color: t.textMuted, marginTop: 2 },
    moduleRight: { flexDirection: 'row', alignItems: 'center', gap: 10 },

    feedback: { fontSize: 12, fontWeight: '600', marginVertical: 6 },

    urlRow:   { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 8 },
    modePill: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 999,
                borderWidth: 1, backgroundColor: t.overlay },
    modeText: { fontSize: 11, fontWeight: '700' },
    iconBtn:  { width: 32, height: 32, borderRadius: 8, backgroundColor: t.overlay,
                borderWidth: 1, borderColor: t.border,
                alignItems: 'center', justifyContent: 'center' },
    iconBtnText: { fontSize: 16, color: t.textSecond },
    emptyNote:   { fontSize: 12, color: t.textMuted, marginBottom: 8, fontStyle: 'italic' },

    hint:       { fontSize: 12, color: t.textSecond, marginBottom: 8, lineHeight: 18 },
    tokenState: { fontSize: 12, fontWeight: '600', marginBottom: 4 },
    btnRow:     { flexDirection: 'row', gap: 8, marginBottom: 4 },

    logsBtn: {
      flexDirection: 'row', alignItems: 'center',
      backgroundColor: t.card, borderWidth: 1, borderColor: t.border,
      borderRadius: 10, padding: 14, gap: 10,
    },
    logsIcon:    { fontSize: 16, color: t.accent },
    logsBtnText: { flex: 1, fontSize: 13, fontWeight: '600', color: t.textPrimary },
    logsArrow:   { fontSize: 20, color: t.accent, fontWeight: '700' },
  });
}
