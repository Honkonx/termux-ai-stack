import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, StyleSheet, ScrollView, TouchableOpacity,
  ActivityIndicator, Alert, RefreshControl, Platform, Modal, TextInput,
} from 'react-native';
import { useTheme } from '../../../theme/ThemeContext';
import { useStatus } from '../../../hooks/useStatus';
import { getOpenClaudeInfo, postOpenClaudeProvider } from '../../../services/dashboard';

const OCL_ACCENT = '#a78bfa';
const OCL_DIM    = '#1e1b3a';

const PROVIDERS = [
  { id: 'ollama',     name: 'Ollama local',  url: 'http://127.0.0.1:11434/v1',          api: 'ollama',     key: 'ollama' },
  { id: 'anthropic',  name: 'Anthropic',     url: 'https://api.anthropic.com/v1',         api: 'anthropic',  key: '' },
  { id: 'deepseek',   name: 'DeepSeek',      url: 'https://api.deepseek.com/v1',          api: 'openai',     key: '' },
  { id: 'openrouter', name: 'OpenRouter',    url: 'https://openrouter.ai/api/v1',         api: 'openai',     key: '' },
  { id: 'manual',     name: 'Manual',        url: '',                                     api: 'openai',     key: '' },
];

const MODELS_BY_PROVIDER = {
  ollama:     ['qwen2.5:0.5b', 'qwen2.5:1.5b', 'llama3.2:1b', 'gemma3:1b', 'phi3:mini'],
  anthropic:  ['claude-sonnet-4-20250514', 'claude-3-5-sonnet-20241022', 'claude-3-5-haiku-20241022'],
  deepseek:   ['deepseek-chat', 'deepseek-reasoner'],
  openrouter: ['deepseek/deepseek-chat', 'google/gemini-2.0-flash-exp', 'meta-llama/llama-3.3-70b-instruct'],
  manual:     [],
};

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

const ProviderCard = ({ prov, selected, installed, onPress, t }) => (
  <TouchableOpacity
    onPress={onPress}
    activeOpacity={0.7}
    style={{
      flexDirection: 'row', alignItems: 'center',
      paddingVertical: 14, paddingHorizontal: 14,
      backgroundColor: selected ? OCL_DIM : 'transparent',
      borderLeftWidth: 3,
      borderLeftColor: selected ? OCL_ACCENT : 'transparent',
    }}
  >
    <View style={{ flex: 1 }}>
      <Text style={{
        fontSize: 14, fontWeight: '600',
        color: selected ? OCL_ACCENT : (t.textPrimary || t.text || '#f4f4f5'),
      }}>{prov.name}</Text>
      <Text style={{
        fontSize: 11, fontWeight: '400',
        color: t.textMuted || '#52525b', marginTop: 2,
      }}>{prov.url || 'URL personalizada'}</Text>
    </View>
    {selected && (
      <View style={{
        paddingHorizontal: 8, paddingVertical: 3,
        borderRadius: 999, backgroundColor: OCL_ACCENT + '33',
      }}>
        <Text style={{ fontSize: 10, fontWeight: '700', color: OCL_ACCENT }}>✓</Text>
      </View>
    )}
  </TouchableOpacity>
);

const ModelChip = ({ label, selected, onPress, t }) => (
  <TouchableOpacity
    onPress={onPress}
    activeOpacity={0.7}
    style={{
      paddingHorizontal: 12, paddingVertical: 7,
      borderRadius: 999,
      backgroundColor: selected ? OCL_DIM : t.card,
      borderWidth: 1,
      borderColor: selected ? OCL_ACCENT : t.border,
      marginRight: 6, marginBottom: 6,
    }}
  >
    <Text style={{
      fontSize: 12, fontWeight: selected ? '700' : '500',
      color: selected ? OCL_ACCENT : (t.textPrimary || t.text || '#f4f4f5'),
      fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
    }}>{label}</Text>
  </TouchableOpacity>
);

export function OpenClaudeScreen({ goBack }) {
  const { theme: t } = useTheme();
  const { status } = useStatus();

  const ip = status?.ip || '127.0.0.1';
  const mod = status?.modules?.find(m => m.id === 'openclaude');

  const [info, setInfo] = useState(null);
  const [loading, setLoading] = useState(true);
  const [feedback, setFeedback] = useState(null);
  const [selectedProv, setSelectedProv] = useState(PROVIDERS[0].id);
  const [selectedModel, setSelectedModel] = useState('');
  const [saving, setSaving] = useState(false);
  const [showProvModal, setShowProvModal] = useState(false);
  const [showModelModal, setShowModelModal] = useState(false);

  const [manualUrl, setManualUrl] = useState('');
  const [manualKey, setManualKey] = useState('');
  const [manualModel, setManualModel] = useState('');

  const fbTimer = useRef(null);

  const showFeedback = useCallback((type, msg) => {
    if (fbTimer.current) clearTimeout(fbTimer.current);
    setFeedback({ type, msg });
    fbTimer.current = setTimeout(() => setFeedback(null), 3000);
  }, []);

  useEffect(() => () => { if (fbTimer.current) clearTimeout(fbTimer.current); }, []);

  const loadInfo = useCallback(async () => {
    try {
      const data = await getOpenClaudeInfo();
      setInfo(data);
      if (data?.provider) {
        const found = PROVIDERS.find(p => p.id === data.provider);
        if (found) setSelectedProv(data.provider);
      }
      if (data?.model) setSelectedModel(data.model);
    } catch {
      // silent
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { loadInfo(); }, [loadInfo]);

  const installed = info?.installed ?? mod?.installed ?? false;
  const version = info?.version || mod?.version || '';
  const currentProvider = info?.provider || '';
  const currentModel = info?.model || '';

  const handleSaveProvider = useCallback(async () => {
    const prov = PROVIDERS.find(p => p.id === selectedProv);
    if (!prov) return;
    setSaving(true);
    try {
      let url = prov.url;
      let key = prov.key;
      let model = selectedModel;
      if (selectedProv === 'manual') {
        url = manualUrl || 'http://127.0.0.1:11434/v1';
        key = manualKey || '';
        model = manualModel || selectedModel;
      }
      const data = await postOpenClaudeProvider(selectedProv, model, url, key);
      if (data.ok) {
        showFeedback('ok', `✓ ${prov.name}/${model} guardado`);
        setShowProvModal(false);
        setShowModelModal(false);
        setTimeout(loadInfo, 1500);
      } else {
        showFeedback('err', data.msg || 'Error');
      }
    } catch {
      showFeedback('err', 'Sin conexión al dashboard');
    } finally {
      setSaving(false);
    }
  }, [selectedProv, selectedModel, manualUrl, manualKey, manualModel, loadInfo, showFeedback]);

  const openTerminal = useCallback(() => {
    Alert.alert(
      'OpenClaude Terminal',
      `Proveedor: ${currentProvider || selectedProv}\nModelo: ${currentModel || selectedModel}\n\nAbre OpenClaude en la terminal:\n$ openclaude\n\nUsa WebSocket :8081 para PTY.`,
      [{ text: 'OK' }]
    );
  }, [currentProvider, currentModel, selectedProv, selectedModel]);

  const handleReinstall = useCallback(() => {
    Alert.alert(
      'Reinstalar OpenClaude',
      'Ejecuta install_openclaude.sh en Termux para reinstalar.',
      [{ text: 'Cancelar', style: 'cancel' }, { text: 'OK' }]
    );
  }, []);

  const s = createStyles(t);

  return (
    <View style={s.root}>
      <View style={s.topBar}>
        <TouchableOpacity onPress={goBack} style={s.backBtn} activeOpacity={0.7}>
          <Text style={s.backTxt}>‹ Módulos</Text>
        </TouchableOpacity>
        <Text style={s.topTitle}>OpenClaude</Text>
        <View style={s.topRight}>
          <View style={[s.pill, installed ? s.pillActive : s.pillOff]}>
            <Text style={[s.pillDot, { color: installed ? OCL_ACCENT : (t.textMuted || '#52525b') }]}>●</Text>
            <Text style={[s.pillLbl, { color: installed ? OCL_ACCENT : (t.textMuted || '#52525b') }]}>
              {installed ? 'instalado' : 'no inst.'}
            </Text>
          </View>
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
          <RefreshControl refreshing={loading} onRefresh={loadInfo} tintColor={OCL_ACCENT} colors={[OCL_ACCENT]} />
        }
      >
        {/* ── Cabecera info ── */}
        <View style={s.section}>
          <View style={s.card}>
            <View style={{ padding: 14 }}>
              <Text style={{
                fontSize: 13, fontWeight: '600',
                color: t.textPrimary || t.text || '#f4f4f5',
                marginBottom: 4,
              }}>@gitlawb/openclaude</Text>
              <Text style={{
                fontSize: 11, fontWeight: '400',
                color: t.textMuted || '#52525b',
              }}>
                Wrapper de Claude Code multi-proveedor{version ? ` · v${version}` : ''}
              </Text>
            </View>
            <Divider t={t} />
            <InfoRow label="Proveedor" value={currentProvider || 'no configurado'} t={t}
              valueColor={currentProvider ? OCL_ACCENT : t.textMuted} />
            <Divider t={t} />
            <InfoRow label="Modelo" value={currentModel || '—'} t={t} />
            <Divider t={t} />
            <InfoRow label="Ubicación" value="Termux nativo" t={t} />
          </View>
        </View>

        {/* ── Acciones ── */}
        <View style={s.section}>
          <SectionLabel t={t}>Acciones</SectionLabel>
          <View style={s.card}>
            <TouchableOpacity
              onPress={openTerminal}
              activeOpacity={0.7}
              style={{
                flexDirection: 'row', alignItems: 'center',
                paddingVertical: 16, paddingHorizontal: 14,
              }}
            >
              <Text style={{
                flex: 1, fontSize: 14, fontWeight: '600',
                color: OCL_ACCENT,
              }}>▶ Abrir OpenClaude</Text>
              <Text style={{ fontSize: 16, color: OCL_ACCENT }}>›</Text>
            </TouchableOpacity>
            <Divider t={t} />
            <TouchableOpacity
              onPress={() => setShowProvModal(true)}
              activeOpacity={0.7}
              style={{
                flexDirection: 'row', alignItems: 'center',
                paddingVertical: 16, paddingHorizontal: 14,
              }}
            >
              <Text style={{
                flex: 1, fontSize: 14, fontWeight: '600',
                color: t.textPrimary || t.text || '#f4f4f5',
              }}>✎ Cambiar proveedor / modelo</Text>
              <Text style={{ fontSize: 16, color: t.textSecond }}>›</Text>
            </TouchableOpacity>
            <Divider t={t} />
            <TouchableOpacity
              onPress={handleReinstall}
              activeOpacity={0.7}
              style={{
                flexDirection: 'row', alignItems: 'center',
                paddingVertical: 16, paddingHorizontal: 14,
              }}
            >
              <Text style={{
                flex: 1, fontSize: 14, fontWeight: '600',
                color: t.textPrimary || t.text || '#f4f4f5',
              }}>↻ Instalar / reinstalar</Text>
              <Text style={{ fontSize: 16, color: t.textSecond }}>›</Text>
            </TouchableOpacity>
          </View>
        </View>

        <View style={{ height: 24 }} />
      </ScrollView>

      {/* ── Modal: Seleccionar proveedor ── */}
      <Modal visible={showProvModal} transparent animationType="fade" onRequestClose={() => setShowProvModal(false)}>
        <View style={s.modalOverlay}>
          <View style={s.modalContent}>
            <Text style={s.modalTitle}>Proveedor IA</Text>
            <ScrollView style={{ maxHeight: 400 }}>
              {PROVIDERS.map(prov => (
                <ProviderCard
                  key={prov.id}
                  prov={prov}
                  selected={selectedProv === prov.id}
                  installed
                  onPress={() => {
                    setSelectedProv(prov.id);
                    const models = MODELS_BY_PROVIDER[prov.id] || [];
                    if (models.length > 0 && !models.includes(selectedModel)) {
                      setSelectedModel(models[0]);
                    }
                    if (prov.id === 'manual') {
                      setSelectedModel(manualModel || '');
                    }
                  }}
                  t={t}
                />
              ))}
            </ScrollView>

            {selectedProv === 'manual' && (
              <View style={{ paddingHorizontal: 14, paddingTop: 12 }}>
                <TextInput
                  style={s.input}
                  placeholder="Base URL (ej: http://..."
                  placeholderTextColor={t.textMuted || '#52525b'}
                  value={manualUrl}
                  onChangeText={setManualUrl}
                />
                <TextInput
                  style={s.input}
                  placeholder="API Key (opcional)"
                  placeholderTextColor={t.textMuted || '#52525b'}
                  value={manualKey}
                  onChangeText={setManualKey}
                  secureTextEntry
                />
                <TextInput
                  style={s.input}
                  placeholder="Modelo (ej: gpt-4)"
                  placeholderTextColor={t.textMuted || '#52525b'}
                  value={manualModel}
                  onChangeText={setManualModel}
                />
              </View>
            )}

            <Divider t={t} />
            <View style={{ paddingHorizontal: 14, paddingVertical: 8 }}>
              <Text style={{
                fontSize: 11, fontWeight: '600', color: t.textMuted || '#52525b',
                marginBottom: 8, textTransform: 'uppercase', letterSpacing: 0.5,
              }}>Modelo</Text>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
                {(MODELS_BY_PROVIDER[selectedProv] || []).map(m => (
                  <ModelChip
                    key={m}
                    label={m}
                    selected={selectedModel === m}
                    onPress={() => setSelectedModel(m)}
                    t={t}
                  />
                ))}
              </View>
            </View>

            <View style={s.modalActions}>
              <TouchableOpacity
                onPress={() => setShowProvModal(false)}
                style={s.modalBtn}
              >
                <Text style={{ fontSize: 14, fontWeight: '600', color: t.textMuted }}>Cancelar</Text>
              </TouchableOpacity>
              <TouchableOpacity
                onPress={handleSaveProvider}
                disabled={saving}
                style={[s.modalBtnPrimary, saving && { opacity: 0.6 }]}
              >
                {saving ? (
                  <ActivityIndicator size="small" color="#fff" />
                ) : (
                  <Text style={{ fontSize: 14, fontWeight: '700', color: '#fff' }}>Guardar</Text>
                )}
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
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
    backTxt: { fontSize: 15, fontWeight: '500', color: OCL_ACCENT },
    topTitle: { flex: 1, fontSize: 15, fontWeight: '700', color: t.textPrimary || t.text || '#f4f4f5', textAlign: 'center' },
    topRight: { flexDirection: 'row', alignItems: 'center', minWidth: 70, justifyContent: 'flex-end' },
    pill: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 999, borderWidth: 1 },
    pillActive: { backgroundColor: OCL_DIM, borderColor: OCL_ACCENT + '55' },
    pillOff: { backgroundColor: t.overlay || '#1a1a1a', borderColor: t.border },
    pillDot: { fontSize: 8, marginRight: 4 },
    pillLbl: { fontSize: 10, fontWeight: '600', letterSpacing: 0.3 },
    feedbackBanner: { marginHorizontal: 16, marginTop: 8, paddingHorizontal: 14, paddingVertical: 8, borderRadius: 8, borderWidth: 1 },
    scroll: { flex: 1 },
    section: { marginTop: 20, paddingHorizontal: 16 },
    card: { backgroundColor: t.card, borderRadius: 12, borderWidth: 1, borderColor: t.border, overflow: 'hidden' },
    modalOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.7)', justifyContent: 'center', padding: 24 },
    modalContent: { backgroundColor: t.surface, borderRadius: 14, borderWidth: 1, borderColor: t.border, overflow: 'hidden' },
    modalTitle: { fontSize: 16, fontWeight: '700', color: OCL_ACCENT, paddingHorizontal: 14, paddingVertical: 14 },
    input: {
      backgroundColor: t.card, borderWidth: 1, borderColor: t.border,
      borderRadius: 8, paddingHorizontal: 12, paddingVertical: 10,
      fontSize: 13, color: t.textPrimary || '#f4f4f5',
      marginBottom: 8, fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
    },
    modalActions: { flexDirection: 'row', justifyContent: 'flex-end', gap: 12, padding: 14 },
    modalBtn: { paddingHorizontal: 16, paddingVertical: 10, borderRadius: 8 },
    modalBtnPrimary: { paddingHorizontal: 20, paddingVertical: 10, borderRadius: 8, backgroundColor: OCL_ACCENT },
  });
}
