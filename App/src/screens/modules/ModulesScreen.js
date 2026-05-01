// src/screens/modules/ModulesScreen.js
import React from 'react';
import { View, Text, StyleSheet, ScrollView } from 'react-native';
import { useTheme } from '../../theme/ThemeContext';
import { useStatus } from '../../hooks/useStatus';
import { OfflineScreen } from '../../components/OfflineScreen';

export function ModulesScreen({ navigate }) {
  const { theme } = useTheme();
  const { status, connErr } = useStatus();
  const styles = createStyles(theme);

  if (connErr && !status) return <OfflineScreen onRetry={() => {}} />;

  return (
    <ScrollView style={styles.root} contentContainerStyle={styles.content}>
      <View style={styles.header}>
        <Text style={styles.title}>● TERMUX·AI·STACK</Text>
        <Text style={styles.meta}>
          RAM: {status?.system?.ram_free || '…'}  IP: {status?.system?.ip || '…'}
        </Text>
      </View>
      <Text style={styles.sectionLabel}>MÓDULOS</Text>
      <Text style={styles.placeholder}>
        {/* Cards de módulos — se implementan en Fase 2 */}
        Cargando módulos...
      </Text>
    </ScrollView>
  );
}

function createStyles(theme) {
  return StyleSheet.create({
    root:         { flex: 1, backgroundColor: theme.bg },
    content:      { padding: 16 },
    header:       { backgroundColor: theme.surface, borderWidth: 1, borderColor: theme.border, borderRadius: 10, padding: 12, marginBottom: 16 },
    title:        { fontSize: 13, fontWeight: '700', color: theme.textCode, letterSpacing: 1, fontFamily: 'monospace' },
    meta:         { fontSize: 11, color: theme.textSecond, marginTop: 3 },
    sectionLabel: { fontSize: 10, fontWeight: '700', letterSpacing: 1.2, textTransform: 'uppercase', color: theme.textMuted, marginBottom: 8 },
    placeholder:  { color: theme.textMuted, fontSize: 13, textAlign: 'center', marginTop: 40 },
  });
}
