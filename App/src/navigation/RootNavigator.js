// src/navigation/RootNavigator.js
// Navegación con estado React puro — cero dependencias nativas nuevas
import React, { useState, useEffect, useRef } from 'react';
import { View, BackHandler, StyleSheet, Animated } from 'react-native';
import { useTheme } from '../theme/ThemeContext';
import { TabBar } from './TabBar';
import { ROUTES } from './routes';

// Screens — importadas lazy para evitar errores en Fase 1 base
// Se descomenta módulo por módulo cuando existan
import { ModulesScreen } from '../screens/modules/ModulesScreen';
import { ChatScreen }    from '../screens/chat/ChatScreen';
import { SystemScreen }  from '../screens/system/SystemScreen';
import { SettingsScreen } from '../screens/settings/SettingsScreen';

// Módulo screens
import { N8nScreen }    from '../screens/modules/n8n/N8nScreen';
import { OllamaScreen } from '../screens/modules/ollama/OllamaScreen';
import { ClaudeScreen } from '../screens/modules/claude/ClaudeScreen';
import { SshScreen }    from '../screens/modules/ssh/SshScreen';

const TAB_SCREENS = {
  [ROUTES.MODULES]:  ModulesScreen,
  [ROUTES.CHAT]:     ChatScreen,
  [ROUTES.SYSTEM]:   SystemScreen,
  [ROUTES.SETTINGS]: SettingsScreen,
};

const MODULE_SCREENS = {
  [ROUTES.N8N]:    N8nScreen,
  [ROUTES.OLLAMA]: OllamaScreen,
  [ROUTES.CLAUDE]: ClaudeScreen,
  [ROUTES.SSH]:    SshScreen,
};

export function RootNavigator() {
  const { theme } = useTheme();
  const [activeTab, setActiveTab] = useState(ROUTES.MODULES);
  // Stack independiente por tab: { modules: [{screen, params}], chat: [], ... }
  const [stacks, setStacks] = useState({
    [ROUTES.MODULES]:  [],
    [ROUTES.CHAT]:     [],
    [ROUTES.SYSTEM]:   [],
    [ROUTES.SETTINGS]: [],
  });

  // Fade al cambiar de tab
  const opacity = useRef(new Animated.Value(1)).current;

  const push = (screen, params = {}) => {
    setStacks(s => ({ ...s, [activeTab]: [...s[activeTab], { screen, params }] }));
  };

  const pop = () => {
    setStacks(s => {
      const current = s[activeTab];
      if (current.length === 0) return s;
      return { ...s, [activeTab]: current.slice(0, -1) };
    });
  };

  const handleTabPress = (tab) => {
    if (tab === activeTab) {
      // Tap en tab activo → vuelve a root del tab
      setStacks(s => ({ ...s, [tab]: [] }));
      return;
    }
    Animated.timing(opacity, {
      toValue: 0, duration: 80, useNativeDriver: true,
    }).start(() => {
      setActiveTab(tab);
      Animated.timing(opacity, {
        toValue: 1, duration: 120, useNativeDriver: true,
      }).start();
    });
  };

  // BackHandler hardware
  useEffect(() => {
    const handler = BackHandler.addEventListener('hardwareBackPress', () => {
      if (stacks[activeTab].length > 0) {
        pop();
        return true; // consumido
      }
      return false; // permite salir de la app
    });
    return () => handler.remove();
  }, [activeTab, stacks]);

  // Determinar qué renderizar
  const stackForTab = stacks[activeTab];
  const topOfStack  = stackForTab[stackForTab.length - 1];

  let ScreenComponent;
  let screenParams = {};

  if (topOfStack && MODULE_SCREENS[topOfStack.screen]) {
    ScreenComponent = MODULE_SCREENS[topOfStack.screen];
    screenParams    = topOfStack.params || {};
  } else {
    ScreenComponent = TAB_SCREENS[activeTab];
  }

  return (
    <View style={[styles.root, { backgroundColor: theme.bg }]}>
      <Animated.View style={[styles.content, { opacity }]}>
        <ScreenComponent
          navigate={push}
          goBack={pop}
          {...screenParams}
        />
      </Animated.View>
      <TabBar activeTab={activeTab} onTabPress={handleTabPress} />
    </View>
  );
}

const styles = StyleSheet.create({
  root:    { flex: 1 },
  content: { flex: 1 },
});
