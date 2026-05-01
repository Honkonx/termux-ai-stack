// src/screens/modules/claude/ClaudeScreen.js
import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useTheme } from '../../../theme/ThemeContext';

export function ClaudeScreen({ goBack }) {
  const { theme } = useTheme();
  const styles = createStyles(theme);
  return (
    <View style={styles.root}>
      <TouchableOpacity onPress={goBack} style={styles.back} activeOpacity={0.7}>
        <Text style={styles.backText}>‹ Volver</Text>
      </TouchableOpacity>
      <Text style={styles.title}>Claude Code</Text>
      <Text style={styles.sub}>Pantalla completa — Fase 2</Text>
    </View>
  );
}

function createStyles(theme) {
  return StyleSheet.create({
    root:     { flex: 1, backgroundColor: theme.bg, padding: 16 },
    back:     { marginBottom: 16 },
    backText: { color: theme.accent, fontSize: 15 },
    title:    { fontSize: 20, fontWeight: '700', color: theme.textPrimary, marginBottom: 8 },
    sub:      { color: theme.textMuted, fontSize: 13 },
  });
}
