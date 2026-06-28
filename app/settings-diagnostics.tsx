import { View, Text, ScrollView, StyleSheet, Pressable, Share, Platform, Alert } from 'react-native';
import { useState } from 'react';
import * as Application from 'expo-application';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, SectionHeader, ModalHeader } from '../src/components';
import { getDiagLog, clearDiagLog, type DiagEntry } from '../src/diagnostics';

function summary(): string {
  return [
    `Okkle ${Application.nativeApplicationVersion ?? '?'} (${Application.nativeBuildVersion ?? '?'})`,
    `${Platform.OS} ${Platform.Version}`,
    `Captured ${new Date().toISOString()}`,
  ].join('\n');
}

export default function DiagnosticsScreen() {
  const [log, setLog] = useState<DiagEntry[]>(getDiagLog());

  function refresh() { setLog(getDiagLog()); }

  function shareAll() {
    const body = [
      summary(),
      '',
      log.length ? log.map(e => `• ${e.t} [${e.ctx}]\n${e.detail}`).join('\n\n') : 'No issues recorded.',
    ].join('\n');
    Share.share({ message: body }).catch(() => {});
  }

  function clear() {
    Alert.alert('Clear diagnostics?', 'This removes the recorded issue log from this phone.', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Clear', style: 'destructive', onPress: () => { clearDiagLog(); refresh(); } },
    ]);
  }

  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content}>
        <ModalHeader title="Diagnostics" />

        <Text style={s.intro}>If something goes wrong, tap Share and send this to support — it captures what happened so we can fix it fast. It stays on your phone until you share it.</Text>

        <SectionHeader icon="smartphone" title="This app" />
        <Card style={{ padding: spacing.lg }}>
          <Text style={s.mono} selectable>{summary()}</Text>
        </Card>

        <View style={s.actions}>
          <Pressable onPress={shareAll} style={({ pressed }) => [s.btn, s.btnPrimary, pressed && { opacity: 0.85 }]}>
            <Feather name="share" size={16} color="#fff" />
            <Text style={s.btnPrimaryText}>Share diagnostics</Text>
          </Pressable>
          <Pressable onPress={refresh} style={({ pressed }) => [s.btn, s.btnNeutral, pressed && { opacity: 0.7 }]} hitSlop={6}>
            <Feather name="refresh-cw" size={15} color={colors.textPrimary} />
          </Pressable>
        </View>

        <SectionHeader icon="alert-triangle" title={`Recorded issues (${log.length})`} />
        {log.length === 0 ? (
          <Card style={{ padding: spacing.lg }}>
            <Text style={s.empty}>Nothing recorded. Crashes and failures will show up here automatically.</Text>
          </Card>
        ) : (
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            {log.map((e, i) => (
              <View key={`${e.t}-${i}`} style={[s.entry, i < log.length - 1 && s.entryBorder]}>
                <View style={s.entryHead}>
                  <Text style={s.entryCtx}>{e.ctx}</Text>
                  <Text style={s.entryTime}>{e.t.replace('T', ' ').slice(0, 19)}</Text>
                </View>
                <Text style={s.entryDetail} selectable>{e.detail}</Text>
              </View>
            ))}
          </Card>
        )}

        {log.length > 0 && (
          <Pressable onPress={clear} style={{ marginTop: spacing.lg, alignItems: 'center' }}>
            <Text style={s.clearText}>Clear log</Text>
          </Pressable>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  intro: { ...type.caption, color: colors.textSecondary, lineHeight: 19, marginBottom: spacing.lg },
  mono: { fontFamily: 'Courier', fontSize: 12, lineHeight: 18, color: colors.textPrimary },
  actions: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.lg, marginBottom: spacing.xl },
  btn: { height: 48, borderRadius: radius.lg, alignItems: 'center', justifyContent: 'center', flexDirection: 'row', gap: 8 },
  btnPrimary: { flex: 1, backgroundColor: colors.brandDeep },
  btnPrimaryText: { color: '#fff', fontSize: 15, fontWeight: font.semibold },
  btnNeutral: { width: 48, backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.border },
  entry: { padding: spacing.lg },
  entryBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  entryHead: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 },
  entryCtx: { ...type.caption, color: colors.brandDeep, fontWeight: font.bold },
  entryTime: { ...type.small, color: colors.textTertiary },
  entryDetail: { fontFamily: 'Courier', fontSize: 11, lineHeight: 16, color: colors.textSecondary },
  empty: { ...type.caption, color: colors.textSecondary, lineHeight: 19 },
  clearText: { ...type.caption, color: colors.red },
});
