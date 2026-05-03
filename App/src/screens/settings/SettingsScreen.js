// src/screens/settings/SettingsScreen.js
import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ScrollView } from 'react-native';
import { useTheme } from '../../theme/ThemeContext';

const THEME_OPTIONS = [
  { key: 'noche',  label: 'Noche',  desc: 'Negro puro · alta densidad',  dot: '#3d7aed' },
  { key: 'oceano', label: 'Océano', desc: 'Azul marino · GitHub Dark',   dot: '#58a6ff' },
  { key: 'dia',    label: 'Día',    desc: 'Blanco limpio · uso diurno',  dot: '#2563eb' },
];

export function SettingsScreen() {
  const { theme, themeName, setThemeName } = useTheme();
  const styles = createStyles(theme);

  return (
    <ScrollView style={styles.root} contentContainerStyle={styles.content}>
      <Text style={styles.sectionLabel}>TEMA</Text>
      {THEME_OPTIONS.map(opt => {
        const active = themeName === opt.key;
        return (
          <TouchableOpacity
            key={opt.key}
            style={[styles.option, active && { borderColor: theme.accent, backgroundColor: theme.accentGlow }]}
            onPress={() => setThemeName(opt.key)}
            activeOpacity={0.75}
          >
            <View style={[styles.preview, { backgroundColor: opt.dot }]} />
            <View style={styles.optText}>
              <Text style={[styles.optLabel, { color: active ? theme.accent : theme.textPrimary }]}>
                {opt.label}
              </Text>
              <Text style={[styles.optDesc, { color: theme.textMuted }]}>{opt.desc}</Text>
            </View>
            {active && <Text style={[styles.check, { color: theme.accent }]}>✓</Text>}
          </TouchableOpacity>
        );
      })}

      <Text style={[styles.sectionLabel, { marginTop: 24 }]}>VERSIONES</Text>
      <View style={styles.card}>
        <Text style={styles.ver}>App v2.0.0 · Expo SDK 50 · RN 0.73.6</Text>
        <Text style={styles.ver}>Claude Code @2.1.111 (ARM64 Bionic)</Text>
      </View>
    </ScrollView>
  );
}

function createStyles(theme) {
  return StyleSheet.create({
    root:         { flex: 1, backgroundColor: theme.bg },
    content:      { padding: 16 },
    sectionLabel: { fontSize: 10, fontWeight: '700', letterSpacing: 1.2, textTransform: 'uppercase', color: theme.textMuted, marginBottom: 10 },
    option:       { flexDirection: 'row', alignItems: 'center', backgroundColor: theme.card, borderWidth: 1, borderColor: theme.border, borderRadius: 10, padding: 14, marginBottom: 8 },
    preview:      { width: 24, height: 24, borderRadius: 999, marginRight: 12 },
    optText:      { flex: 1 },
    optLabel:     { fontSize: 14, fontWeight: '600' },
    optDesc:      { fontSize: 11, marginTop: 2 },
    check:        { fontSize: 16, fontWeight: '700' },
    card:         { backgroundColor: theme.card, borderWidth: 1, borderColor: theme.border, borderRadius: 10, padding: 14, gap: 4 },
    ver:          { fontSize: 11, color: theme.textSecond, fontFamily: 'monospace' },
  });
}
