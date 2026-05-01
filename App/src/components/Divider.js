// src/components/Divider.js
import React from 'react';
import { View } from 'react-native';
import { useTheme } from '../theme/ThemeContext';

export function Divider({ style }) {
  const { theme } = useTheme();
  return <View style={[{ height: 1, backgroundColor: theme.border, marginVertical: 12 }, style]} />;
}
