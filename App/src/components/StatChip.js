// src/components/StatChip.js
import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

export function StatChip({ icon, label }) {
  const { theme } = useTheme();
  return (
    <View style={[styles.chip, { backgroundColor: theme.card, borderColor: theme.border }]}>
      {icon ? <Text style={{ fontSize: 10, marginRight: 3 }}>{icon}</Text> : null}
      <Text style={[styles.text, { color: theme.textSecond }]}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  chip: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
    borderWidth: 1,
    marginRight: 6,
    marginBottom: 4,
  },
  text: { fontSize: 11, fontWeight: '500' },
});
