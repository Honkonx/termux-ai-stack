// src/screens/modules/claude/TerminalModal.js — v3.0.0 (S16)
// Fixes:
//   1. stripAnsi completo — cubre todas las secuencias Claude Code
//   2. \r handling correcto — carriage return sobreescribe línea actual
//   3. Detecta URLs OAuth → botón "Abrir en navegador"
//   4. Colores fijos oscuros — terminal siempre negra sin importar el tema
//   5. Texto legible en todos los temas

import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  View, Text, TextInput, TouchableOpacity, ScrollView,
  StyleSheet, Modal, Animated, Dimensions, KeyboardAvoidingView,
  Platform, Linking,
} from 'react-native';
import { Icons } from '../../../theme/icons';

const { height: SCREEN_H } = Dimensions.get('window');

// ─── ANSI striper completo ────────────────────────────────────────────────────
// Cubre TODAS las secuencias que Claude Code emite:
// - CSI sequences: ESC [ ... (colores, cursor, borrado, modos)
// - OSC sequences: ESC ] ... BEL/ST  (títulos de ventana)
// - DCS sequences: ESC P ... ST
// - SS2/SS3: ESC N / ESC O
// - Caracteres de control: NUL, BEL, BS, SO, SI, DEL, etc.
// - Bracketed paste mode: ESC[?2004h/l
// - Modo pantalla alternativa: ESC[?1049h/l, ESC[?47h/l
function stripAnsi(raw) {
  return raw
    // OSC: ESC ] ... (BEL o ESC \)
    .replace(/\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)/g, '')
    // DCS: ESC P ... ESC \
    .replace(/\x1B P[^\x1B]*\x1B\\/g, '')
    // CSI: ESC [ ... letra final (incluyendo secuencias con ? y >)
    .replace(/\x1B\[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]/g, '')
    // ESC seguido de un carácter simple (SS2, SS3, RIS, etc.)
    .replace(/\x1B[\x40-\x5F\x60-\x7E]/g, '')
    // Caracteres de control no imprimibles (excepto \n, \r, \t)
    .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
}

// ─── Procesador de líneas con \r correcto ─────────────────────────────────────
// \r sin \n = sobreescribir la línea actual (como hace una terminal real)
// \r\n = nueva línea normal
function processChunk(raw, prevLines) {
  const clean = stripAnsi(raw);
  const lines = [...prevLines];

  let i = 0;
  let current = lines.length > 0 ? lines[lines.length - 1] : '';
  if (lines.length > 0) lines.pop();

  while (i < clean.length) {
    const ch = clean[i];
    if (ch === '\r' && clean[i + 1] === '\n') {
      // CRLF → nueva línea
      lines.push(current);
      current = '';
      i += 2;
    } else if (ch === '\r') {
      // CR solo → volver al inicio de la línea (sobreescribir)
      current = '';
      i++;
    } else if (ch === '\n') {
      lines.push(current);
      current = '';
      i++;
    } else {
      current += ch;
      i++;
    }
  }
  lines.push(current);

  // Buffer máx 600 líneas
  return lines.length > 600 ? lines.slice(-600) : lines;
}

// ─── Detector de URLs OAuth/HTTPS ────────────────────────────────────────────
const URL_REGEX = /https?:\/\/[^\s\])"']+/g;

function extractUrls(lines) {
  const urls = [];
  for (const line of lines) {
    const matches = line.match(URL_REGEX);
    if (matches) urls.push(...matches);
  }
  return urls;
}

// ─── Componente ───────────────────────────────────────────────────────────────
export function TerminalModal({ visible, onClose, wsUrl, title, projectDir }) {
  const slideAnim  = useRef(new Animated.Value(SCREEN_H)).current;
  const scrollRef  = useRef(null);
  const wsRef      = useRef(null);
  const linesRef   = useRef([]); // ref para evitar closures stale

  const [lines, setLines]         = useState([]);
  const [input, setInput]         = useState('');
  const [connected, setConnected] = useState(false);
  const [connMsg, setConnMsg]     = useState('Conectando...');
  const [oauthUrl, setOauthUrl]   = useState(null); // URL detectada para OAuth

  // Auto-scroll
  useEffect(() => {
    if (lines.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: false }), 40);
    }
    // Detectar URL OAuth en las últimas líneas
    const recent = lines.slice(-20);
    const urls   = extractUrls(recent);
    const oauth  = urls.find(u =>
      u.includes('claude.com') || u.includes('anthropic.com') ||
      u.includes('oauth') || u.includes('authorize')
    );
    if (oauth && oauth !== oauthUrl) setOauthUrl(oauth);
  }, [lines]);

  // Slide + conexión WS
  useEffect(() => {
    if (visible) {
      linesRef.current = [];
      setLines([]);
      setInput('');
      setConnected(false);
      setConnMsg('Conectando...');
      setOauthUrl(null);
      Animated.spring(slideAnim, {
        toValue: 0, tension: 65, friction: 11, useNativeDriver: true,
      }).start();
      connectWs();
    } else {
      Animated.timing(slideAnim, {
        toValue: SCREEN_H, duration: 220, useNativeDriver: true,
      }).start();
      disconnectWs();
    }
    return () => disconnectWs();
  }, [visible]);

  const appendChunk = useCallback((raw) => {
    linesRef.current = processChunk(raw, linesRef.current);
    setLines([...linesRef.current]);
  }, []);

  const connectWs = useCallback(() => {
    if (wsRef.current) { try { wsRef.current.close(); } catch {} }
    // Pasar project_dir en query string — el servidor lo lee desde el handshake HTTP
    const base = wsUrl || 'ws://127.0.0.1:8081';
    const proj = projectDir ? encodeURIComponent(projectDir) : '';
    const url  = proj ? `${base}?project=${proj}&cols=80&rows=30` : `${base}?cols=80&rows=30`;
    try {
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        setConnected(true);
        setConnMsg('');
        // Sin mensaje init — project_dir ya fue enviado en la URL
      };

      ws.onmessage = (evt) => appendChunk(evt.data);

      ws.onerror = () => {
        setConnMsg('Sin conexión — ¿dashboard corriendo en :8081?');
      };

      ws.onclose = (evt) => {
        setConnected(false);
        if (evt.code !== 1000) {
          appendChunk(`\n[sesión terminada]\n`);
        }
      };
    } catch (e) {
      setConnMsg(`Error WS: ${e.message}`);
    }
  }, [wsUrl, projectDir, appendChunk]);

  const disconnectWs = useCallback(() => {
    if (wsRef.current) {
      try { wsRef.current.close(1000); } catch {}
      wsRef.current = null;
    }
    setConnected(false);
  }, []);

  const sendInput = useCallback(() => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
    const text = input;
    setInput('');
    wsRef.current.send(JSON.stringify({ type: 'input', data: text + '\n' }));
  }, [input]);

  const sendCtrlC = useCallback(() => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
    wsRef.current.send(JSON.stringify({ type: 'input', data: '\x03' }));
  }, []);

  const sendRaw = useCallback((data) => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
    wsRef.current.send(JSON.stringify({ type: 'input', data }));
  }, []);

  const openOAuth = useCallback(() => {
    if (oauthUrl) Linking.openURL(oauthUrl).catch(() => {});
  }, [oauthUrl]);

  const handleClose = useCallback(() => {
    disconnectWs();
    Animated.timing(slideAnim, {
      toValue: SCREEN_H, duration: 220, useNativeDriver: true,
    }).start(() => onClose());
  }, [onClose, disconnectWs]);

  if (!visible) return null;

  return (
    <Modal visible={visible} transparent animationType="none" onRequestClose={handleClose}>
      <KeyboardAvoidingView
        style={s.overlay}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
        <Animated.View style={[s.panel, { transform: [{ translateY: slideAnim }] }]}>

          {/* Header — siempre oscuro */}
          <View style={s.header}>
            <View style={s.dotsRow}>
              <View style={[s.dot, { backgroundColor: '#e06c75' }]} />
              <View style={[s.dot, { backgroundColor: '#d4a027' }]} />
              <View style={[s.dot, { backgroundColor: '#4ade80' }]} />
            </View>
            <Text style={s.headerTitle} numberOfLines={1}>
              {title || 'Claude Code'}
            </Text>
            <View style={s.headerRight}>
              {/* Botones de teclado rápido */}
              <TouchableOpacity onPress={() => sendRaw('\t')} style={s.keyBtn}
                hitSlop={{ top:6, bottom:6, left:4, right:4 }}>
                <Text style={s.keyBtnText}>TAB</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={sendCtrlC} style={s.keyBtn}
                hitSlop={{ top:6, bottom:6, left:4, right:4 }}>
                <Text style={[s.keyBtnText, { color: '#e06c75' }]}>^C</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={handleClose} style={s.closeBtn}
                hitSlop={{ top:10, bottom:10, left:10, right:10 }}>
                <Text style={s.closeIcon}>{Icons.close}</Text>
              </TouchableOpacity>
            </View>
          </View>

          {/* Banner OAuth — aparece cuando Claude Code muestra una URL */}
          {oauthUrl && (
            <TouchableOpacity onPress={openOAuth} style={s.oauthBanner} activeOpacity={0.8}>
              <Text style={s.oauthIcon}>🔐</Text>
              <View style={{ flex: 1 }}>
                <Text style={s.oauthTitle}>Autorizar Claude Code</Text>
                <Text style={s.oauthSub} numberOfLines={1}>Toca para abrir el navegador y verificar tu cuenta</Text>
              </View>
              <Text style={s.oauthArrow}>›</Text>
            </TouchableOpacity>
          )}

          {/* Barra de estado de conexión */}
          {(!connected || connMsg) && (
            <View style={s.connBar}>
              <Text style={[s.connText, { color: connected ? '#4ade80' : '#d4a027' }]}>
                {connected ? '● conectado' : connMsg || '○ desconectado'}
              </Text>
              {!connected && (
                <TouchableOpacity onPress={connectWs}
                  hitSlop={{ top:8, bottom:8, left:8, right:8 }}>
                  <Text style={s.retryText}>{Icons.refresh} Reconectar</Text>
                </TouchableOpacity>
              )}
            </View>
          )}

          {/* Output terminal */}
          <ScrollView
            ref={scrollRef}
            style={s.output}
            contentContainerStyle={s.outputContent}
            keyboardShouldPersistTaps="handled"
            showsVerticalScrollIndicator={false}
          >
            {lines.map((line, i) => (
              <Text key={i} style={s.outputLine} selectable>
                {line || ' '}
              </Text>
            ))}
          </ScrollView>

          {/* Input */}
          <View style={s.inputRow}>
            <Text style={s.prompt}>›</Text>
            <TextInput
              style={s.input}
              value={input}
              onChangeText={setInput}
              onSubmitEditing={sendInput}
              placeholder="escribe aquí..."
              placeholderTextColor="#404040"
              autoCapitalize="none"
              autoCorrect={false}
              spellCheck={false}
              returnKeyType="send"
              blurOnSubmit={false}
              editable={connected}
            />
            <TouchableOpacity
              onPress={sendInput}
              disabled={!connected || !input.trim()}
              style={[s.sendBtn, (!connected || !input.trim()) && { opacity: 0.3 }]}
            >
              <Text style={s.sendIcon}>{Icons.send}</Text>
            </TouchableOpacity>
          </View>

        </Animated.View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

// ─── Estilos — siempre oscuros, independientes del tema de la app ─────────────
const s = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.88)',
    justifyContent: 'flex-end',
  },
  panel: {
    height: SCREEN_H * 0.90,
    backgroundColor: '#0d0d0d',
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    overflow: 'hidden',
    borderTopWidth: 1,
    borderColor: 'rgba(212,160,39,0.3)',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 9,
    backgroundColor: '#181818',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.06)',
  },
  dotsRow:     { flexDirection: 'row', gap: 6, marginRight: 10 },
  dot:         { width: 12, height: 12, borderRadius: 6 },
  headerTitle: {
    flex: 1, fontSize: 12, fontWeight: '600',
    color: '#707070', fontFamily: 'monospace', textAlign: 'center',
  },
  headerRight: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  keyBtn: {
    paddingHorizontal: 7, paddingVertical: 3,
    backgroundColor: '#222', borderRadius: 4,
    borderWidth: 1, borderColor: '#333',
  },
  keyBtnText: { fontSize: 10, color: '#aaa', fontWeight: '700', fontFamily: 'monospace' },
  closeBtn:   { width: 28, height: 28, alignItems: 'center', justifyContent: 'center' },
  closeIcon:  { fontSize: 18, color: '#555', fontWeight: '700' },

  // Banner OAuth
  oauthBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 14,
    paddingVertical: 10,
    backgroundColor: '#1a1500',
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(212,160,39,0.4)',
  },
  oauthIcon:  { fontSize: 18 },
  oauthTitle: { fontSize: 13, fontWeight: '700', color: '#d4a027' },
  oauthSub:   { fontSize: 11, color: '#a07820', marginTop: 1 },
  oauthArrow: { fontSize: 20, color: '#d4a027', fontWeight: '700' },

  // Barra conexión
  connBar: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 12, paddingVertical: 5,
    backgroundColor: '#141414',
    borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.04)',
  },
  connText:  { fontSize: 11, fontFamily: 'monospace', color: '#888' },
  retryText: { fontSize: 11, color: '#d4a027', fontWeight: '600' },

  // Output
  output:        { flex: 1, backgroundColor: '#0d0d0d' },
  outputContent: { padding: 10, paddingBottom: 6 },
  outputLine: {
    fontSize: 13,
    fontFamily: 'monospace',
    color: '#e8e8e8',       // blanco cálido — legible en fondo #0d0d0d
    lineHeight: 20,
    letterSpacing: 0,
  },

  // Input
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: '#181818',
    borderTopWidth: 1,
    borderTopColor: 'rgba(212,160,39,0.25)',
    gap: 8,
  },
  prompt: { fontSize: 16, color: '#d4a027', fontFamily: 'monospace', fontWeight: '700' },
  input: {
    flex: 1,
    fontSize: 14,
    fontFamily: 'monospace',
    color: '#f0f0f0',
    paddingVertical: 6,
  },
  sendBtn: {
    width: 36, height: 36, borderRadius: 8,
    backgroundColor: '#1a1400',
    borderWidth: 1, borderColor: 'rgba(212,160,39,0.45)',
    alignItems: 'center', justifyContent: 'center',
  },
  sendIcon: { fontSize: 14, color: '#d4a027', fontWeight: '700' },
});
