// App/App.js — v2.1.1
// Fix status bar Android: compensación única en App.js
// Las sub-pantallas con topBar NO compensan por su cuenta — solo aquí

import React from 'react';
import { StatusBar, View, StyleSheet, Platform } from 'react-native';
import { StatusBar as ExpoStatusBar } from 'expo-status-bar';
import { ThemeProvider, useTheme } from './src/theme/ThemeContext';
import { RootNavigator } from './src/navigation/RootNavigator';

// Exportada para que sub-pantallas puedan calcular alturas relativas si necesitan
// PERO no para volver a compensar — esa compensación ya la hace App.js
export const STATUS_BAR_HEIGHT = Platform.OS === 'android'
  ? (StatusBar.currentHeight || 24)
  : 44;

function AppInner() {
  const { theme } = useTheme();

  return (
    <View style={[styles.root, { backgroundColor: theme.bg }]}>
      {/*
        Único relleno de status bar en toda la app.
        Color surface para que los íconos del sistema (hora, wifi, batería)
        se vean sobre un fondo coherente con el tema activo.
      */}
      <View style={{ height: STATUS_BAR_HEIGHT, backgroundColor: theme.surface }} />
      <ExpoStatusBar style={theme.name === 'dia' ? 'dark' : 'light'} translucent={false} />
      <RootNavigator />
    </View>
  );
}

export default function App() {
  return (
    <ThemeProvider>
      <AppInner />
    </ThemeProvider>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
});
