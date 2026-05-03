// src/navigation/RootNavigator.js — v3.0.0 S19
// FIX CRÍTICO: tabs renderizados simultáneamente con display:none
// Antes: ScreenComponent se recalculaba → ChatScreen se remontaba al cambiar tab
//        → useChatSession perdía su estado y polls activos → crash + mensajes borrados
// Ahora: todos los tabs viven en memoria, solo se ocultan visualmente
//        → ChatScreen mantiene su estado aunque estés en otro tab

import React, { useState, useEffect, useRef } from 'react';
import { View, BackHandler, StyleSheet, Animated } from 'react-native';
import { useTheme } from '../theme/ThemeContext';
import { TabBar } from './TabBar';
import { ROUTES } from './routes';

import { ModulesScreen }  from '../screens/modules/ModulesScreen';
import { ChatScreen }     from '../screens/chat/ChatScreen';
import { SystemScreen }   from '../screens/system/SystemScreen';
import { SettingsScreen } from '../screens/settings/SettingsScreen';

import { N8nScreen }    from '../screens/modules/n8n/N8nScreen';
import { OllamaScreen } from '../screens/modules/ollama/OllamaScreen';
import { ClaudeScreen } from '../screens/modules/claude/ClaudeScreen';
import { SshScreen }    from '../screens/modules/ssh/SshScreen';

const MODULE_SCREENS = {
  [ROUTES.N8N]:    N8nScreen,
  [ROUTES.OLLAMA]: OllamaScreen,
  [ROUTES.CLAUDE]: ClaudeScreen,
  [ROUTES.SSH]:    SshScreen,
};

const TABS = [ROUTES.MODULES, ROUTES.CHAT, ROUTES.SYSTEM, ROUTES.SETTINGS];

export function RootNavigator() {
  const { theme } = useTheme();
  const [activeTab, setActiveTab] = useState(ROUTES.MODULES);
  // Stack independiente por tab para módulos
  const [stacks, setStacks] = useState({
    [ROUTES.MODULES]:  [],
    [ROUTES.CHAT]:     [],
    [ROUTES.SYSTEM]:   [],
    [ROUTES.SETTINGS]: [],
  });
  // tabParams: params pasados al tab root (ej: {model, numCtx} para ChatScreen)
  const [tabParams, setTabParams] = useState({});

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

  // navigateToTab: cambia de tab y opcionalmente pasa params al root del tab
  // Usado por OllamaScreen → ChatScreen con {model, numCtx}
  const navigateToTab = (tab, params = {}) => {
    if (params && Object.keys(params).length > 0) {
      setTabParams(p => ({ ...p, [tab]: params }));
    }
    handleTabPress(tab);
  };

  const handleTabPress = (tab) => {
    if (tab === activeTab) {
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

  useEffect(() => {
    const handler = BackHandler.addEventListener('hardwareBackPress', () => {
      if (stacks[activeTab].length > 0) { pop(); return true; }
      return false;
    });
    return () => handler.remove();
  }, [activeTab, stacks]);

  return (
    <View style={[styles.root, { backgroundColor: theme.bg }]}>
      <Animated.View style={[styles.content, { opacity }]}>

        {/* ── Tabs — siempre montados, solo display cambia ── */}
        {TABS.map(tab => {
          const stackForTab = stacks[tab];
          const topOfStack  = stackForTab[stackForTab.length - 1];
          const isVisible   = tab === activeTab;

          // Si hay una pantalla de módulo en el stack, mostrarla
          let ScreenComponent;
          let screenParams = {};

          if (topOfStack && MODULE_SCREENS[topOfStack.screen]) {
            ScreenComponent = MODULE_SCREENS[topOfStack.screen];
            screenParams    = topOfStack.params || {};
          } else {
            // Tab root — determinar componente
            const TAB_ROOTS = {
              [ROUTES.MODULES]:  ModulesScreen,
              [ROUTES.CHAT]:     ChatScreen,
              [ROUTES.SYSTEM]:   SystemScreen,
              [ROUTES.SETTINGS]: SettingsScreen,
            };
            ScreenComponent = TAB_ROOTS[tab];
            // Mezclar tabParams si los hay (ej: modelo desde OllamaScreen)
            screenParams = tabParams[tab] || {};
          }

          return (
            <View
              key={tab}
              style={[
                styles.tabContainer,
                // display:none preserva el estado del componente en React Native
                // a diferencia de unmount — ChatScreen NO se reinicia
                { display: isVisible ? 'flex' : 'none' },
              ]}
            >
              <ScreenComponent
                navigate={push}
                goBack={pop}
                navigateToTab={navigateToTab}
                {...screenParams}
              />
            </View>
          );
        })}

      </Animated.View>
      <TabBar activeTab={activeTab} onTabPress={handleTabPress} />
    </View>
  );
}

const styles = StyleSheet.create({
  root:         { flex: 1 },
  content:      { flex: 1 },
  tabContainer: { flex: 1 },
});
