// src/navigation/TabBar.js
import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Platform } from 'react-native';
import { useTheme } from '../theme/ThemeContext';
import { ROUTES, TAB_LABELS } from './routes';

const TABS = [ROUTES.MODULES, ROUTES.CHAT, ROUTES.SYSTEM, ROUTES.SETTINGS];

export function TabBar({ activeTab, onTabPress }) {
  const { theme } = useTheme();
  const styles = createStyles(theme);

  return (
    <View style={styles.container}>
      {TABS.map(tab => {
        const active = activeTab === tab;
        const { label, icon } = TAB_LABELS[tab];
        return (
          <TouchableOpacity
            key={tab}
            style={styles.tab}
            onPress={() => onTabPress(tab)}
            activeOpacity={0.7}
          >
            {active && <View style={styles.indicator} />}
            <Text style={[styles.icon, active && styles.iconActive]}>{icon}</Text>
            <Text style={[styles.label, active && styles.labelActive]}>{label}</Text>
          </TouchableOpacity>
        );
      })}
    </View>
  );
}

function createStyles(theme) {
  return StyleSheet.create({
    container: {
      flexDirection: 'row',
      backgroundColor: theme.surface,
      borderTopWidth: 1,
      borderTopColor: theme.border,
      paddingBottom: Platform.OS === 'android' ? 8 : 20,
      paddingTop: 8,
    },
    tab: {
      flex: 1,
      alignItems: 'center',
      position: 'relative',
      paddingVertical: 2,
      minHeight: 44,
      justifyContent: 'center',
    },
    indicator: {
      position: 'absolute',
      top: 0,
      width: 24,
      height: 2,
      backgroundColor: theme.accent,
      borderRadius: 2,
    },
    icon: {
      fontSize: 18,
      color: theme.textMuted,
      marginBottom: 3,
    },
    iconActive: {
      color: theme.accent,
    },
    label: {
      fontSize: 10,
      color: theme.textMuted,
      fontWeight: '500',
    },
    labelActive: {
      color: theme.accent,
      fontWeight: '700',
    },
  });
}
