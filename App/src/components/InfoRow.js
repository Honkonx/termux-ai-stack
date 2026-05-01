// src/components/InfoRow.js
import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

export function InfoRow({ label, value, valueColor }) {
  const { theme } = useTheme();
  const styles = createStyles(theme);
  return (
    <View style={styles.row}>
      <Text style={styles.label}>{label}</Text>
      <Text style={[styles.value, valueColor ? { color: valueColor } : null]} numberOfLines={1}>
        {value ?? '—'}
      </Text>
    </View>
  );
}

function createStyles(theme) {
  return StyleSheet.create({
    row: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      paddingVertical: 6,
      borderBottomWidth: 1,
      borderBottomColor: theme.border,
    },
    label: { fontSize: 12, color: theme.textSecond, flex: 1 },
    value: { fontSize: 12, color: theme.textPrimary, fontWeight: '500', flex: 1, textAlign: 'right' },
  });
}
