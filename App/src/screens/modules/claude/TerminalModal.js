// src/screens/modules/claude/TerminalModal.js — v2.0.0 (S15c-fix)
// Terminal sin react-native-webview — solo componentes nativos RN
// Comunicación: WebSocket nativo del JS engine (sin deps) → Dashboard PTY :8081
// Colores ANSI: stripeados del output para mostrar texto limpio

import React, {
  useState, useEffect, useRef, useCallback,
} from 'react';
import {
  View, Text, TextInput, TouchableOpacity, ScrollView,
  StyleSheet, Modal, Animated, Dimensions, KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { useTheme } from '../../../theme/ThemeContext';
import { Icons }    from '../../../theme/icons';

const { height: SCREEN_H } = Dimensions.get('window');

// Elimina secuencias ANSI del texto para display limpio
function stripAnsi(str) {
  // eslint-disable-next-line no-control-regex
  return str.replace(/\x1B\[[0-9;]*[mGKHFABCDJsu]/g, '')
            .replace(/\x1B\][^\x07]*\x07/g, '')
            .replace(/\x1B[@-Z\\-_]/g, '')
            .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');
}

export function TerminalModal({ visible, onClose, wsUrl, title, projectDir }) {
  const { theme }     = useTheme();
  const s             = createStyles(theme);
  const slideAnim     = useRef(new Animated.Value(SCREEN_H)).current;
  const scrollRef     = useRef(null);
  const wsRef         = useRef(null);

  const [lines, setLines]     = useState([]);
  const [input, setInput]     = useState('');
  const [connected, setConnected] = useState(false);
  const [connMsg, setConnMsg] = useState('Conectando...');

  // Scroll al fondo cuando llegan líneas nuevas
  useEffect(() => {
    if (lines.length > 0) {
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: false }), 50);
    }
  }, [lines]);

  // Animación slide
  useEffect(() => {
    if (visible) {
      setLines([]);
      setInput('');
      setConnected(false);
      setConnMsg('Conectando...');
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
  }, [visible]);

  const addLine = useCallback((text) => {
    const clean = stripAnsi(text);
    if (!clean && text && text.trim()) return; // era solo ANSI, ignorar
    const parts = clean.split(/\r?\n/);
    setLines(prev => {
      const next = [...prev];
      // Si la última línea no terminó en \n, concatenar
      if (parts.length > 0 && next.length > 0 && !next[next.length - 1].endsWith('\n')) {
        next[next.length - 1] = next[next.length - 1] + parts[0];
        for (let i = 1; i < parts.length; i++) next.push(parts[i]);
      } else {
        for (const p of parts) next.push(p);
      }
      // Limitar buffer a 500 líneas
      return next.length > 500 ? next.slice(-500) : next;
    });
  }, []);

  const connectWs = useCallback(() => {
    if (wsRef.current) {
      try { wsRef.current.close(); } catch {}
    }
    const url = wsUrl || 'ws://127.0.0.1:8081';
    try {
      const ws = new WebSocket(url);
      wsRef.current = ws;

      ws.onopen = () => {
        setConnected(true);
        setConnMsg('');
        // Enviar init con proyecto
        ws.send(JSON.stringify({
          type: 'init',
          project_dir: projectDir || '',
          cols: 80,
          rows: 24,
        }));
      };

      ws.onmessage = (evt) => {
        addLine(evt.data);
      };

      ws.onerror = () => {
        setConnMsg('Error de conexión — ¿está el dashboard corriendo?');
      };

      ws.onclose = (evt) => {
        setConnected(false);
        if (evt.code !== 1000) {
          setConnMsg(`[Sesión terminada — código ${evt.code}]`);
        }
      };
    } catch (e) {
      setConnMsg(`Error: ${e.message}`);
    }
  }, [wsUrl, projectDir, addLine]);

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
    // Mostrar lo que se escribió
    addLine(`${text}`);
    wsRef.current.send(JSON.stringify({ type: 'input', data: text + '\n' }));
  }, [input, addLine]);

  const sendCtrlC = useCallback(() => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) return;
    wsRef.current.send(JSON.stringify({ type: 'input', data: '\x03' }));
    addLine('^C');
  }, [addLine]);

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

          {/* Header */}
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
              <TouchableOpacity onPress={sendCtrlC} style={s.ctrlCBtn}
                hitSlop={{ top:8, bottom:8, left:8, right:8 }}>
                <Text style={s.ctrlCText}>^C</Text>
              </TouchableOpacity>
              <TouchableOpacity onPress={handleClose} style={s.closeBtn}
                hitSlop={{ top:10, bottom:10, left:10, right:10 }}>
                <Text style={s.closeIcon}>{Icons.close}</Text>
              </TouchableOpacity>
            </View>
          </View>

          {/* Estado de conexión */}
          {(!connected || connMsg) && (
            <View style={s.connBar}>
              <Text style={[s.connText, { color: connected ? '#4ade80' : '#d4a027' }]}>
                {connected ? '● conectado' : connMsg || '○ desconectado'}
              </Text>
              {!connected && (
                <TouchableOpacity onPress={connectWs} hitSlop={{ top:8, bottom:8, left:8, right:8 }}>
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
                {line}
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
              placeholder="escribe un comando..."
              placeholderTextColor="#404040"
              autoCapitalize="none"
              autoCorrect={false}
              returnKeyType="send"
              blurOnSubmit={false}
              editable={connected}
            />
            <TouchableOpacity
              onPress={sendInput}
              disabled={!connected || !input.trim()}
              style={[s.sendBtn, (!connected || !input.trim()) && { opacity: 0.35 }]}
            >
              <Text style={s.sendIcon}>{Icons.send}</Text>
            </TouchableOpacity>
          </View>

        </Animated.View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

function createStyles(t) {
  return StyleSheet.create({
    overlay: {
      flex: 1,
      backgroundColor: 'rgba(0,0,0,0.85)',
      justifyContent: 'flex-end',
    },
    panel: {
      height: SCREEN_H * 0.88,
      backgroundColor: '#0a0a0a',
      borderTopLeftRadius: 16,
      borderTopRightRadius: 16,
      overflow: 'hidden',
      borderTopWidth: 1,
      borderColor: 'rgba(212,160,39,0.25)',
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: 14,
      paddingVertical: 10,
      backgroundColor: '#141414',
      borderBottomWidth: 1,
      borderBottomColor: 'rgba(255,255,255,0.07)',
    },
    dotsRow: { flexDirection: 'row', gap: 6, marginRight: 10 },
    dot: { width: 11, height: 11, borderRadius: 6 },
    headerTitle: {
      flex: 1, fontSize: 12, fontWeight: '600',
      color: '#808080', fontFamily: 'monospace', textAlign: 'center',
    },
    headerRight: { flexDirection: 'row', alignItems: 'center', gap: 8 },
    ctrlCBtn: {
      paddingHorizontal: 8, paddingVertical: 3,
      backgroundColor: '#1a1a1a', borderRadius: 4,
      borderWidth: 1, borderColor: '#333',
    },
    ctrlCText: { fontSize: 11, color: '#e06c75', fontWeight: '700', fontFamily: 'monospace' },
    closeBtn: { width: 28, height: 28, alignItems: 'center', justifyContent: 'center' },
    closeIcon: { fontSize: 18, color: '#505050', fontWeight: '700' },

    connBar: {
      flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
      paddingHorizontal: 12, paddingVertical: 6,
      backgroundColor: '#111',
      borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.05)',
    },
    connText:  { fontSize: 11, fontFamily: 'monospace' },
    retryText: { fontSize: 11, color: '#d4a027', fontWeight: '600' },

    output: { flex: 1, backgroundColor: '#0a0a0a' },
    outputContent: { padding: 12, paddingBottom: 8 },
    outputLine: {
      fontSize: 12,
      fontFamily: 'monospace',
      color: '#d0d0d0',
      lineHeight: 18,
    },

    inputRow: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingHorizontal: 12,
      paddingVertical: 8,
      backgroundColor: '#111',
      borderTopWidth: 1,
      borderTopColor: 'rgba(212,160,39,0.2)',
      gap: 8,
    },
    prompt: { fontSize: 16, color: '#d4a027', fontFamily: 'monospace', fontWeight: '700' },
    input: {
      flex: 1,
      fontSize: 13,
      fontFamily: 'monospace',
      color: '#e0e0e0',
      paddingVertical: 6,
      paddingHorizontal: 0,
    },
    sendBtn: {
      width: 34, height: 34, borderRadius: 8,
      backgroundColor: '#1a1400',
      borderWidth: 1, borderColor: 'rgba(212,160,39,0.4)',
      alignItems: 'center', justifyContent: 'center',
    },
    sendIcon: { fontSize: 14, color: '#d4a027', fontWeight: '700' },
  });
}
