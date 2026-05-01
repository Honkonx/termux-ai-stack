// src/components/StatusPill.js
import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

// status: 'active' | 'ready' | 'inactive'
export function StatusPill({ status, label }) {
  const { theme } = useTheme();

  const config = {
    active:   { dot: '●', color: theme.success,  bg: theme.successDim, text: label || 'activo'   },
    ready:    { dot: '○', color: theme.warning,  bg: theme.warningDim, text: label || 'listo'    },
    inactive: { dot: '○', color: theme.textMuted, bg: theme.card,      text: label || 'no inst.' },
  }[status] || { dot: '○', color: theme.textMuted, bg: theme.card, text: label || 'desconocido' };

  return (
    <View style={[styles.pill, { backgroundColor: config.bg }]}>
      <Text style={[styles.dot, { color: config.color }]}>{config.dot}</Text>
      <Text style={[styles.text, { color: config.color }]}>{config.text}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 999,
    gap: 4,
  },
  dot:  { fontSize: 8 },
  text: { fontSize: 10, fontWeight: '700', letterSpacing: 0.5 },
});
