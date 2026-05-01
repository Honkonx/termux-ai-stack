// App/App.js — v2.0.0
// Entry point mínimo: solo ThemeProvider + RootNavigator
// NO contiene lógica ni componentes — todo está en src/

import React from 'react';
import { StatusBar } from 'expo-status-bar';
import { SafeAreaView, StyleSheet } from 'react-native';
import { ThemeProvider, useTheme } from './src/theme/ThemeContext';
import { RootNavigator } from './src/navigation/RootNavigator';

function AppInner() {
  const { theme } = useTheme();
  return (
    <SafeAreaView style={[styles.root, { backgroundColor: theme.bg }]}>
      <StatusBar style={theme.name === 'dia' ? 'dark' : 'light'} />
      <RootNavigator />
    </SafeAreaView>
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
