// src/screens/modules/claude/TerminalModal.js — v1.0.0 (S15)
// Terminal embebida usando WebView + xterm.js + WebSocket PTY
// Sin dependencias nativas — solo WebView (incluida en Expo SDK 50)

import React, { useRef, useEffect, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet,
  Modal, Animated, Dimensions,
} from 'react-native';
import { WebView } from 'react-native-webview';
import { useTheme } from '../../../theme/ThemeContext';
import { Icons }    from '../../../theme/icons';

const { height: SCREEN_H } = Dimensions.get('window');

// ─── HTML inline con xterm.js desde CDN ──────────────────────────────────────
// Se inyecta la IP y puerto del WS dinámicamente
function buildTerminalHTML(wsUrl, projectDir) {
  return `<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html, body { width:100%; height:100%; background:#0a0a0a; overflow:hidden; }
  #terminal { width:100%; height:100%; }
  .xterm { height:100% !important; }
  .xterm-viewport { overflow-y:auto !important; }
</style>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/xterm/5.3.0/xterm.min.css"/>
</head>
<body>
<div id="terminal"></div>
<script src="https://cdnjs.cloudflare.com/ajax/libs/xterm/5.3.0/xterm.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/xterm/5.3.0/addon-fit/addon-fit.min.js"></script>
<script>
(function() {
  var WS_URL = "${wsUrl}";

  var term = new Terminal({
    cursorBlink: true,
    fontSize: 13,
    fontFamily: 'monospace',
    theme: {
      background: '#0a0a0a',
      foreground: '#e0e0e0',
      cursor:     '#d4a027',
      black:      '#1a1a1a',
      red:        '#e06c75',
      green:      '#4ade80',
      yellow:     '#d4a027',
      blue:       '#58a6ff',
      magenta:    '#c084fc',
      cyan:       '#22d3ee',
      white:      '#e0e0e0',
      brightBlack: '#404040',
      brightGreen: '#86efac',
    },
    scrollback: 2000,
    convertEol: true,
  });

  var fitAddon = new FitAddon.FitAddon();
  term.loadAddon(fitAddon);
  term.open(document.getElementById('terminal'));
  fitAddon.fit();

  window.addEventListener('resize', function() { fitAddon.fit(); });

  // Conectar WebSocket
  var ws;
  var reconnectDelay = 1000;

  function connect() {
    term.write('\\x1b[33mConectando a ' + WS_URL + '...\\x1b[0m\\r\\n');
    try {
      ws = new WebSocket(WS_URL);
    } catch(e) {
      term.write('\\x1b[31mError al crear WebSocket: ' + e.message + '\\x1b[0m\\r\\n');
      return;
    }

    ws.onopen = function() {
      reconnectDelay = 1000;
      // Primer mensaje: init con proyecto y dimensiones
      var initMsg = {
        type: 'init',
        project_dir: PROJECT_DIR,
        cols: term.cols,
        rows: term.rows,
      };
      ws.send(JSON.stringify(initMsg));
      var proj = PROJECT_DIR ? PROJECT_DIR.split('/').pop() : null;
      if (proj) {
        term.write('\\x1b[32m✓ Iniciando Claude Code en \\x1b[33m' + proj + '\\x1b[0m\\r\\n');
      } else {
        term.write('\\x1b[32m✓ Iniciando Claude Code\\x1b[0m\\r\\n');
      }
    };

    ws.onmessage = function(evt) {
      term.write(evt.data);
    };

    ws.onerror = function(e) {
      term.write('\\x1b[31m[WS Error]\\x1b[0m\\r\\n');
    };

    ws.onclose = function(evt) {
      term.write('\\x1b[33m[Sesión terminada — código ' + evt.code + ']\\x1b[0m\\r\\n');
      if (evt.code !== 1000) {
        setTimeout(function() {
          term.write('\\x1b[33mReconectando...\\x1b[0m\\r\\n');
          connect();
        }, reconnectDelay);
        reconnectDelay = Math.min(reconnectDelay * 2, 10000);
      }
    };
  }

  // Input del usuario → WS
  term.onData(function(data) {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type:'input', data: data }));
    }
  });

  // Resize → notificar al servidor
  term.onResize(function(size) {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type:'resize', cols: size.cols, rows: size.rows }));
    }
  });

  // Notificar a React Native cuando hay actividad
  term.onData(function() {
    if (window.ReactNativeWebView) {
      window.ReactNativeWebView.postMessage(JSON.stringify({ type:'activity' }));
    }
  });

  // Recibir project_dir del contexto
  var PROJECT_DIR = "${projectDir}";

  connect();
})();
</script>
</body>
</html>`;
}

// ─── Componente ───────────────────────────────────────────────────────────────
export function TerminalModal({ visible, onClose, wsUrl, title, projectDir }) {
  const { theme }    = useTheme();
  const s            = createStyles(theme);
  const slideAnim    = useRef(new Animated.Value(SCREEN_H)).current;
  const webviewRef   = useRef(null);

  // Animación slide-up al abrir
  useEffect(() => {
    if (visible) {
      Animated.spring(slideAnim, {
        toValue: 0,
        tension: 65,
        friction: 11,
        useNativeDriver: true,
      }).start();
    } else {
      Animated.timing(slideAnim, {
        toValue: SCREEN_H,
        duration: 250,
        useNativeDriver: true,
      }).start();
    }
  }, [visible]);

  const handleClose = useCallback(() => {
    Animated.timing(slideAnim, {
      toValue: SCREEN_H,
      duration: 220,
      useNativeDriver: true,
    }).start(() => onClose());
  }, [onClose]);

  const handleMessage = useCallback((event) => {
    // Mensajes del WebView (actividad, errores, etc.)
    try {
      const msg = JSON.parse(event.nativeEvent.data);
      // Extender aquí si se necesita comunicación bidireccional adicional
    } catch {}
  }, []);

  if (!visible) return null;

  const html = buildTerminalHTML(wsUrl || 'ws://127.0.0.1:8081', projectDir || '');

  return (
    <Modal
      visible={visible}
      transparent
      animationType="none"
      onRequestClose={handleClose}
    >
      <View style={s.overlay}>
        <Animated.View
          style={[s.panel, { transform: [{ translateY: slideAnim }] }]}
        >
          {/* Header */}
          <View style={s.header}>
            <View style={s.headerLeft}>
              <View style={s.termDot} />
              <View style={[s.termDot, { backgroundColor: '#d4a027' }]} />
              <View style={[s.termDot, { backgroundColor: '#4ade80' }]} />
            </View>
            <Text style={s.headerTitle} numberOfLines={1}>
              {title || 'Terminal · Claude Code'}
            </Text>
            <TouchableOpacity
              onPress={handleClose}
              style={s.closeBtn}
              hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
            >
              <Text style={s.closeIcon}>{Icons.close}</Text>
            </TouchableOpacity>
          </View>

          {/* WebView con xterm.js */}
          <WebView
            ref={webviewRef}
            source={{ html }}
            style={s.webview}
            originWhitelist={['*']}
            onMessage={handleMessage}
            javaScriptEnabled
            domStorageEnabled
            allowFileAccess
            mixedContentMode="always"
            // Permitir WebSockets a IP local
            allowUniversalAccessFromFileURLs
            onError={(e) => console.warn('WebView error:', e.nativeEvent)}
          />
        </Animated.View>
      </View>
    </Modal>
  );
}

// ─── Estilos ──────────────────────────────────────────────────────────────────
function createStyles(t) {
  return StyleSheet.create({
    overlay: {
      flex: 1,
      backgroundColor: 'rgba(0,0,0,0.82)',
      justifyContent: 'flex-end',
    },
    panel: {
      height: SCREEN_H * 0.88,
      backgroundColor: '#0a0a0a',
      borderTopLeftRadius: 16,
      borderTopRightRadius: 16,
      overflow: 'hidden',
      borderTopWidth: 1,
      borderColor: 'rgba(212,160,39,0.25)', // ámbar Claude sutil
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
    headerLeft: {
      flexDirection: 'row',
      gap: 6,
      marginRight: 10,
    },
    termDot: {
      width: 11, height: 11, borderRadius: 6,
      backgroundColor: '#e06c75',
    },
    headerTitle: {
      flex: 1,
      fontSize: 12,
      fontWeight: '600',
      color: '#a0a0a0',
      fontFamily: 'monospace',
      textAlign: 'center',
    },
    closeBtn: {
      width: 28, height: 28,
      alignItems: 'center', justifyContent: 'center',
    },
    closeIcon: {
      fontSize: 18,
      color: '#606060',
      fontWeight: '700',
    },
    webview: {
      flex: 1,
      backgroundColor: '#0a0a0a',
    },
  });
}
