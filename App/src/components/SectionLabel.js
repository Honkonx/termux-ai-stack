// src/components/SectionLabel.js
import React from 'react';
import { Text, StyleSheet } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

export function SectionLabel({ children, style }) {
  const { theme } = useTheme();
  return (
    <Text style={[styles.label, { color: theme.textMuted }, style]}>
      {children}
    </Text>
  );
}

const styles = StyleSheet.create({
  label: {
    fontSize: 10,
    fontWeight: '700',
    letterSpacing: 1.2,
    textTransform: 'uppercase',
    marginBottom: 8,
    marginTop: 4,
  },
});
