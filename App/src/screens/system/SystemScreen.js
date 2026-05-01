// src/screens/system/SystemScreen.js
import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTheme } from '../../theme/ThemeContext';

export function SystemScreen() {
  const { theme } = useTheme();
  const styles = createStyles(theme);
  return (
    <View style={styles.root}>
      <Text style={styles.text}>Sistema — Fase 2</Text>
    </View>
  );
}

function createStyles(theme) {
  return StyleSheet.create({
    root: { flex: 1, backgroundColor: theme.bg, alignItems: 'center', justifyContent: 'center' },
    text: { color: theme.textMuted, fontSize: 14 },
  });
}
