import { StatusBar } from 'expo-status-bar';
import { StyleSheet, View, ActivityIndicator, Text } from 'react-native';
import { WebView } from 'react-native-webview';
import { useState } from 'react';

const DASHBOARD_URL = 'http://localhost:8080';

export default function App() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  return (
    <View style={styles.container}>
      <StatusBar style="light" backgroundColor="#0d1117" />

      {error ? (
        <View style={styles.errorBox}>
          <Text style={styles.errorIcon}>⬡</Text>
          <Text style={styles.errorTitle}>Sin conexión</Text>
          <Text style={styles.errorSub}>
            Ejecuta en Termux:{'\n'}
            <Text style={styles.errorCode}>bash ~/dashboard_start.sh</Text>
          </Text>
        </View>
      ) : (
        <WebView
          source={{ uri: DASHBOARD_URL }}
          style={styles.webview}
          onLoadStart={() => setLoading(true)}
          onLoadEnd={() => setLoading(false)}
          onError={() => { setLoading(false); setError(true); }}
          onHttpError={() => { setLoading(false); setError(true); }}
          javaScriptEnabled={true}
          domStorageEnabled={true}
          startInLoadingState={false}
          allowsInlineMediaPlayback={true}
          mixedContentMode="always"
        />
      )}

      {loading && !error && (
        <View style={styles.loadingBox}>
          <ActivityIndicator size="large" color="#79c0ff" />
          <Text style={styles.loadingText}>conectando...</Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0d1117',
  },
  webview: {
    flex: 1,
    backgroundColor: '#0d1117',
  },
  loadingBox: {
    position: 'absolute',
    top: 0, left: 0, right: 0, bottom: 0,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#0d1117',
    gap: 16,
  },
  loadingText: {
    color: '#7d8590',
    fontFamily: 'monospace',
    fontSize: 12,
    letterSpacing: 2,
  },
  errorBox: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 32,
    gap: 12,
  },
  errorIcon: {
    fontSize: 48,
    color: '#79c0ff',
    marginBottom: 8,
  },
  errorTitle: {
    color: '#e6edf3',
    fontSize: 18,
    fontFamily: 'monospace',
    fontWeight: 'bold',
    letterSpacing: 2,
  },
  errorSub: {
    color: '#7d8590',
    fontSize: 13,
    fontFamily: 'monospace',
    textAlign: 'center',
    lineHeight: 22,
    marginTop: 8,
  },
  errorCode: {
    color: '#3fb950',
    fontSize: 12,
  },
});
