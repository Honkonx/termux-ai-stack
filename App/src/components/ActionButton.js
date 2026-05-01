// src/components/ActionButton.js
import React from 'react';
import { TouchableOpacity, Text, StyleSheet, ActivityIndicator } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

// variant: 'primary' | 'danger' | 'ghost'
// state:   'idle' | 'loading' | 'success' | 'error'
export function ActionButton({ label, onPress, variant = 'primary', state = 'idle', disabled, style }) {
  const { theme } = useTheme();

  const isLoading = state === 'loading';
  const isDisabled = disabled || isLoading;

  const colors = {
    primary: { bg: theme.accent,    text: '#fff',            border: theme.accent },
    danger:  { bg: theme.errorDim,  text: theme.error,       border: theme.error + '55' },
    ghost:   { bg: 'transparent',   text: theme.textSecond,  border: theme.border },
  }[variant] || {};

  if (state === 'success') { colors.bg = theme.successDim; colors.text = theme.success; }
  if (state === 'error')   { colors.bg = theme.errorDim;   colors.text = theme.error; }

  return (
    <TouchableOpacity
      style={[
        styles.btn,
        { backgroundColor: colors.bg, borderColor: colors.border },
        isDisabled && styles.disabled,
        style,
      ]}
      onPress={onPress}
      disabled={isDisabled}
      activeOpacity={0.75}
    >
      {isLoading
        ? <ActivityIndicator size="small" color={colors.text} />
        : <Text style={[styles.label, { color: colors.text }]}>{label}</Text>
      }
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  btn: {
    minHeight: 44,
    minWidth: 90,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 8,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  label:    { fontSize: 13, fontWeight: '600' },
  disabled: { opacity: 0.45 },
});
