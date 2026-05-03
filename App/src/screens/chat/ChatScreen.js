// src/screens/chat/ChatScreen.js — v1.0.0 (S18)
// Fixes:
//   Bug #1 — layout superpuesto: estructura correcta con flex + zIndex
//   Bug #2 — teclado tapa input: KeyboardAvoidingView behavior="height" Android
//   Bug #4 — chat congela UI: loading state visible, botón cancelar, timeout 90s
//
// SURFACE:   bg negro puro → surface #0a0a0a header/footer → card #111 burbujas
// JERARQUÍA: modelo 13px bold · mensaje 14px regular · timestamp 10px muted
// ACENTO:    cian #06b6d4 (chat icon) para estado Ollama · success para enviado
// BORDES:    rgba baja opacidad — nunca hex sólido
// DENSIDAD:  media — chat conversacional, no dashboard técnico

import React, {
  useState, useRef, useCallback, useEffect,
  useMemo,
} from 'react';
import {
  View, Text, TextInput, TouchableOpacity, FlatList,
  StyleSheet, KeyboardAvoidingView, Platform, ActivityIndicator,
  Keyboard, Animated,
} from 'react-native';
import { useTheme } from '../../theme/ThemeContext';
import { useChatSession } from '../../hooks/useChatSession';

// ─── Constantes ───────────────────────────────────────────────────────────────

const ACCENT_CHAT = '#06b6d4';  // cian — diferencia ChatScreen de módulos
const ACCENT_OLLAMA = '#4ade80';

// Modelos disponibles (se sobreescriben desde OllamaScreen cuando pasa params)
const DEFAULT_MODELS = [
  'qwen2.5:0.5b',
  'qwen2.5:1.5b',
  'qwen3:4b',
  'gemma3:4b',
  'gemma3:1b',
  'deepseek-coder:1.3b-instruct',
  'llama3.2:1b',
];

// ─── Componentes internos ─────────────────────────────────────────────────────

// Burbuja de mensaje — memoizada para no re-renderizar en cada keystroke
const MessageBubble = React.memo(function MessageBubble({ message, theme }) {
  const isUser = message.role === 'user';
  const s = bubbleStyles(theme, isUser);

  const time = useMemo(() => {
    if (!message.ts) return '';
    const d = new Date(message.ts);
    return `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;
  }, [message.ts]);

  return (
    <View style={s.row}>
      <View style={s.bubble}>
        {/* Badge de rol */}
        <View style={s.roleRow}>
          <Text style={s.roleLabel}>
            {isUser ? 'TÚ' : (message.model ? `⬡ ${message.model.toUpperCase()}` : '⬡ OLLAMA')}
          </Text>
          {time ? <Text style={s.timestamp}>{time}</Text> : null}
        </View>
        {/* Contenido */}
        <Text style={s.content} selectable>
          {message.content}
        </Text>
      </View>
    </View>
  );
});

function bubbleStyles(t, isUser) {
  return StyleSheet.create({
    row: {
      paddingHorizontal: 12,
      paddingVertical: 4,
      alignItems: isUser ? 'flex-end' : 'flex-start',
    },
    bubble: {
      maxWidth: '85%',
      backgroundColor: isUser
        ? (t.chatUser || t.accentDim || '#1a2d5a')
        : (t.chatBot  || t.card     || '#111111'),
      borderRadius: isUser ? 16 : 12,
      borderTopRightRadius: isUser ? 4 : 12,
      borderTopLeftRadius:  isUser ? 12 : 4,
      borderWidth: 1,
      borderColor: isUser
        ? 'rgba(61,122,237,0.25)'
        : (t.border || 'rgba(255,255,255,0.07)'),
      padding: 10,
    },
    roleRow: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      marginBottom: 5,
    },
    roleLabel: {
      fontSize: 10,
      fontWeight: '700',
      letterSpacing: 1,
      color: isUser
        ? (t.accent  || '#3d7aed')
        : ACCENT_OLLAMA,
    },
    timestamp: {
      fontSize: 10,
      color: t.textMuted || '#52525b',
      marginLeft: 8,
    },
    content: {
      fontSize: 14,
      lineHeight: 21,
      color: t.textPrimary || t.text || '#f4f4f5',
      fontFamily: Platform.OS === 'android' ? 'sans-serif' : 'System',
    },
  });
}

// Spinner de "Ollama pensando..."
function ThinkingBubble({ theme }) {
  const anim = useRef(new Animated.Value(0.4)).current;

  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(anim, { toValue: 1,   duration: 600, useNativeDriver: true }),
        Animated.timing(anim, { toValue: 0.4, duration: 600, useNativeDriver: true }),
      ])
    );
    loop.start();
    return () => loop.stop();
  }, [anim]);

  return (
    <View style={{ paddingHorizontal: 12, paddingVertical: 4, alignItems: 'flex-start' }}>
      <View style={{
        backgroundColor: theme.chatBot || theme.card || '#111',
        borderRadius: 12,
        borderTopLeftRadius: 4,
        borderWidth: 1,
        borderColor: theme.border || 'rgba(255,255,255,0.07)',
        padding: 12,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
      }}>
        <ActivityIndicator size="small" color={ACCENT_OLLAMA} />
        <Animated.Text style={{
          fontSize: 13,
          color: theme.textMuted || '#52525b',
          opacity: anim,
        }}>
          ⬡ Ollama procesando...
        </Animated.Text>
      </View>
    </View>
  );
}

// Selector de modelo — dropdown propio, no overlay flotante
function ModelSelector({ models, selected, onSelect, theme }) {
  const [open, setOpen] = useState(false);

  return (
    <View style={{ position: 'relative', zIndex: 100 }}>
      {/* Trigger */}
      <TouchableOpacity
        onPress={() => setOpen(v => !v)}
        style={{
          flexDirection: 'row',
          alignItems: 'center',
          backgroundColor: theme.overlay || '#1a1a1a',
          borderRadius: 8,
          borderWidth: 1,
          borderColor: open
            ? (theme.borderFocus || 'rgba(61,122,237,0.35)')
            : (theme.border || 'rgba(255,255,255,0.07)'),
          paddingHorizontal: 10,
          paddingVertical: 6,
          maxWidth: 200,
        }}
        activeOpacity={0.7}
      >
        <Text style={{
          fontSize: 12,
          color: ACCENT_OLLAMA,
          fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
          flex: 1,
        }} numberOfLines={1}>
          {selected || 'Seleccionar modelo'}
        </Text>
        <Text style={{
          fontSize: 10,
          color: theme.textMuted || '#52525b',
          marginLeft: 4,
        }}>
          {open ? '∧' : '∨'}
        </Text>
      </TouchableOpacity>

      {/* Dropdown — renderizado dentro del flujo, NO modal flotante */}
      {open && (
        <View style={{
          position: 'absolute',
          top: '100%',
          left: 0,
          right: 0,
          marginTop: 2,
          backgroundColor: theme.overlay || '#1a1a1a',
          borderRadius: 8,
          borderWidth: 1,
          borderColor: theme.border || 'rgba(255,255,255,0.07)',
          // Sombra para separar del contenido debajo
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 4 },
          shadowOpacity: 0.4,
          shadowRadius: 8,
          elevation: 10,
          zIndex: 200,
          minWidth: 200,
        }}>
          {models.map((m, i) => (
            <TouchableOpacity
              key={m}
              onPress={() => { onSelect(m); setOpen(false); }}
              style={{
                paddingHorizontal: 12,
                paddingVertical: 10,
                borderBottomWidth: i < models.length - 1 ? 1 : 0,
                borderBottomColor: theme.border || 'rgba(255,255,255,0.07)',
                backgroundColor: m === selected
                  ? (theme.cardActive || '#161616')
                  : 'transparent',
              }}
              activeOpacity={0.7}
            >
              <Text style={{
                fontSize: 12,
                color: m === selected
                  ? ACCENT_OLLAMA
                  : (theme.textPrimary || theme.text || '#f4f4f5'),
                fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
              }}>
                {m === selected ? `✓ ${m}` : m}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      )}
    </View>
  );
}

// ─── Pantalla principal ───────────────────────────────────────────────────────

export function ChatScreen({ params = {} }) {
  const { theme } = useTheme();

  // Modelo inicial desde params (si viene de OllamaScreen) o default
  const [selectedModel, setSelectedModel] = useState(
    params.model || DEFAULT_MODELS[0]
  );
  const [numCtx] = useState(params.numCtx || 2048);
  const [inputText, setInputText] = useState('');
  const [inputHeight, setInputHeight] = useState(44);

  const flatListRef = useRef(null);

  const {
    messages,
    loading,
    loadingText,
    error,
    historyLoading,
    sendMessage,
    clearHistory,
    cancelRequest,
  } = useChatSession(selectedModel, numCtx);

  // Scroll al último mensaje cuando llega respuesta
  useEffect(() => {
    if (messages.length > 0 && flatListRef.current) {
      setTimeout(() => {
        flatListRef.current?.scrollToEnd({ animated: true });
      }, 100);
    }
  }, [messages.length]);

  const handleSend = useCallback(() => {
    const text = inputText.trim();
    if (!text || loading) return;
    setInputText('');
    setInputHeight(44);
    Keyboard.dismiss();
    sendMessage(text);
  }, [inputText, loading, sendMessage]);

  const handleClear = useCallback(() => {
    clearHistory();
    setInputText('');
  }, [clearHistory]);

  const s = createStyles(theme);

  // ─── Render ───────────────────────────────────────────────────────────────

  return (
    // KeyboardAvoidingView CORRECTO para Android:
    // behavior="height" — NO "padding" (ese es para iOS)
    // keyboardVerticalOffset={0} — App.js ya compensa status bar
    <KeyboardAvoidingView
      style={s.root}
      behavior={Platform.OS === 'android' ? 'height' : 'padding'}
      keyboardVerticalOffset={0}
    >
      {/* ── Header ─────────────────────────────────────────────────────── */}
      <View style={s.header}>
        <View style={s.headerLeft}>
          <Text style={s.headerTitle}>◈ Chat IA</Text>
          <View style={s.ollamaStatus}>
            <View style={[s.statusDot, { backgroundColor: ACCENT_OLLAMA }]} />
            <Text style={s.statusText}>Ollama activo</Text>
            <Text style={s.ctxText}>· {numCtx / 1000}K ctx</Text>
          </View>
        </View>

        <View style={s.headerRight}>
          <TouchableOpacity
            onPress={handleClear}
            style={s.headerBtn}
            activeOpacity={0.7}
          >
            <Text style={s.headerBtnText}>⌫ Limpiar</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* ── Selector de modelo — BAJO el header, sobre el chat ─────────── */}
      <View style={s.modelBar}>
        <ModelSelector
          models={DEFAULT_MODELS}
          selected={selectedModel}
          onSelect={setSelectedModel}
          theme={theme}
        />
        {messages.length > 0 && (
          <Text style={s.messageCount}>
            {messages.length} mensaje{messages.length !== 1 ? 's' : ''}
          </Text>
        )}
      </View>

      {/* ── Cuerpo del chat ─────────────────────────────────────────────── */}
      <View style={s.chatArea}>
        {historyLoading ? (
          <View style={s.centered}>
            <ActivityIndicator size="small" color={ACCENT_CHAT} />
            <Text style={s.emptyText}>Cargando historial...</Text>
          </View>
        ) : messages.length === 0 && !loading ? (
          <View style={s.centered}>
            <Text style={s.emptyGlyph}>◈</Text>
            <Text style={s.emptyTitle}>Chat con Ollama</Text>
            <Text style={s.emptyText}>
              Modelo: {selectedModel}
            </Text>
            <Text style={s.emptyHint}>
              Escribe un mensaje para comenzar
            </Text>
          </View>
        ) : (
          <FlatList
            ref={flatListRef}
            data={messages}
            keyExtractor={item => item.id}
            renderItem={({ item }) => (
              <MessageBubble message={item} theme={theme} />
            )}
            contentContainerStyle={s.messageList}
            showsVerticalScrollIndicator={false}
            removeClippedSubviews
            initialNumToRender={15}
            maxToRenderPerBatch={5}
            // Mantener scroll al fondo cuando llegan mensajes nuevos
            onContentSizeChange={() => {
              flatListRef.current?.scrollToEnd({ animated: true });
            }}
            ListFooterComponent={
              loading ? <ThinkingBubble theme={theme} /> : null
            }
          />
        )}
      </View>

      {/* ── Mensaje de error ─────────────────────────────────────────────── */}
      {error ? (
        <View style={s.errorBar}>
          <Text style={s.errorText} numberOfLines={2}>
            ✗ {error}
          </Text>
          <TouchableOpacity onPress={() => {}}>
            <Text style={s.errorDismiss}>×</Text>
          </TouchableOpacity>
        </View>
      ) : null}

      {/* ── Footer de input ──────────────────────────────────────────────── */}
      {/* 
        POSICIÓN: dentro del KeyboardAvoidingView, NO position:absolute
        Esto garantiza que el teclado empuja el footer hacia arriba
      */}
      <View style={s.footer}>
        {/* Indicador de carga con botón cancelar */}
        {loading && (
          <TouchableOpacity
            onPress={cancelRequest}
            style={s.cancelBar}
            activeOpacity={0.7}
          >
            <ActivityIndicator size="small" color={ACCENT_OLLAMA} />
            <Text style={s.cancelText}>
              {loadingText || 'Ollama procesando...'} · toca para cancelar
            </Text>
          </TouchableOpacity>
        )}

        <View style={s.inputRow}>
          {/* TextInput multiline con altura dinámica */}
          <TextInput
            style={[s.input, { height: Math.max(44, Math.min(inputHeight, 120)) }]}
            placeholder={`Escribe a ${selectedModel}...`}
            placeholderTextColor={theme.textMuted || '#52525b'}
            value={inputText}
            onChangeText={setInputText}
            multiline
            onContentSizeChange={e => {
              setInputHeight(e.nativeEvent.contentSize.height + 16);
            }}
            returnKeyType="default"
            // NO submitOnReturn — permite saltos de línea
            blurOnSubmit={false}
            editable={!loading}
            // Enfocar input no oculta el header
            scrollEnabled={false}
          />

          {/* Botón enviar */}
          <TouchableOpacity
            onPress={handleSend}
            style={[
              s.sendBtn,
              (!inputText.trim() || loading) && s.sendBtnDisabled,
            ]}
            disabled={!inputText.trim() || loading}
            activeOpacity={0.7}
          >
            <Text style={[
              s.sendBtnText,
              (!inputText.trim() || loading) && s.sendBtnTextDisabled,
            ]}>
              ↑
            </Text>
          </TouchableOpacity>
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

// ─── Estilos ──────────────────────────────────────────────────────────────────

function createStyles(t) {
  return StyleSheet.create({
    root: {
      flex: 1,
      backgroundColor: t.bg || '#000',
    },

    // Header
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      backgroundColor: t.surface || '#0a0a0a',
      paddingHorizontal: 16,
      paddingTop: 10,
      paddingBottom: 10,
      borderBottomWidth: 1,
      borderBottomColor: t.border || 'rgba(255,255,255,0.07)',
    },
    headerLeft: {
      flex: 1,
    },
    headerTitle: {
      fontSize: 17,
      fontWeight: '700',
      color: t.textPrimary || t.text || '#f4f4f5',
      letterSpacing: -0.3,
    },
    ollamaStatus: {
      flexDirection: 'row',
      alignItems: 'center',
      marginTop: 2,
    },
    statusDot: {
      width: 6,
      height: 6,
      borderRadius: 3,
      marginRight: 5,
    },
    statusText: {
      fontSize: 11,
      color: t.textMuted || '#52525b',
    },
    ctxText: {
      fontSize: 11,
      color: t.textMuted || '#52525b',
    },
    headerRight: {
      flexDirection: 'row',
      gap: 8,
    },
    headerBtn: {
      paddingHorizontal: 10,
      paddingVertical: 6,
      borderRadius: 6,
      borderWidth: 1,
      borderColor: t.border || 'rgba(255,255,255,0.07)',
      backgroundColor: t.card || '#111',
    },
    headerBtnText: {
      fontSize: 12,
      color: t.textSecond || t.textSecondary || '#a1a1aa',
    },

    // Barra de selector de modelo
    modelBar: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingHorizontal: 12,
      paddingVertical: 8,
      backgroundColor: t.surface || '#0a0a0a',
      borderBottomWidth: 1,
      borderBottomColor: t.border || 'rgba(255,255,255,0.07)',
      zIndex: 50,
      overflow: 'visible',  // permite que el dropdown salga del bounds
    },
    messageCount: {
      fontSize: 11,
      color: t.textMuted || '#52525b',
    },

    // Área de chat
    chatArea: {
      flex: 1,
      backgroundColor: t.bg || '#000',
    },
    messageList: {
      paddingTop: 12,
      paddingBottom: 8,
    },

    // Estado vacío
    centered: {
      flex: 1,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: 32,
      paddingBottom: 40,
    },
    emptyGlyph: {
      fontSize: 48,
      color: ACCENT_CHAT,
      marginBottom: 12,
      opacity: 0.6,
    },
    emptyTitle: {
      fontSize: 17,
      fontWeight: '700',
      color: t.textPrimary || t.text || '#f4f4f5',
      marginBottom: 6,
    },
    emptyText: {
      fontSize: 13,
      color: t.textMuted || '#52525b',
      fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
      marginBottom: 4,
    },
    emptyHint: {
      fontSize: 12,
      color: t.textMuted || '#52525b',
      textAlign: 'center',
      marginTop: 8,
    },

    // Barra de error
    errorBar: {
      flexDirection: 'row',
      alignItems: 'center',
      backgroundColor: t.errorDim || '#2d0707',
      paddingHorizontal: 14,
      paddingVertical: 8,
      borderTopWidth: 1,
      borderTopColor: (t.error || '#ef4444') + '44',
    },
    errorText: {
      flex: 1,
      fontSize: 12,
      color: t.error || '#ef4444',
    },
    errorDismiss: {
      fontSize: 18,
      color: t.error || '#ef4444',
      paddingLeft: 8,
    },

    // Footer
    footer: {
      backgroundColor: t.surface || '#0a0a0a',
      borderTopWidth: 1,
      borderTopColor: t.border || 'rgba(255,255,255,0.07)',
      paddingBottom: 8,  // espacio para la barra de nav Android
    },
    cancelBar: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: 14,
      paddingVertical: 8,
      gap: 8,
      borderBottomWidth: 1,
      borderBottomColor: t.border || 'rgba(255,255,255,0.07)',
    },
    cancelText: {
      fontSize: 12,
      color: ACCENT_OLLAMA,
    },
    inputRow: {
      flexDirection: 'row',
      alignItems: 'flex-end',
      paddingHorizontal: 12,
      paddingTop: 8,
      paddingBottom: 4,
      gap: 8,
    },
    input: {
      flex: 1,
      backgroundColor: t.overlay || '#1a1a1a',
      borderRadius: 12,
      borderWidth: 1,
      borderColor: t.border || 'rgba(255,255,255,0.07)',
      paddingHorizontal: 14,
      paddingTop: 11,
      paddingBottom: 11,
      fontSize: 14,
      color: t.textPrimary || t.text || '#f4f4f5',
      // Altura mínima del dedo
      minHeight: 44,
      maxHeight: 120,
    },
    sendBtn: {
      width: 44,
      height: 44,
      borderRadius: 22,
      backgroundColor: ACCENT_OLLAMA,
      alignItems: 'center',
      justifyContent: 'center',
    },
    sendBtnDisabled: {
      backgroundColor: t.card || '#111',
      borderWidth: 1,
      borderColor: t.border || 'rgba(255,255,255,0.07)',
    },
    sendBtnText: {
      fontSize: 18,
      fontWeight: '700',
      color: '#000',
    },
    sendBtnTextDisabled: {
      color: t.textMuted || '#52525b',
    },
  });
}
