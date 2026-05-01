// src/components/ModuleIcon.js
import React from 'react';
import { View, Text } from 'react-native';
import { ModuleIcons } from '../theme/icons';
import { useTheme } from '../theme/ThemeContext';

export function ModuleIcon({ id, size = 44 }) {
  const { theme } = useTheme();
  const cfg = ModuleIcons[id] || { glyph: '?', bg: theme.overlay, color: theme.textMuted };
  return (
    <View style={{
      width: size,
      height: size,
      borderRadius: 12,
      backgroundColor: cfg.bg,
      alignItems: 'center',
      justifyContent: 'center',
      borderWidth: 1,
      borderColor: cfg.color + '33',
    }}>
      <Text style={{ fontSize: size * 0.46, color: cfg.color, fontWeight: '700' }}>
        {cfg.glyph}
      </Text>
    </View>
  );
}
