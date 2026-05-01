// src/components/OfflineScreen.js
import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Platform } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

export function OfflineScreen({ onRetry }) {
  const { theme } = useTheme();
  const styles = createStyles(theme);

  return (
    <View style={styles.root}>
      <Text style={styles.hex}>⬡</Text>
      <Text style={styles.title}>Sin conexión</Text>
      <Text style={styles.sub}>Dashboard no responde en :8080</Text>
      <View style={styles.cmdBox}>
        <Text style={styles.cmd}>python3 ~/dashboard_server.py &amp;</Text>
      </View>
      <Text style={styles.hint}>Corre el servidor en Termux y reintenta</Text>
      <TouchableOpacity style={styles.retryBtn} onPress={onRetry} activeOpacity={0.75}>
        <Text style={styles.retryText}>↻ Reintentar</Text>
      </TouchableOpacity>
    </View>
  );
}

function createStyles(theme) {
  return StyleSheet.create({
    root: {
      flex: 1,
      backgroundColor: theme.bg,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: 32,
    },
    hex:      { fontSize: 52, color: theme.info, marginBottom: 16 },
    title:    { fontSize: 20, fontWeight: '700', color: theme.textPrimary, marginBottom: 6 },
    sub:      { fontSize: 13, color: theme.textSecond, marginBottom: 14, textAlign: 'center' },
    cmdBox: {
      backgroundColor: theme.surface,
      borderWidth: 1,
      borderColor: theme.border,
      borderRadius: 10,
      paddingVertical: 10,
      paddingHorizontal: 18,
      marginBottom: 12,
    },
    cmd: {
      fontSize: 12,
      color: theme.textCode,
      fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
    },
    hint:     { fontSize: 11, color: theme.textMuted, textAlign: 'center', marginBottom: 22 },
    retryBtn: {
      backgroundColor: theme.accentGlow,
      borderWidth: 1,
      borderColor: theme.accent + '55',
      borderRadius: 10,
      paddingVertical: 12,
      paddingHorizontal: 28,
    },
    retryText: { fontSize: 14, fontWeight: '600', color: theme.accent },
  });
}
