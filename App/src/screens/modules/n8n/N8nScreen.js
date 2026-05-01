// src/screens/modules/n8n/N8nScreen.js — v2.0.0
import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, ScrollView, TouchableOpacity,
  Switch, StyleSheet, Platform, Alert, Clipboard,
} from 'react-native';
import { useTheme }       from '../../../theme/ThemeContext';
import { useStatus }      from '../../../hooks/useStatus';
import { useAction }      from '../../../hooks/useAction';
import { InputField }     from '../../../components/InputField';
import { ActionButton }   from '../../../components/ActionButton';
import { StatusPill }     from '../../../components/StatusPill';
import { SectionLabel }   from '../../../components/SectionLabel';
import { Divider }        from '../../../components/Divider';
import { InfoRow }        from '../../../components/InfoRow';
import { CodeBox }        from '../../../components/CodeBox';
import { LogsModal }      from '../../logs/LogsModal';
import {
  getN8nInfo, postN8nToken, postN8nWebhook,
} from '../../../services/dashboard';

// ─── Helper de estado ────────────────────────────────────────

function getStatus(mod) {
  if (!mod) return 'inactive';
  if (mod.running === true) return 'active';
  if (mod.installed) return 'ready';
  return 'inactive';
}

// ─── N8nScreen ───────────────────────────────────────────────

export function N8nScreen({ goBack }) {
  const { theme }               = useTheme();
  const { status }              = useStatus();
  const { actionState, trigger } = useAction('n8n');
  const s = createStyles(theme);

  // Info del módulo desde status
  const mod = status?.modules?.find(m => m.id === 'n8n');

  // Estado local
  const [n8nInfo, setN8nInfo]         = useState(null);
  const [token, setToken]             = useState('');
  const [tokenSaved, setTokenSaved]   = useState('');  // mensaje feedback
  const [webhook, setWebhook]         = useState('');
  const [webhookSaved, setWebhookSaved] = useState('');
  const [logsVisible, setLogsVisible] = useState(false);
  const [saving, setSaving]           = useState(false);

  // Cargar info de n8n
  useEffect(() => {
    loadInfo();
  }, []);

  const loadInfo = async () => {
    try {
      const data = await getN8nInfo();
      setN8nInfo(data);
      if (data?.webhook_url) setWebhook(data.webhook_url);
    } catch { /* dashboard offline */ }
  };

  // ── Guardar token ─────────────────────────────────────────

  const handleSaveToken = async () => {
    if (!token.trim()) return;
    setSaving(true);
    try {
      await postN8nToken(token.trim());
      setTokenSaved('✓ Token guardado — reinicia n8n para aplicar');
      setToken('');
      setTimeout(() => setTokenSaved(''), 4000);
    } catch {
      setTokenSaved('✗ Error al guardar token');
      setTimeout(() => setTokenSaved(''), 3000);
    } finally {
      setSaving(false);
    }
  };

  const handleRemoveToken = async () => {
    Alert.alert(
      'Quitar token',
      '¿Quitar el token cloudflared? n8n usará URL temporal (gratuita).',
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Quitar', style: 'destructive',
          onPress: async () => {
            setSaving(true);
            try {
              await postN8nToken('', true);
              setTokenSaved('✓ Token eliminado');
              setTimeout(() => setTokenSaved(''), 3000);
            } catch {
              setTokenSaved('✗ Error al quitar token');
              setTimeout(() => setTokenSaved(''), 3000);
            } finally {
              setSaving(false);
              loadInfo();
            }
          },
        },
      ]
    );
  };

  // ── Guardar webhook ──────────────────────────────────────

  const handleSaveWebhook = async () => {
    if (!webhook.trim()) return;
    setSaving(true);
    try {
      await postN8nWebhook(webhook.trim());
      setWebhookSaved('✓ Webhook guardado');
      setTimeout(() => setWebhookSaved(''), 3000);
    } catch {
      setWebhookSaved('✗ Error al guardar');
      setTimeout(() => setWebhookSaved(''), 3000);
    } finally {
      setSaving(false);
    }
  };

  const copyToClipboard = (text) => {
    Clipboard.setString(text);
  };

  // ── URL mode ─────────────────────────────────────────────
  // Determina si la URL es de token fijo o free (temporal)
  const tunnelUrl    = n8nInfo?.tunnel_url || status?.n8n_url || '';
  const hasToken     = n8nInfo?.has_token === true;
  const urlMode      = hasToken ? 'tunnel' : tunnelUrl ? 'free' : 'sin URL';
  const urlModeColor = hasToken ? theme.success : tunnelUrl ? theme.warning : theme.textMuted;

  return (
    <View style={s.root}>
      {/* Header con back */}
      <View style={s.topBar}>
        <TouchableOpacity onPress={goBack} style={s.backBtn} activeOpacity={0.7}>
          <Text style={s.backIcon}>‹</Text>
          <Text style={s.backText}>Módulos</Text>
        </TouchableOpacity>
      </View>

      <ScrollView style={s.scroll} contentContainerStyle={s.content}
        showsVerticalScrollIndicator={false}>

        {/* ── Título + estado + switch ── */}
        <View style={s.moduleHeader}>
          <View style={s.moduleLeft}>
            <Text style={s.moduleIcon}>∞</Text>
            <View>
              <Text style={s.moduleName}>n8n</Text>
              {mod?.version ? <Text style={s.moduleVer}>v{mod.version}</Text> : null}
            </View>
          </View>
          <View style={s.moduleRight}>
            <StatusPill status={getStatus(mod)} />
            {mod?.installed ? (
              <Switch
                value={mod?.running === true}
                onValueChange={(val) => trigger(val ? 'start' : 'stop')}
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
             actionState === 'success' ? '✓ Hecho' : '✗ Sin respuesta'}
          </Text>
        )}

        <Divider />

        {/* ── URL pública ── */}
        <SectionLabel>URL PÚBLICA</SectionLabel>
        <View style={s.urlRow}>
          <View style={[s.modePill, { borderColor: urlModeColor + '55' }]}>
            <Text style={[s.modeText, { color: urlModeColor }]}>
              {urlMode === 'tunnel' ? '⚿ token' : urlMode === 'free' ? '○ free' : '— sin URL'}
            </Text>
          </View>
          <TouchableOpacity style={s.refreshBtn} onPress={loadInfo} activeOpacity={0.7}>
            <Text style={s.refreshIcon}>↻</Text>
          </TouchableOpacity>
        </View>
        {tunnelUrl ? (
          <CodeBox value={tunnelUrl} onCopy={copyToClipboard} label="URL activa" />
        ) : (
          <Text style={s.emptyNote}>
            {mod?.running ? 'Obteniendo URL...' : 'Inicia n8n para ver la URL'}
          </Text>
        )}

        <Divider />

        {/* ── Token cloudflared ── */}
        <SectionLabel>TOKEN CLOUDFLARED</SectionLabel>
        <Text style={s.hint}>
          Con token: URL fija permanente.{'\n'}Sin token: URL temporal gratuita (cambia al reiniciar).
        </Text>
        <View style={s.tokenStatus}>
          <Text style={[s.tokenState,
            hasToken ? { color: theme.success } : { color: theme.textMuted }
          ]}>
            {hasToken ? '⚿ Token configurado' : '○ Sin token (modo free)'}
          </Text>
        </View>
        <InputField
          label="Nuevo token"
          value={token}
          onChangeText={setToken}
          placeholder="eyJhGxn0..."
          secureTextEntry
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
        {tokenSaved ? (
          <Text style={[s.feedback,
            tokenSaved.startsWith('✓') ? { color: theme.success } : { color: theme.error }
          ]}>{tokenSaved}</Text>
        ) : null}

        <Divider />

        {/* ── Webhook URL ── */}
        <SectionLabel>WEBHOOK URL</SectionLabel>
        <Text style={s.hint}>URL de tu workflow de Telegram en n8n.</Text>
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
        {webhookSaved ? (
          <Text style={[s.feedback,
            webhookSaved.startsWith('✓') ? { color: theme.success } : { color: theme.error }
          ]}>{webhookSaved}</Text>
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
        <InfoRow label="Puerto"       value="5678 (proot Debian)" />
        <InfoRow label="Node.js"      value="v20 LTS (fijo)" />
        <InfoRow label="Protocolo"    value="HTTPS + cloudflared" />
        <InfoRow label="Webhook activo"
          value={n8nInfo?.webhook_url ? 'Sí' : 'No'}
          valueColor={n8nInfo?.webhook_url ? theme.success : theme.textMuted}
        />

        <View style={{ height: 32 }} />
      </ScrollView>

      {/* Modal de logs */}
      <LogsModal
        visible={logsVisible}
        module="n8n"
        onClose={() => setLogsVisible(false)}
      />
    </View>
  );
}

// ─── Estilos ─────────────────────────────────────────────────

function createStyles(t) {
  return StyleSheet.create({
    root:   { flex: 1, backgroundColor: t.bg },
    topBar: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: 14,
      paddingTop: Platform.OS === 'android' ? 10 : 16,
      paddingBottom: 6,
      backgroundColor: t.surface,
      borderBottomWidth: 1,
      borderBottomColor: t.border,
    },
    backBtn:  { flexDirection: 'row', alignItems: 'center', gap: 4, padding: 4 },
    backIcon: { fontSize: 22, color: t.accent, fontWeight: '700' },
    backText: { fontSize: 14, color: t.accent, fontWeight: '500' },

    scroll:  { flex: 1 },
    content: { padding: 16 },

    // Header módulo
    moduleHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      marginBottom: 6,
    },
    moduleLeft:  { flexDirection: 'row', alignItems: 'center', gap: 12 },
    moduleIcon:  { fontSize: 32, color: '#e05d28' },
    moduleName:  { fontSize: 20, fontWeight: '700', color: t.textPrimary },
    moduleVer:   { fontSize: 11, color: t.textMuted, marginTop: 2 },
    moduleRight: { flexDirection: 'row', alignItems: 'center', gap: 10 },

    feedback: { fontSize: 12, fontWeight: '600', marginBottom: 8 },

    // URL
    urlRow:      { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 8 },
    modePill:    { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 999,
                   borderWidth: 1, backgroundColor: t.overlay },
    modeText:    { fontSize: 11, fontWeight: '700' },
    refreshBtn:  { width: 32, height: 32, borderRadius: 8, backgroundColor: t.overlay,
                   borderWidth: 1, borderColor: t.border,
                   alignItems: 'center', justifyContent: 'center' },
    refreshIcon: { fontSize: 16, color: t.textSecond },
    emptyNote:   { fontSize: 12, color: t.textMuted, marginBottom: 8, fontStyle: 'italic' },

    // Token
    hint: { fontSize: 12, color: t.textSecond, marginBottom: 10, lineHeight: 18 },
    tokenStatus: { marginBottom: 10 },
    tokenState:  { fontSize: 12, fontWeight: '600' },
    btnRow:      { flexDirection: 'row', gap: 8, marginBottom: 4 },

    // Logs
    logsBtn: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: t.card,
      borderWidth: 1,
      borderColor: t.border,
      borderRadius: 10,
      padding: 14,
      gap: 10,
    },
    logsIcon:    { fontSize: 16, color: t.accent },
    logsBtnText: { flex: 1, fontSize: 13, fontWeight: '600', color: t.textPrimary },
    logsArrow:   { fontSize: 20, color: t.accent, fontWeight: '700' },
  });
}
