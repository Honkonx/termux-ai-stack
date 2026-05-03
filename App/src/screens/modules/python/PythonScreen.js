// App/src/screens/modules/python/PythonScreen.js
// v1.0.0 — S19
// SURFACE:   tema activo — acento amarillo Python #eab308
// JERARQUÍA: versión grande · secciones UPPERCASE · info en filas · paquetes en chips
// ACENTO:    #eab308 — amarillo Python, color reconocible del lenguaje
// BORDES:    rgba consistente con el resto de la app
// DENSIDAD:  media — pantalla informativa con acciones secundarias

import { useState, useEffect, useCallback } from 'react';
import {
  View, Text, TouchableOpacity, ScrollView,
  StyleSheet, Platform, Clipboard,
} from 'react-native';
import { useTheme }  from '../../../theme/ThemeContext';
import { useStatus } from '../../../hooks/useStatus';

const PY_ACCENT  = '#eab308';
const BASE_URL   = 'http://127.0.0.1:8080';

// Paquetes clave del stack — se muestran con estado instalado/no
const KEY_PACKAGES = [
  { name: 'Pillow',   desc: 'visión' },
  { name: 'sqlite3',  desc: 'builtin' },
  { name: 'urllib',   desc: 'builtin' },
  { name: 'requests', desc: 'HTTP' },
  { name: 'flask',    desc: 'web' },
  { name: 'numpy',    desc: 'cálculo' },
  { name: 'pandas',   desc: 'datos' },
];

// ── SectionLabel ──────────────────────────────────────────────
function SLabel({ text, t }) {
  return (
    <Text style={{
      fontSize: 11, fontWeight: '600', letterSpacing: 1.2,
      textTransform: 'uppercase', color: t.textMuted || '#52525b',
      marginBottom: 8, marginTop: 4,
    }}>
      {text}
    </Text>
  );
}

// ── InfoRow ───────────────────────────────────────────────────
function InfoRow({ label, value, accent, mono, t }) {
  return (
    <View style={{
      flexDirection: 'row', justifyContent: 'space-between',
      alignItems: 'center', paddingVertical: 11, paddingHorizontal: 14,
      borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.05)',
    }}>
      <Text style={{ fontSize: 13, color: t.textMuted || '#71717a' }}>{label}</Text>
      <Text style={{
        fontSize: 13, fontWeight: '600',
        color: accent || t.textPrimary || t.text || '#f4f4f5',
        fontFamily: mono ? (Platform.OS === 'android' ? 'monospace' : 'Courier New') : undefined,
      }}>
        {value}
      </Text>
    </View>
  );
}

// ── PackageChip ───────────────────────────────────────────────
function PackageChip({ name, desc, installed, t }) {
  return (
    <View style={{
      paddingHorizontal: 10, paddingVertical: 7,
      borderRadius: 8, borderWidth: 1,
      backgroundColor: installed ? PY_ACCENT + '12' : 'rgba(255,255,255,0.04)',
      borderColor: installed ? PY_ACCENT + '44' : 'rgba(255,255,255,0.08)',
      alignItems: 'center', minWidth: 80,
    }}>
      <Text style={{
        fontSize: 12, fontWeight: '600',
        color: installed ? PY_ACCENT : (t.textMuted || '#52525b'),
        fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
      }}>
        {name}
      </Text>
      <Text style={{ fontSize: 10, color: t.textMuted || '#52525b', marginTop: 1 }}>
        {installed ? desc : '—'}
      </Text>
    </View>
  );
}

// ── CopyBox ───────────────────────────────────────────────────
function CopyBox({ value, label, t }) {
  const [copied, setCopied] = useState(false);
  const handleCopy = () => {
    Clipboard.setString(value);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  };
  return (
    <View style={{ marginBottom: 8 }}>
      {label && (
        <Text style={{ fontSize: 11, color: t.textMuted || '#52525b',
                       letterSpacing: 0.8, textTransform: 'uppercase', marginBottom: 5 }}>
          {label}
        </Text>
      )}
      <View style={{
        flexDirection: 'row', alignItems: 'center',
        backgroundColor: t.card || '#111', borderRadius: 8,
        borderWidth: 1, borderColor: 'rgba(255,255,255,0.07)', overflow: 'hidden',
      }}>
        <Text style={{
          flex: 1, paddingHorizontal: 12, paddingVertical: 11,
          fontSize: 12, color: PY_ACCENT,
          fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
        }} numberOfLines={1} selectable>
          {value}
        </Text>
        <TouchableOpacity
          style={{ paddingHorizontal: 14, paddingVertical: 11,
                   borderLeftWidth: 1, borderLeftColor: 'rgba(255,255,255,0.07)' }}
          onPress={handleCopy} activeOpacity={0.7}
        >
          <Text style={{ fontSize: 16, color: copied ? PY_ACCENT : (t.textMuted || '#52525b') }}>
            {copied ? '✓' : '⧉'}
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

// ── PythonScreen ──────────────────────────────────────────────
export function PythonScreen({ goBack }) {
  const { theme: t } = useTheme();
  const { status }   = useStatus();

  const [pkgStatus, setPkgStatus] = useState({});
  const [scripts,   setScripts]   = useState([]);
  const [loadingPkgs, setLoadingPkgs] = useState(true);

  const pyModule  = status?.modules?.find(m => m.id === 'python');
  const version   = pyModule?.version || '–';

  // Detectar paquetes instalados via dashboard
  const loadPackages = useCallback(() => {
    setLoadingPkgs(true);
    const ctrl = new AbortController();
    setTimeout(() => ctrl.abort(), 6000);
    fetch(`${BASE_URL}/api/python/info`, { signal: ctrl.signal })
      .then(r => r.json())
      .then(d => {
        setPkgStatus(d.packages || {});
        setScripts(d.scripts   || []);
        setLoadingPkgs(false);
      })
      .catch(() => {
        // Si el endpoint no existe aún, marcar builtins como instalados
        setPkgStatus({ sqlite3: true, urllib: true });
        setLoadingPkgs(false);
      });
  }, []);

  useEffect(() => { loadPackages(); }, []);

  const s = styles(t);

  return (
    <View style={s.root}>
      {/* ── Header ─── */}
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={goBack} activeOpacity={0.7}>
          <Text style={s.backIcon}>‹</Text>
        </TouchableOpacity>
        <View style={s.headerCenter}>
          <Text style={s.headerTitle}>Python</Text>
          <Text style={s.headerSub}>{version}</Text>
        </View>
        {/* Badge instalado — Python no es servicio, no tiene switch */}
        <View style={s.badge}>
          <Text style={s.badgeText}>● listo</Text>
        </View>
      </View>

      <ScrollView style={s.scroll} contentContainerStyle={s.scrollContent}>

        {/* ── Info ─── */}
        <View style={s.card}>
          <SLabel text="Entorno" t={t} />
          <InfoRow label="Versión"  value={version} accent={PY_ACCENT} mono t={t} />
          <InfoRow label="Plataforma" value="ARM64 · Android" t={t} />
          <InfoRow label="Ubicación" value="Termux nativo" t={t} />
          <InfoRow label="Restricciones" value="noexec /tmp → usar ~/" t={t} />
        </View>

        {/* ── Paquetes clave ─── */}
        <View style={s.card}>
          <SLabel text="Paquetes" t={t} />
          <View style={s.chipsGrid}>
            {KEY_PACKAGES.map(pkg => (
              <PackageChip
                key={pkg.name}
                name={pkg.name}
                desc={pkg.desc}
                installed={pkgStatus[pkg.name.toLowerCase()] ?? (pkg.desc === 'builtin')}
                t={t}
              />
            ))}
          </View>
        </View>

        {/* ── Reglas ARM64 ─── */}
        <View style={s.card}>
          <SLabel text="Reglas ARM64 Termux" t={t} />
          <CopyBox label="Instalar paquete" value="pip install PAQUETE --break-system-packages" t={t} />
          <CopyBox label="Ejecutar script"  value="python3 ~/script.py" t={t} />
          <View style={s.rulesBox}>
            <RuleRow icon="✗" text="NUNCA requests → usar urllib.request" color="#ef4444" t={t} />
            <RuleRow icon="✗" text="NUNCA /tmp/ → guardar en $HOME/" color="#ef4444" t={t} />
            <RuleRow icon="✗" text="NUNCA datetime('now') en SQLite → usar datetime.now()" color="#ef4444" t={t} />
            <RuleRow icon="✓" text="Pillow funciona: pip install Pillow --break-system-packages" color={PY_ACCENT} t={t} />
            <RuleRow icon="✓" text="pandas + matplotlib instalan en ARM64 POCO F5" color={PY_ACCENT} t={t} />
          </View>
        </View>

        {/* ── Scripts detectados ─── */}
        {scripts.length > 0 && (
          <View style={s.card}>
            <SLabel text={`Scripts en ~/python/ (${scripts.length})`} t={t} />
            {scripts.map((sc, i) => (
              <View key={sc} style={{
                paddingVertical: 10, paddingHorizontal: 14,
                borderBottomWidth: i < scripts.length - 1 ? 1 : 0,
                borderBottomColor: 'rgba(255,255,255,0.05)',
              }}>
                <Text style={{
                  fontSize: 13, color: t.textPrimary || t.text || '#f4f4f5',
                  fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
                }}>
                  {sc}
                </Text>
              </View>
            ))}
          </View>
        )}

        {/* ── Proyectos del stack ─── */}
        <View style={s.card}>
          <SLabel text="Scripts del stack" t={t} />
          {[
            { name: 'dashboard_server.py', desc: 'API HTTP :8080' },
            { name: 'vision_bot.py',       desc: 'Bot visión Telegram' },
            { name: 'bot_utils.py',        desc: 'Utilidades compartidas' },
            { name: 'image_archive.py',    desc: 'Archivo imágenes SQLite' },
          ].map((item, i, arr) => (
            <View key={item.name} style={{
              flexDirection: 'row', justifyContent: 'space-between',
              paddingVertical: 10, paddingHorizontal: 14,
              borderBottomWidth: i < arr.length - 1 ? 1 : 0,
              borderBottomColor: 'rgba(255,255,255,0.05)',
            }}>
              <Text style={{
                fontSize: 12, color: PY_ACCENT,
                fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New',
              }}>
                {item.name}
              </Text>
              <Text style={{ fontSize: 12, color: t.textMuted || '#52525b' }}>
                {item.desc}
              </Text>
            </View>
          ))}
        </View>

      </ScrollView>
    </View>
  );
}

function RuleRow({ icon, text, color, t }) {
  return (
    <View style={{ flexDirection: 'row', gap: 8, marginBottom: 6 }}>
      <Text style={{ fontSize: 13, color, fontWeight: '700', width: 14 }}>{icon}</Text>
      <Text style={{ flex: 1, fontSize: 12, color: t.textSecond || '#a1a1aa', lineHeight: 18 }}>
        {text}
      </Text>
    </View>
  );
}

function styles(t) {
  return StyleSheet.create({
    root:   { flex: 1, backgroundColor: t.bg || '#0a0a0a' },
    header: {
      flexDirection: 'row', alignItems: 'center',
      paddingHorizontal: 12, paddingVertical: 12,
      backgroundColor: t.surface || '#111',
      borderBottomWidth: 1, borderBottomColor: 'rgba(255,255,255,0.06)',
    },
    backBtn:      { width: 36, height: 36, alignItems: 'center', justifyContent: 'center' },
    backIcon:     { fontSize: 26, color: t.textPrimary || t.text || '#f4f4f5', lineHeight: 30 },
    headerCenter: { flex: 1, marginLeft: 4 },
    headerTitle:  { fontSize: 17, fontWeight: '700', letterSpacing: 0.2,
                    color: t.textPrimary || t.text || '#f4f4f5' },
    headerSub:    { fontSize: 11, color: t.textMuted || '#52525b', marginTop: 1,
                    fontFamily: Platform.OS === 'android' ? 'monospace' : 'Courier New' },
    badge: {
      paddingHorizontal: 10, paddingVertical: 4, borderRadius: 999,
      backgroundColor: PY_ACCENT + '18', borderWidth: 1, borderColor: PY_ACCENT + '44',
    },
    badgeText:   { fontSize: 12, fontWeight: '600', color: PY_ACCENT },
    scroll:        { flex: 1 },
    scrollContent: { padding: 16, gap: 12 },
    card: {
      backgroundColor: t.surface || '#111',
      borderRadius: 12, borderWidth: 1,
      borderColor: 'rgba(255,255,255,0.07)',
      padding: 14, marginBottom: 4,
    },
    chipsGrid: {
      flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 2,
    },
    rulesBox: { marginTop: 12 },
  });
}
