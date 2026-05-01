// src/components/CodeBox.js
import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Platform } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

export function CodeBox({ value, onCopy, label }) {
  const { theme } = useTheme();
  const styles = createStyles(theme);
  return (
    <View style={styles.box}>
      {label ? <Text style={styles.label}>{label}</Text> : null}
      <View style={styles.row}>
        <Text style={styles.code} selectable numberOfLines={2}>{value || '—'}</Text>
        {onCopy && (
          <TouchableOpacity onPress={() => onCopy(value)} style={styles.copyBtn} activeOpacity={0.7}>
            <Text style={styles.copyIcon}>⧉</Text>
          </TouchableOpacity>
        )}
      </View>
    </View>
  );
}

function createStyles(theme) {
  return StyleSheet.create({
    box: {
      backgroundColor: theme.overlay,
      borderWidth: 1,
      borderColor: theme.border,
      borderRadius: 8,
      padding: 10,
      marginBottom: 8,
    },
    label: {
      fontSize: 10,
      fontWeight: '700',
      letterSpacing: 1,
      textTransform: 'uppercase',
      color: theme.textMuted,
      marginBottom: 4,
    },
    row: { flexDirection: 'row', alignItems: 'center' },
    code: {
      flex: 1,
      fontSize: 11,
      fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
      color: theme.textCode,
      lineHeight: 17,
    },
    copyBtn:  { padding: 4, marginLeft: 8 },
    copyIcon: { fontSize: 16, color: theme.textMuted },
  });
}
