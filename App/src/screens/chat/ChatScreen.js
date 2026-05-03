// App/src/screens/chat/ChatScreen.js
// v2.0.0 — S19
// Fix B2: guard Ollama — si ollama.running=false → pantalla bloqueada
// Sin cambios en lógica de chat existente

import { useState, useEffect, useRef, useCallback } from "react";
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Animated,
} from "react-native";
import { useTheme }      from "../../theme/ThemeContext";
import { useStatus }     from "../../hooks/useStatus";
import { useChatSession } from "../../hooks/useChatSession";

// ── Constantes ────────────────────────────────────────────────
const OLLAMA_ACCENT = "#4ade80";
const BASE_URL      = "http://127.0.0.1:8080";

// ── OllamaOfflineScreen ───────────────────────────────────────
// Pantalla que reemplaza el chat cuando Ollama está apagado
function OllamaOfflineScreen({ t, navigateToTab }) {
  const pulse = useRef(new Animated.Value(0.4)).current;

  useEffect(() => {
    const anim = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, { toValue: 1,   duration: 900, useNativeDriver: true }),
        Animated.timing(pulse, { toValue: 0.4, duration: 900, useNativeDriver: true }),
      ])
    );
    anim.start();
    return () => anim.stop();
  }, []);

  const s = offlineStyles(t);

  return (
    <View style={s.root}>
      {/* Ícono animado */}
      <Animated.View style={[s.iconWrap, { opacity: pulse }]}>
        <Text style={s.iconGlyph}>◎</Text>
      </Animated.View>

      {/* Texto */}
      <Text style={s.title}>Ollama inactivo</Text>
      <Text style={s.subtitle}>
        Activa Ollama para usar el chat con IA
      </Text>

      {/* Botón ir a Módulos */}
      <TouchableOpacity
        style={s.btn}
        onPress={() => navigateToTab && navigateToTab("modules")}
        activeOpacity={0.75}
      >
        <Text style={s.btnText}>Ir a Módulos  ›</Text>
      </TouchableOpacity>
    </View>
  );
}

function offlineStyles(t) {
  return StyleSheet.create({
    root: {
      flex: 1,
      backgroundColor: t.bg || "#0a0a0a",
      alignItems: "center",
      justifyContent: "center",
      paddingHorizontal: 32,
    },
    iconWrap: {
      width: 72,
      height: 72,
      borderRadius: 36,
      backgroundColor: (t.surface || "#161616"),
      borderWidth: 1,
      borderColor: "rgba(255,255,255,0.08)",
      alignItems: "center",
      justifyContent: "center",
      marginBottom: 24,
    },
    iconGlyph: {
      fontSize: 32,
      color: t.textMuted || "#555",
    },
    title: {
      fontSize: 20,
      fontWeight: "700",
      color: t.textPrimary || t.text || "#e8e8e8",
      letterSpacing: 0.2,
      marginBottom: 8,
      textAlign: "center",
    },
    subtitle: {
      fontSize: 14,
      color: t.textMuted || "#666",
      textAlign: "center",
      lineHeight: 20,
      marginBottom: 32,
    },
    btn: {
      paddingHorizontal: 24,
      paddingVertical: 12,
      borderRadius: 8,
      backgroundColor: t.surface || "#1a1a1a",
      borderWidth: 1,
      borderColor: OLLAMA_ACCENT + "44",
    },
    btnText: {
      fontSize: 14,
      fontWeight: "600",
      color: OLLAMA_ACCENT,
      letterSpacing: 0.3,
    },
  });
}

// ── ModelSelector ─────────────────────────────────────────────
function ModelSelector({ models, selected, onSelect, t }) {
  const [open, setOpen] = useState(false);
  const s = modelStyles(t);

  return (
    <View style={s.wrap}>
      <TouchableOpacity
        style={s.trigger}
        onPress={() => setOpen(o => !o)}
        activeOpacity={0.8}
      >
        <Text style={s.triggerText} numberOfLines={1}>
          {selected || "modelo"}
        </Text>
        <Text style={s.chevron}>{open ? "▲" : "▼"}</Text>
      </TouchableOpacity>

      {open && (
        <View style={s.dropdown}>
          {models.map(m => (
            <TouchableOpacity
              key={m}
              style={[s.item, m === selected && s.itemActive]}
              onPress={() => { onSelect(m); setOpen(false); }}
              activeOpacity={0.7}
            >
              <Text style={[s.itemText, m === selected && s.itemTextActive]}>
                {m === selected ? "✓  " : "    "}{m}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      )}
    </View>
  );
}

function modelStyles(t) {
  return StyleSheet.create({
    wrap:        { position: "relative", zIndex: 100 },
    trigger:     {
      flexDirection: "row",
      alignItems: "center",
      paddingHorizontal: 10,
      paddingVertical: 6,
      borderRadius: 6,
      backgroundColor: t.surface || "#1a1a1a",
      borderWidth: 1,
      borderColor: "rgba(255,255,255,0.08)",
      maxWidth: 160,
    },
    triggerText: { fontSize: 12, color: t.textSecond || "#9ca3af", flex: 1 },
    chevron:     { fontSize: 9, color: t.textMuted || "#555", marginLeft: 6 },
    dropdown:    {
      position: "absolute",
      top: "110%",
      left: 0,
      minWidth: 180,
      backgroundColor: t.card || "#1e1e1e",
      borderRadius: 8,
      borderWidth: 1,
      borderColor: "rgba(255,255,255,0.1)",
      overflow: "hidden",
      elevation: 8,
      shadowColor: "#000",
      shadowOpacity: 0.4,
      shadowRadius: 8,
      shadowOffset: { width: 0, height: 4 },
    },
    item:        { paddingHorizontal: 14, paddingVertical: 11 },
    itemActive:  { backgroundColor: OLLAMA_ACCENT + "18" },
    itemText:    { fontSize: 13, color: t.textSecond || "#9ca3af", fontFamily: Platform.OS === "android" ? "monospace" : "Courier" },
    itemTextActive: { color: OLLAMA_ACCENT },
  });
}

// ── ThinkingBubble ────────────────────────────────────────────
function ThinkingBubble({ t }) {
  const dot1 = useRef(new Animated.Value(0.3)).current;
  const dot2 = useRef(new Animated.Value(0.3)).current;
  const dot3 = useRef(new Animated.Value(0.3)).current;

  useEffect(() => {
    const anim = (dot, delay) =>
      Animated.loop(
        Animated.sequence([
          Animated.delay(delay),
          Animated.timing(dot, { toValue: 1,   duration: 350, useNativeDriver: true }),
          Animated.timing(dot, { toValue: 0.3, duration: 350, useNativeDriver: true }),
        ])
      );
    const a1 = anim(dot1, 0);
    const a2 = anim(dot2, 150);
    const a3 = anim(dot3, 300);
    a1.start(); a2.start(); a3.start();
    return () => { a1.stop(); a2.stop(); a3.stop(); };
  }, []);

  const s = thinkStyles(t);
  return (
    <View style={s.row}>
      <View style={s.bubble}>
        {[dot1, dot2, dot3].map((d, i) => (
          <Animated.View key={i} style={[s.dot, { opacity: d }]} />
        ))}
      </View>
    </View>
  );
}

function thinkStyles(t) {
  return StyleSheet.create({
    row:    { flexDirection: "row", marginVertical: 4, paddingHorizontal: 12 },
    bubble: {
      flexDirection: "row",
      alignItems: "center",
      gap: 5,
      paddingHorizontal: 14,
      paddingVertical: 10,
      backgroundColor: t.surface || "#1a1a1a",
      borderRadius: 12,
      borderTopLeftRadius: 2,
      borderWidth: 1,
      borderColor: "rgba(255,255,255,0.06)",
    },
    dot: {
      width: 6, height: 6, borderRadius: 3,
      backgroundColor: OLLAMA_ACCENT,
    },
  });
}

// ── MessageBubble ─────────────────────────────────────────────
const MessageBubble = ({ item, t }) => {
  const isUser = item.role === "user";
  const s      = bubbleStyles(t, isUser);
  return (
    <View style={s.row}>
      <View style={s.bubble}>
        <Text style={s.text}>{item.content}</Text>
        {item.ts && <Text style={s.ts}>{item.ts}</Text>}
      </View>
    </View>
  );
};

function bubbleStyles(t, isUser) {
  return StyleSheet.create({
    row: {
      flexDirection: "row",
      justifyContent: isUser ? "flex-end" : "flex-start",
      marginVertical: 3,
      paddingHorizontal: 12,
    },
    bubble: {
      maxWidth: "80%",
      paddingHorizontal: 14,
      paddingVertical: 9,
      backgroundColor: isUser
        ? (t.chatUser    || "#1a2e1a")
        : (t.chatAssist || "#1a1a1a"),
      borderRadius: 14,
      borderTopRightRadius: isUser ? 2 : 14,
      borderTopLeftRadius:  isUser ? 14 : 2,
      borderWidth: 1,
      borderColor: isUser
        ? OLLAMA_ACCENT + "33"
        : "rgba(255,255,255,0.06)",
    },
    text: {
      fontSize: 14,
      lineHeight: 20,
      color: t.textPrimary || t.text || "#e8e8e8",
    },
    ts: {
      fontSize: 10,
      color: t.textMuted || "#555",
      marginTop: 4,
      textAlign: isUser ? "right" : "left",
    },
  });
}

// ── ChatScreen — Exportación named (REGLA ABSOLUTA) ───────────
export function ChatScreen({ model: modelProp, numCtx: numCtxProp, navigateToTab }) {
  const { theme: t }   = useTheme();
  const { status }     = useStatus();

  // ── Guard: verificar si Ollama está corriendo ─────────────────
  // status.modules es array — buscar módulo ollama
  const ollamaModule = status?.modules?.find(m => m.id === "ollama");
  const ollamaRunning = ollamaModule?.running === true;

  // ── Estado del chat ──────────────────────────────────────────
  const [models,   setModels]   = useState([]);
  const [model,    setModel]    = useState(modelProp || "qwen2.5:0.5b");
  const [numCtx]                = useState(numCtxProp || 2048);
  const [input,    setInput]    = useState("");
  const [messages, setMessages] = useState([]);

  const flatRef  = useRef(null);
  const chatId   = useRef("app_" + Date.now()).current;

  const {
    loading,
    sendMessage,
    cancelRequest,
  } = useChatSession({ model, numCtx, chatId, BASE_URL });

  // Cargar modelos disponibles cuando Ollama esté activo
  useEffect(() => {
    if (!ollamaRunning) return;
    fetch(`${BASE_URL}/api/ollama/models`, { signal: AbortSignal.timeout(5000) })
      .then(r => r.json())
      .then(d => {
        const names = (d.models || []).map(m => m.name);
        if (names.length > 0) {
          setModels(names);
          if (!names.includes(model)) setModel(names[0]);
        }
      })
      .catch(() => {});
  }, [ollamaRunning]);

  // Scroll al final cuando llegan mensajes
  useEffect(() => {
    if (messages.length > 0) {
      setTimeout(() => flatRef.current?.scrollToEnd({ animated: true }), 100);
    }
  }, [messages]);

  // Actualizar modelo si viene de OllamaScreen via navigateToTab
  useEffect(() => {
    if (modelProp) setModel(modelProp);
  }, [modelProp]);

  const handleSend = useCallback(async () => {
    const text = input.trim();
    if (!text || loading) return;
    setInput("");

    const userMsg = {
      id:      Date.now().toString(),
      role:    "user",
      content: text,
      ts:      new Date().toLocaleTimeString("es", { hour: "2-digit", minute: "2-digit" }),
    };
    setMessages(prev => [...prev, userMsg]);

    const reply = await sendMessage(text, messages);
    if (reply) {
      const botMsg = {
        id:      Date.now().toString() + "_b",
        role:    "assistant",
        content: reply,
        ts:      new Date().toLocaleTimeString("es", { hour: "2-digit", minute: "2-digit" }),
      };
      setMessages(prev => [...prev, botMsg]);
    }
  }, [input, loading, messages, sendMessage]);

  const s = chatStyles(t);

  // ── GUARD — Ollama apagado ────────────────────────────────────
  if (!ollamaRunning) {
    return <OllamaOfflineScreen t={t} navigateToTab={navigateToTab} />;
  }

  // ── UI normal del chat ────────────────────────────────────────
  return (
    <KeyboardAvoidingView
      style={s.root}
      behavior={Platform.OS === "ios" ? "padding" : "height"}
    >
      {/* Header */}
      <View style={s.header}>
        <View style={s.headerLeft}>
          <View style={s.statusDot} />
          <Text style={s.headerTitle}>Chat IA</Text>
        </View>
        <View style={s.headerRight}>
          <ModelSelector
            models={models.length > 0 ? models : [model]}
            selected={model}
            onSelect={setModel}
            t={t}
          />
          <TouchableOpacity
            style={s.clearBtn}
            onPress={() => setMessages([])}
            activeOpacity={0.7}
          >
            <Text style={s.clearBtnText}>⌫</Text>
          </TouchableOpacity>
        </View>
      </View>

      {/* Sub-header: ctx info */}
      <View style={s.subHeader}>
        <Text style={s.ctxLabel}>
          Ollama activo · {(numCtx / 1000).toFixed(0)}K ctx
        </Text>
      </View>

      {/* Mensajes */}
      <FlatList
        ref={flatRef}
        data={messages}
        keyExtractor={item => item.id}
        renderItem={({ item }) => <MessageBubble item={item} t={t} />}
        contentContainerStyle={s.msgList}
        ListEmptyComponent={
          <View style={s.emptyWrap}>
            <Text style={s.emptyTitle}>Chat con Ollama</Text>
            <Text style={s.emptySubtitle}>
              Modelo: {model}{"\n"}Escribe un mensaje para comenzar
            </Text>
          </View>
        }
        ListFooterComponent={loading ? <ThinkingBubble t={t} /> : null}
        removeClippedSubviews
        initialNumToRender={15}
      />

      {/* Barra cancelar durante loading */}
      {loading && (
        <TouchableOpacity style={s.cancelBar} onPress={cancelRequest} activeOpacity={0.8}>
          <Text style={s.cancelBarText}>↻  Ollama procesando... · toca para cancelar</Text>
        </TouchableOpacity>
      )}

      {/* Input */}
      <View style={s.inputRow}>
        <TextInput
          style={s.input}
          value={input}
          onChangeText={setInput}
          placeholder={`Escribe a ${model}...`}
          placeholderTextColor={t.textMuted || "#555"}
          multiline
          editable={!loading}
          onSubmitEditing={handleSend}
          blurOnSubmit={false}
        />
        <TouchableOpacity
          style={[s.sendBtn, (!input.trim() || loading) && s.sendBtnDisabled]}
          onPress={handleSend}
          disabled={!input.trim() || loading}
          activeOpacity={0.75}
        >
          <Text style={s.sendIcon}>↑</Text>
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

// ── Estilos del chat ──────────────────────────────────────────
function chatStyles(t) {
  return StyleSheet.create({
    root: {
      flex: 1,
      backgroundColor: t.bg || "#0a0a0a",
    },
    header: {
      flexDirection: "row",
      alignItems: "center",
      justifyContent: "space-between",
      paddingHorizontal: 16,
      paddingVertical: 12,
      backgroundColor: t.surface || "#111",
      borderBottomWidth: 1,
      borderBottomColor: "rgba(255,255,255,0.06)",
    },
    headerLeft: {
      flexDirection: "row",
      alignItems: "center",
      gap: 8,
    },
    statusDot: {
      width: 8,
      height: 8,
      borderRadius: 4,
      backgroundColor: OLLAMA_ACCENT,
    },
    headerTitle: {
      fontSize: 16,
      fontWeight: "700",
      color: t.textPrimary || t.text || "#e8e8e8",
      letterSpacing: 0.2,
    },
    headerRight: {
      flexDirection: "row",
      alignItems: "center",
      gap: 8,
    },
    clearBtn: {
      width: 32,
      height: 32,
      borderRadius: 6,
      backgroundColor: t.card || "#1e1e1e",
      alignItems: "center",
      justifyContent: "center",
      borderWidth: 1,
      borderColor: "rgba(255,255,255,0.07)",
    },
    clearBtnText: {
      fontSize: 14,
      color: t.textMuted || "#555",
    },
    subHeader: {
      paddingHorizontal: 16,
      paddingVertical: 5,
      borderBottomWidth: 1,
      borderBottomColor: "rgba(255,255,255,0.04)",
    },
    ctxLabel: {
      fontSize: 11,
      color: OLLAMA_ACCENT,
      letterSpacing: 0.3,
    },
    msgList: {
      paddingVertical: 12,
      flexGrow: 1,
    },
    emptyWrap: {
      flex: 1,
      alignItems: "center",
      justifyContent: "center",
      paddingVertical: 80,
      paddingHorizontal: 32,
    },
    emptyTitle: {
      fontSize: 18,
      fontWeight: "700",
      color: t.textPrimary || t.text || "#e8e8e8",
      marginBottom: 8,
      textAlign: "center",
    },
    emptySubtitle: {
      fontSize: 13,
      color: t.textMuted || "#666",
      textAlign: "center",
      lineHeight: 20,
    },
    cancelBar: {
      paddingVertical: 10,
      paddingHorizontal: 16,
      backgroundColor: t.surface || "#111",
      borderTopWidth: 1,
      borderTopColor: "rgba(255,255,255,0.06)",
      alignItems: "center",
    },
    cancelBarText: {
      fontSize: 12,
      color: OLLAMA_ACCENT,
      letterSpacing: 0.3,
    },
    inputRow: {
      flexDirection: "row",
      alignItems: "flex-end",
      paddingHorizontal: 12,
      paddingVertical: 10,
      backgroundColor: t.surface || "#111",
      borderTopWidth: 1,
      borderTopColor: "rgba(255,255,255,0.06)",
      gap: 8,
    },
    input: {
      flex: 1,
      minHeight: 40,
      maxHeight: 100,
      paddingHorizontal: 14,
      paddingVertical: 10,
      backgroundColor: t.card || "#1e1e1e",
      borderRadius: 10,
      borderWidth: 1,
      borderColor: "rgba(255,255,255,0.08)",
      fontSize: 14,
      color: t.textPrimary || t.text || "#e8e8e8",
    },
    sendBtn: {
      width: 40,
      height: 40,
      borderRadius: 10,
      backgroundColor: OLLAMA_ACCENT,
      alignItems: "center",
      justifyContent: "center",
    },
    sendBtnDisabled: {
      backgroundColor: "rgba(255,255,255,0.08)",
    },
    sendIcon: {
      fontSize: 18,
      color: "#000",
      fontWeight: "700",
    },
  });
}
