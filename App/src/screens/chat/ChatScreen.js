// src/screens/chat/ChatScreen.js — v1.0 (S18)
// Chat completo con Ollama via /api/chat
// Historial persistente via /api/chat/history + /api/chat/clear
// FlatList con burbujas chatUser/chatBot del tema
// Selector de modelo en header
// num_ctx pasado desde OllamaScreen (o valor por defecto 2048)
// chatLoadingRef → previene falsos "sin conexión" durante envío

import React, {
  useState, useEffect, useRef, useCallback, useMemo,
} from 'react';
import {
  View, Text, StyleSheet, FlatList, TextInput,
  TouchableOpacity, ActivityIndicator, KeyboardAvoidingView,
  Platform, Alert, Animated,
} from 'react-native';
import { useTheme } from '../../theme/ThemeContext';
import { useStatus } from '../../hooks/useStatus';

// ── Constantes ────────────────────────────────────────────────

const OLLAMA_ACCENT  = '#4ade80';
const CHAT_ID        = 'app_local'; // chat_id fijo para la app
const TYPING_DOTS    = ['·', '· ·', '· · ·'];

// ── Helper fetch ──────────────────────────────────────────────

async function apiFetch(ip, path, opts = {}, ms = 90_000) {
  const ctrl = new AbortController();
  const tid  = setTimeout(() => ctrl.abort(), ms);
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

// ── Burbuja de mensaje ────────────────────────────────────────

const MessageBubble = React.memo(function MessageBubble({ msg, t }) {
  const isUser = msg.role === 'user';

  return (
    <View style={{
      alignItems: isUser ? 'flex-end' : 'flex-start',
      marginBottom: 8,
      paddingHorizontal: 12,
    }}>
      {/* Etiqueta rol */}
      {!isUser && (
        <Text style={{
          fontSize: 10, fontWeight: '700', letterSpacing: 0.8,
          color: OLLAMA_ACCENT,
          textTransform: 'uppercase',
          marginBottom: 3, marginLeft: 4,
        }}>
          ⬡ Ollama
        </Text>
      )}

      <View style={{
        maxWidth: '85%',
        backgroundColor: isUser ? (t.chatUser || '#1a2d5a') : (t.chatBot || '#111111'),
        borderRadius: isUser ? 16 : 12,
        borderTopRightRadius: isUser ? 4 : 16,
        borderTopLeftRadius: isUser ? 16 : 4,
        borderWidth: 1,
        borderColor: isUser
          ? ((t.accent || '#3d7aed') + '33')
          : (t.border),
        paddingHorizontal: 14,
        paddingVertical: 10,
      }}>
        <Text style={{
          fontSize: 14, fontWeight: '400', lineHeight: 21,
          color: t.textPrimary || t.text || '#f4f4f5',
          fontFamily: msg.isCode ? 'monospace' : undefined,
        }}>
          {msg.content}
        </Text>

        {/* Timestamp */}
        <Text style={{
          fontSize: 10, fontWeight: '400',
          color: t.textMuted || '#52525b',
          marginTop: 4,
          textAlign: isUser ? 'right' : 'left',
        }}>
          {msg.time}
        </Text>
      </View>
    </View>
  );
});

// ── Indicador "escribiendo" ───────────────────────────────────

const TypingIndicator = ({ t }) => {
  const [frame, setFrame] = useState(0);
  const anim = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    const id = setInterval(() => setFrame(f => (f + 1) % 3), 500);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    Animated.sequence([
      Animated.timing(anim, { toValue: 1, duration: 200, useNativeDriver: true }),
      Animated.timing(anim, { toValue: 0.6, duration: 300, useNativeDriver: true }),
    ]).start();
  }, [frame]);

  return (
    <View style={{ paddingHorizontal: 12, marginBottom: 8, alignItems: 'flex-start' }}>
      <Text style={{ fontSize: 10, fontWeight: '700', letterSpacing: 0.8,
        color: OLLAMA_ACCENT, textTransform: 'uppercase',
        marginBottom: 3, marginLeft: 4 }}>
        ⬡ Ollama
      </Text>
      <Animated.View style={{
        backgroundColor: t.chatBot || '#111111',
        borderRadius: 12, borderTopLeftRadius: 4,
        borderWidth: 1, borderColor: t.border,
        paddingHorizontal: 16, paddingVertical: 12,
        opacity: anim,
      }}>
        <Text style={{ fontSize: 18, color: t.textSecond || '#8b949e', letterSpacing: 4 }}>
          {TYPING_DOTS[frame]}
        </Text>
      </Animated.View>
    </View>
  );
};

// ── Selector de modelo (pill expandible) ─────────────────────

const ModelSelector = ({ models, selected, onSelect, t }) => {
  const [open, setOpen] = useState(false);

  return (
    <View style={{ position: 'relative', zIndex: 10 }}>
      <TouchableOpacity
        onPress={() => setOpen(v => !v)}
        activeOpacity={0.7}
        style={{
          flexDirection: 'row', alignItems: 'center',
          paddingHorizontal: 10, paddingVertical: 6,
          borderRadius: 8,
          backgroundColor: t.overlay || '#1a1a1a',
          borderWidth: 1, borderColor: t.border,
          maxWidth: 160,
        }}
      >
        <Text style={{
          fontSize: 11, fontWeight: '600',
          color: OLLAMA_ACCENT,
          fontFamily: 'monospace',
          flex: 1,
        }} numberOfLines={1}>
          {selected || 'modelo'}
        </Text>
        <Text style={{ fontSize: 10, color: t.textMuted || '#52525b', marginLeft: 4 }}>
          {open ? '∧' : '∨'}
        </Text>
      </TouchableOpacity>

      {open && (
        <View style={{
          position: 'absolute',
          top: 38, left: 0, right: 0,
          backgroundColor: t.overlay || '#1a1a1a',
          borderRadius: 8,
          borderWidth: 1, borderColor: t.border,
          zIndex: 20,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 4 },
          shadowOpacity: 0.4,
          shadowRadius: 8,
          elevation: 8,
          minWidth: 200,
        }}>
          {models.map((m, i) => (
            <TouchableOpacity
              key={m}
              onPress={() => { onSelect(m); setOpen(false); }}
              activeOpacity={0.75}
              style={{
                paddingHorizontal: 14, paddingVertical: 10,
                borderBottomWidth: i < models.length - 1 ? 1 : 0,
                borderBottomColor: t.border,
                flexDirection: 'row', alignItems: 'center',
              }}
            >
              {m === selected && (
                <Text style={{ fontSize: 11, color: OLLAMA_ACCENT, marginRight: 6 }}>✓</Text>
              )}
              <Text style={{
                fontSize: 12, fontWeight: '500',
                fontFamily: 'monospace',
                color: m === selected
                  ? OLLAMA_ACCENT
                  : (t.textPrimary || t.text || '#f4f4f5'),
              }}>
                {m}
              </Text>
            </TouchableOpacity>
          ))}
          {models.length === 0 && (
            <Text style={{
              fontSize: 12, color: t.textMuted || '#52525b',
              padding: 14,
            }}>
              Sin modelos instalados
            </Text>
          )}
        </View>
      )}
    </View>
  );
};

// ── Pantalla principal ────────────────────────────────────────

export default function ChatScreen({ navigate, goBack, params = {} }) {
  const { theme: t }  = useTheme();
  const { status }    = useStatus();

  const ip           = status?.ip || '127.0.0.1';
  const ollamaActive = status?.modules?.find(m => m.id === 'ollama')?.running ?? false;

  // Modelo y ctx vienen de OllamaScreen o defaults
  const [model,    setModel]    = useState(params.model    || 'qwen2.5:0.5b');
  const [numCtx]                = useState(params.numCtx   || 2048);
  const [input,    setInput]    = useState('');
  const [messages, setMessages] = useState([]);
  const [sending,  setSending]  = useState(false);
  const [loadHist, setLoadHist] = useState(true);
  const [models,   setModels]   = useState(params.model ? [params.model] : []);

  // Ref para evitar falsos "sin conexión" durante envío activo
  const chatLoadingRef = useRef(false);

  const listRef     = useRef(null);
  const inputRef    = useRef(null);

  const s = useMemo(() => createStyles(t), [t]);

  // ── Cargar historial ───────────────────────────────────────

  const loadHistory = useCallback(async () => {
    setLoadHist(true);
    try {
      const data = await apiFetch(ip, `/api/chat/history?chat_id=${CHAT_ID}`, {}, 8000);
      if (data.messages && Array.isArray(data.messages)) {
        const normalized = data.messages.map((m, idx) => ({
          id:      `hist_${idx}`,
          role:    m.rol || m.role || 'user',
          content: m.content || '',
          time:    m.fecha ? formatTime(m.fecha) : '—',
        }));
        setMessages(normalized);
      }
    } catch {
      // historial vacío — no bloquear
    } finally {
      setLoadHist(false);
    }
  }, [ip]);

  // ── Cargar lista de modelos ────────────────────────────────

  const loadModels = useCallback(async () => {
    try {
      const data = await apiFetch(ip, '/api/ollama/models', {}, 5000);
      const raw = data.models || [];
      const names = raw.map(m => typeof m === 'string' ? m : m.name || m);
      setModels(names);
      // Si el modelo actual no existe en la lista y hay otros, actualizar
      if (names.length > 0 && !names.includes(model)) {
        setModel(names[0]);
      }
    } catch {
      // silencioso
    }
  }, [ip, model]);

  useEffect(() => {
    loadHistory();
    loadModels();
  }, [loadHistory, loadModels]);

  // ── Scroll al último mensaje ───────────────────────────────

  const scrollToEnd = useCallback((animated = true) => {
    setTimeout(() => {
      listRef.current?.scrollToEnd({ animated });
    }, 100);
  }, []);

  useEffect(() => {
    if (messages.length > 0) scrollToEnd(false);
  }, [messages.length]);

  // ── Enviar mensaje ─────────────────────────────────────────

  const handleSend = useCallback(async () => {
    const text = input.trim();
    if (!text || sending) return;

    if (!ollamaActive) {
      // Solo mostrar error si NO estamos ya en una petición (evita falso negativo)
      if (!chatLoadingRef.current) {
        Alert.alert('Ollama detenido', 'Inicia Ollama desde el submenú Módulos.');
      }
      return;
    }

    // Añadir mensaje usuario inmediatamente
    const userMsg = {
      id:      `u_${Date.now()}`,
      role:    'user',
      content: text,
      time:    formatTime(new Date().toISOString()),
    };
    setMessages(prev => [...prev, userMsg]);
    setInput('');
    setSending(true);
    chatLoadingRef.current = true;
    scrollToEnd();

    try {
      const data = await apiFetch(ip, '/api/chat', {
        method: 'POST',
        body: JSON.stringify({
          model,
          message:  text,
          chat_id:  CHAT_ID,
          num_ctx:  numCtx,
        }),
      }, 120_000);

      if (data.ok && data.response) {
        const botMsg = {
          id:      `b_${Date.now()}`,
          role:    'assistant',
          content: data.response,
          time:    formatTime(new Date().toISOString()),
        };
        setMessages(prev => [...prev, botMsg]);
        scrollToEnd();
      } else {
        const errMsg = {
          id:      `e_${Date.now()}`,
          role:    'assistant',
          content: `⚠ Error: ${data.error || 'respuesta vacía'}`,
          time:    formatTime(new Date().toISOString()),
        };
        setMessages(prev => [...prev, errMsg]);
      }
    } catch (e) {
      const errMsg = {
        id:      `e_${Date.now()}`,
        role:    'assistant',
        content: e.name === 'AbortError'
          ? '⚠ Timeout — el modelo tardó demasiado. Intenta con menos contexto.'
          : `⚠ Sin respuesta del dashboard`,
        time:    formatTime(new Date().toISOString()),
      };
      setMessages(prev => [...prev, errMsg]);
    } finally {
      setSending(false);
      chatLoadingRef.current = false;
    }
  }, [input, sending, ollamaActive, ip, model, numCtx, scrollToEnd]);

  // ── Limpiar historial ──────────────────────────────────────

  const handleClear = useCallback(() => {
    Alert.alert(
      'Limpiar chat',
      'Borra el historial local y en la base de datos.',
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Limpiar', style: 'destructive',
          onPress: async () => {
            try {
              await apiFetch(ip, '/api/chat/clear', {
                method: 'POST',
                body: JSON.stringify({ chat_id: CHAT_ID }),
              }, 5000);
            } catch { /* silencioso */ }
            setMessages([]);
          },
        },
      ]
    );
  }, [ip]);

  // ── Render item ────────────────────────────────────────────

  const renderItem = useCallback(({ item }) => (
    <MessageBubble msg={item} t={t} />
  ), [t]);

  const keyExtractor = useCallback(item => item.id, []);

  // ── Estado vacío ───────────────────────────────────────────

  const EmptyState = () => (
    <View style={s.emptyState}>
      <Text style={{ fontSize: 40, marginBottom: 16 }}>⬡</Text>
      <Text style={{
        fontSize: 17, fontWeight: '700',
        color: t.textPrimary || t.text || '#f4f4f5',
        marginBottom: 8,
      }}>
        Chat con {model}
      </Text>
      <Text style={{
        fontSize: 13, fontWeight: '400', textAlign: 'center', lineHeight: 20,
        color: t.textMuted || '#52525b',
        maxWidth: 240,
      }}>
        {ollamaActive
          ? 'Escribe tu primer mensaje para empezar'
          : 'Ollama está detenido — inícialo desde Módulos'}
      </Text>
      {!ollamaActive && (
        <TouchableOpacity
          onPress={() => navigate && navigate('Ollama')}
          activeOpacity={0.75}
          style={{
            marginTop: 20,
            paddingHorizontal: 20, paddingVertical: 10,
            borderRadius: 8,
            backgroundColor: t.overlay || '#1a1a1a',
            borderWidth: 1, borderColor: t.border,
          }}
        >
          <Text style={{
            fontSize: 13, fontWeight: '600',
            color: OLLAMA_ACCENT,
          }}>
            Ir a Ollama →
          </Text>
        </TouchableOpacity>
      )}
    </View>
  );

  // ── Render ─────────────────────────────────────────────────

  return (
    <KeyboardAvoidingView
      style={s.root}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      keyboardVerticalOffset={0}
    >
      {/* ── Header ── */}
      <View style={s.header}>
        <View style={{ flex: 1 }}>
          <Text style={s.headerTitle} numberOfLines={1}>
            Chat IA
          </Text>
          {/* Estado Ollama */}
          <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 2 }}>
            <Text style={{
              fontSize: 8,
              color: ollamaActive ? OLLAMA_ACCENT : (t.textMuted || '#52525b'),
              marginRight: 4,
            }}>●</Text>
            <Text style={{
              fontSize: 10, fontWeight: '500',
              color: ollamaActive ? OLLAMA_ACCENT : (t.textMuted || '#52525b'),
            }}>
              {ollamaActive ? 'Ollama activo' : 'Ollama detenido'}
            </Text>
            <Text style={{
              fontSize: 10, fontWeight: '400',
              color: t.textMuted || '#52525b',
              marginLeft: 6,
            }}>
              · {numCtx.toLocaleString()} ctx
            </Text>
          </View>
        </View>

        {/* Selector de modelo */}
        <ModelSelector
          models={models}
          selected={model}
          onSelect={setModel}
          t={t}
        />

        {/* Botones acciones */}
        <View style={{ flexDirection: 'row', marginLeft: 8 }}>
          <TouchableOpacity
            onPress={() => { loadHistory(); loadModels(); }}
            activeOpacity={0.7}
            style={s.iconBtn}
          >
            <Text style={{ fontSize: 16, color: t.textSecond || '#8b949e' }}>↻</Text>
          </TouchableOpacity>
          <TouchableOpacity
            onPress={handleClear}
            activeOpacity={0.7}
            style={[s.iconBtn, { marginLeft: 4 }]}
          >
            <Text style={{ fontSize: 14, color: t.textSecond || '#8b949e' }}>⌫</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* ── Lista de mensajes ── */}
      {loadHist ? (
        <View style={s.loadingCenter}>
          <ActivityIndicator size="small" color={OLLAMA_ACCENT} />
          <Text style={{
            fontSize: 12, marginTop: 8,
            color: t.textMuted || '#52525b',
          }}>
            Cargando historial…
          </Text>
        </View>
      ) : (
        <FlatList
          ref={listRef}
          data={messages}
          renderItem={renderItem}
          keyExtractor={keyExtractor}
          style={s.list}
          contentContainerStyle={[
            { paddingTop: 12, paddingBottom: 8 },
            messages.length === 0 && { flex: 1 },
          ]}
          ListEmptyComponent={EmptyState}
          ListFooterComponent={sending ? <TypingIndicator t={t} /> : null}
          removeClippedSubviews
          initialNumToRender={15}
          maxToRenderPerBatch={8}
          keyboardShouldPersistTaps="handled"
          onContentSizeChange={() => scrollToEnd(false)}
        />
      )}

      {/* ── Input footer ── */}
      <View style={s.footer}>
        <View style={s.inputRow}>
          <TextInput
            ref={inputRef}
            style={s.input}
            value={input}
            onChangeText={setInput}
            placeholder={
              ollamaActive
                ? `Escribe a ${model}…`
                : 'Ollama detenido'
            }
            placeholderTextColor={t.textMuted || '#52525b'}
            multiline
            maxLength={2000}
            blurOnSubmit={false}
            editable={!sending}
            returnKeyType="default"
            onSubmitEditing={({ nativeEvent }) => {
              // submit solo si Shift no está presionado (en teclados físicos)
              // en móvil, el botón ↑ es el principal trigger
            }}
          />

          {/* Botón enviar */}
          <TouchableOpacity
            onPress={handleSend}
            activeOpacity={0.75}
            disabled={sending || !input.trim()}
            style={[
              s.sendBtn,
              (sending || !input.trim()) && { opacity: 0.35 },
            ]}
          >
            {sending ? (
              <ActivityIndicator size="small" color="#000" />
            ) : (
              <Text style={s.sendIcon}>↑</Text>
            )}
          </TouchableOpacity>
        </View>

        {/* Info tokens */}
        <Text style={s.footerHint}>
          ctx: {numCtx.toLocaleString()} · modelo: {model}
        </Text>
      </View>
    </KeyboardAvoidingView>
  );
}

// ── Helpers ───────────────────────────────────────────────────

function formatTime(iso) {
  try {
    const d = new Date(iso);
    const h = d.getHours().toString().padStart(2, '0');
    const m = d.getMinutes().toString().padStart(2, '0');
    return `${h}:${m}`;
  } catch {
    return '—';
  }
}

// ── Estilos ───────────────────────────────────────────────────

function createStyles(t) {
  return StyleSheet.create({
    root: {
      flex: 1,
      backgroundColor: t.bg,
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingTop: 10,
      paddingBottom: 12,
      paddingHorizontal: 16,
      backgroundColor: t.surface,
      borderBottomWidth: 1,
      borderBottomColor: t.border,
    },
    headerTitle: {
      fontSize: 15,
      fontWeight: '700',
      color: t.textPrimary || t.text || '#f4f4f5',
    },
    iconBtn: {
      width: 36,
      height: 36,
      borderRadius: 8,
      backgroundColor: t.overlay || '#1a1a1a',
      borderWidth: 1,
      borderColor: t.border,
      alignItems: 'center',
      justifyContent: 'center',
    },
    loadingCenter: {
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
    },
    list: {
      flex: 1,
    },
    emptyState: {
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: 32,
    },
    footer: {
      backgroundColor: t.surface,
      borderTopWidth: 1,
      borderTopColor: t.border,
      paddingHorizontal: 12,
      paddingTop: 10,
      paddingBottom: Platform.OS === 'android' ? 12 : 24,
    },
    inputRow: {
      flexDirection: 'row',
      alignItems: 'flex-end',
    },
    input: {
      flex: 1,
      backgroundColor: t.overlay || '#1a1a1a',
      borderRadius: 12,
      borderWidth: 1,
      borderColor: t.border,
      paddingHorizontal: 14,
      paddingTop: 10,
      paddingBottom: 10,
      fontSize: 14,
      fontWeight: '400',
      color: t.textPrimary || t.text || '#f4f4f5',
      maxHeight: 120,
      minHeight: 44,
      marginRight: 8,
    },
    sendBtn: {
      width: 44,
      height: 44,
      borderRadius: 12,
      backgroundColor: OLLAMA_ACCENT,
      alignItems: 'center',
      justifyContent: 'center',
    },
    sendIcon: {
      fontSize: 20,
      fontWeight: '700',
      color: '#000000',
    },
    footerHint: {
      fontSize: 10,
      fontWeight: '400',
      color: t.textMuted || '#52525b',
      marginTop: 6,
      textAlign: 'center',
      letterSpacing: 0.3,
    },
  });
}
