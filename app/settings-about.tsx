import React from 'react';
import { Text, View, Pressable, ScrollView, StyleSheet } from 'react-native';
import Constants from 'expo-constants';
import { useFocusEffect } from 'expo-router';
import { colors, font, spacing, type } from '../src/theme';
import { Card, ModalHeader } from '../src/components';
import { getDiagLog, clearDiagLog } from '../src/diagnostics';

export default function SettingsAbout() {
  const version = Constants.expoConfig?.version ?? 'dev';
  const [diagLog, setDiagLog] = React.useState(() => getDiagLog());

  // Whatever generated these entries (e.g. the automatic-tracking background
  // watcher) runs completely out of our control between visits to this
  // screen — so re-read fresh every time it regains focus rather than once.
  useFocusEffect(
    React.useCallback(() => {
      setDiagLog(getDiagLog());
    }, []),
  );

  function clearLog() {
    clearDiagLog();
    setDiagLog([]);
  }

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <ModalHeader title="About Okkle" />

      <Card style={{ gap: spacing.md }}>
        <Text style={s.aboutText}>Okkle keeps a record of your delivery mileage and earnings so you (or your accountant) have what you need at tax time.</Text>
        <Text style={s.aboutText}>Mileage deductions use HMRC's simplified flat rates, which are set per tax year. From 6 April 2026 cars and vans are 55p/mile for the first 10,000 business miles in a tax year (25p after); motorbikes are 24p. Earlier years used 45p for the first 10,000 miles, and Okkle values each trip at the rate that applied on its date. These rates are the same across the whole UK.</Text>
        <Text style={s.aboutText}>The simplified flat-rate scheme formally covers cars, goods vehicles and motorcycles. The cycle (e-bike / bicycle) figure follows the employee mileage rate — if you ride for work as self-employed you may instead need to claim actual costs, so treat the cycle figure as an estimate.</Text>
        <Text style={s.aboutText}>All figures are estimates to help your record-keeping — always check the current HMRC rates and your own circumstances before filing. Your data is stored only on this phone; nothing is sent to a server. Okkle is a record-keeping tool and does not provide tax advice or file your return.</Text>
      </Card>

      <Text style={s.version}>Version {version}</Text>

      <View style={s.diagHeaderRow}>
        <Text style={s.diagTitle}>Diagnostics</Text>
        {diagLog.length > 0 && (
          <Pressable onPress={clearLog} hitSlop={10}>
            <Text style={s.clearLink}>Clear</Text>
          </Pressable>
        )}
      </View>
      <Text style={s.diagSub}>
        On-device activity from background features (e.g. automatic tracking) — useful for checking something's actually working.
      </Text>
      {diagLog.length === 0 ? (
        <Card style={s.diagEmpty}>
          <Text style={s.diagEmptyText}>Nothing logged yet.</Text>
        </Card>
      ) : (
        <Card style={s.diagCard}>
          {diagLog.slice(0, 30).map((e, i) => (
            <View key={i} style={[s.diagRow, i > 0 && s.diagRowBorder]}>
              <Text style={s.diagTime}>{new Date(e.t).toLocaleString('en-GB', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', second: '2-digit' })}</Text>
              <Text style={s.diagDetail}>[{e.ctx}] {e.detail}</Text>
            </View>
          ))}
        </Card>
      )}
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.heading, fontSize: 18 },
  close: { ...type.bodyMedium, color: colors.textSecondary },
  aboutText: { ...type.caption, color: colors.textSecondary, lineHeight: 20 },
  version: { ...type.small, textAlign: 'center', marginTop: spacing.xl },
  diagHeaderRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: spacing.xxl },
  diagTitle: { ...type.bodyMedium, fontSize: 16 },
  clearLink: { ...type.bodyMedium, fontSize: 14, color: colors.brandDeep },
  diagSub: { ...type.caption, lineHeight: 18, marginTop: 2 },
  diagEmpty: { marginTop: spacing.md, alignItems: 'center', paddingVertical: spacing.lg },
  diagEmptyText: { ...type.caption, textAlign: 'center' },
  diagCard: { padding: 0, overflow: 'hidden', marginTop: spacing.md },
  diagRow: { padding: spacing.md, gap: 3 },
  diagRowBorder: { borderTopWidth: 1, borderTopColor: colors.border },
  diagTime: { ...type.caption, fontWeight: font.semibold, color: colors.brandDeep },
  diagDetail: { ...type.caption, lineHeight: 17 },
});
