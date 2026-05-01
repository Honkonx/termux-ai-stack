// src/screens/logs/LogsModal.js — v2.0.0
// Modal overlay 60% pantalla — reutilizable por cualquier módulo
import React, { useState, useEffect, useRef } from 'react';
import {
  View, Text, ScrollView, TouchableOpacity,
  StyleSheet, Platform, Modal, Animated,
} from 'react-native';
import { useTheme } from '../../theme/ThemeContext';
import { getN8nLogs } from '../../services/dashboard';

export function LogsModal({ visible, module = 'n8n', onClose }) {
  const { theme }       = useTheme();
  const [logs, setLogs] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError]     = useState('');
  const scrollRef = useRef(null);
  const slideAnim = useRef(new Animated.Value(300)).current;
  const s = createStyles(theme);

  useEffect(() => {
    if (visible) {
      setLogs('');
      setError('');
      fetchLogs();
      Animated.spring(slideAnim, {
        toValue: 0, useNativeDriver: true, tension: 65, friction: 11,
      }).start();
    } else {
      Animated.timing(slideAnim, {
        toValue: 300, duration: 200, useNativeDriver: true,
      }).start();
    }
  }, [visible]);

  const fetchLogs = async () => {
    setLoading(true);
    try {
      const data = await getN8nLogs();
      setLogs(data?.logs || '(sin logs)');
      setError('');
      setTimeout(() => scrollRef.current?.scrollToEnd({ animated: true }), 150);
    } catch (e) {
      setError('✗ No se pudo obtener logs — ¿n8n está activo?');
      setLogs('');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal
      visible={visible}
      transparent
      animationType="none"
      onRequestClose={onClose}
    >
      {/* Fondo semi-transparente */}
      <TouchableOpacity style={s.backdrop} activeOpacity={1} onPress={onClose} />

      {/* Panel deslizante desde abajo */}
      <Animated.View style={[s.panel, { transform: [{ translateY: slideAnim }] }]}>
        {/* Header */}
        <View style={s.header}>
          <View style={s.headerLeft}>
            <Text style={s.icon}>≡</Text>
            <Text style={s.title}>Logs — {module}</Text>
          </View>
          <View style={s.headerRight}>
            <TouchableOpacity style={s.iconBtn} onPress={fetchLogs} activeOpacity={0.7}
              disabled={loading}>
              <Text style={[s.iconBtnText, loading && { opacity: 0.4 }]}>↻</Text>
            </TouchableOpacity>
            <TouchableOpacity style={s.iconBtn} onPress={onClose} activeOpacity={0.7}>
              <Text style={s.iconBtnText}>×</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Divisor */}
        <View style={s.divider} />

        {/* Contenido */}
        <ScrollView
          ref={scrollRef}
          style={s.body}
          contentContainerStyle={s.bodyContent}
          showsVerticalScrollIndicator={false}
        >
          {loading ? (
            <Text style={s.placeholder}>Cargando logs…</Text>
          ) : error ? (
            <Text style={s.errorText}>{error}</Text>
          ) : (
            <Text style={s.logText} selectable>{logs}</Text>
          )}
        </ScrollView>
      </Animated.View>
    </Modal>
  );
}

function createStyles(t) {
  return StyleSheet.create({
    backdrop: {
      flex: 1,
      backgroundColor: 'rgba(0,0,0,0.65)',
    },
    panel: {
      position: 'absolute',
      bottom: 0,
      left: 0,
      right: 0,
      height: '62%',
      backgroundColor: t.surface,
      borderTopLeftRadius: 16,
      borderTopRightRadius: 16,
      borderWidth: 1,
      borderBottomWidth: 0,
      borderColor: t.border,
      overflow: 'hidden',
    },
    header: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingHorizontal: 16,
      paddingTop: 14,
      paddingBottom: 10,
    },
    headerLeft: { flexDirection: 'row', alignItems: 'center', gap: 8 },
    headerRight: { flexDirection: 'row', alignItems: 'center', gap: 4 },
    icon:  { fontSize: 16, color: t.accent },
    title: { fontSize: 14, fontWeight: '700', color: t.textPrimary },
    iconBtn: {
      width: 32, height: 32, borderRadius: 8,
      backgroundColor: t.overlay,
      borderWidth: 1, borderColor: t.border,
      alignItems: 'center', justifyContent: 'center',
    },
    iconBtnText: { fontSize: 18, color: t.textSecond, fontWeight: '600' },
    divider: { height: 1, backgroundColor: t.border },
    body:   { flex: 1 },
    bodyContent: { padding: 14, paddingBottom: 24 },
    logText: {
      fontSize: 11,
      color: t.textCode,
      fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
      lineHeight: 18,
    },
    placeholder: { fontSize: 12, color: t.textMuted, textAlign: 'center', marginTop: 24 },
    errorText:   { fontSize: 12, color: t.error, lineHeight: 18 },
  });
}
