// src/components/InputField.js
import React, { useState } from 'react';
import { View, Text, TextInput, StyleSheet } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

export function InputField({ label, value, onChangeText, placeholder, secureTextEntry, multiline, style }) {
  const { theme } = useTheme();
  const [focused, setFocused] = useState(false);
  const styles = createStyles(theme, focused);

  return (
    <View style={[styles.wrapper, style]}>
      {label ? <Text style={styles.label}>{label}</Text> : null}
      <TextInput
        style={styles.input}
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={theme.textMuted}
        secureTextEntry={secureTextEntry}
        multiline={multiline}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        autoCapitalize="none"
        autoCorrect={false}
      />
    </View>
  );
}

function createStyles(theme, focused) {
  return StyleSheet.create({
    wrapper: { marginBottom: 8 },
    label: {
      fontSize: 10,
      fontWeight: '700',
      letterSpacing: 1,
      textTransform: 'uppercase',
      color: theme.textMuted,
      marginBottom: 5,
    },
    input: {
      backgroundColor: theme.overlay,
      borderWidth: 1,
      borderColor: focused ? theme.borderFocus : theme.border,
      borderRadius: 8,
      paddingHorizontal: 12,
      paddingVertical: 10,
      fontSize: 13,
      color: theme.textPrimary,
      minHeight: 44,
    },
  });
}
