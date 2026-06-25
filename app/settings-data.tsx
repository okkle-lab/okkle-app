import React, { useState } from 'react';
import { Platform, View, Text, ScrollView, StyleSheet, Pressable, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, SectionHeader, IconBadge, ModalHeader } from '../src/components';
import { resetAllData } from '../src/db';
import { backupNow, restoreFromFile } from '../src/backup';
import { Feather } from '@expo/vector-icons';

export default function SettingsData() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function doBackup() {
    setBusy(true);
    try { await backupNow(); } catch { Alert.alert('Backup failed', 'Could not create the backup file.'); }
    setBusy(false);
  }

  function doRestore() {
    Alert.alert('Restore from backup?', 'This replaces all current data on this phone with the contents of the backup file.', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Choose file', onPress: async () => {
        setBusy(true);
        try {
          const r = await restoreFromFile();
          if (r) Alert.alert('Restored', `${r.trips} trips and ${r.records} records restored.`, [{ text: 'OK', onPress: () => router.replace('/(tabs)') }]);
        } catch { Alert.alert('Restore failed', "That file isn't a valid Okkle backup."); }
        setBusy(false);
      } },
    ]);
  }

  function confirmReset() {
    Alert.alert('Delete all data?', 'This permanently removes every trip, record and your profile from this phone. This cannot be undone.', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Delete everything', style: 'destructive', onPress: () => { resetAllData(); router.replace('/onboarding'); } },
    ]);
  }

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <ModalHeader title="Data & backup" />

      <SectionHeader title="Backup & restore" />
      <Card style={{ gap: spacing.md }}>
        <Text style={s.aboutText}>Your data lives only on this phone. Back it up to your own iCloud or Files so you don't lose your records — HMRC expects records kept for at least 5 years.</Text>
        <Pressable onPress={doBackup} disabled={busy} style={s.actionRow}>
          <IconBadge icon="upload-cloud" tone="mint" />
          <Text style={s.actionText}>Back up my data</Text>
          <Feather name="chevron-right" size={18} color={colors.textTertiary} />
        </Pressable>
        <View style={s.divider} />
        <Pressable onPress={doRestore} disabled={busy} style={s.actionRow}>
          <IconBadge icon="download-cloud" tone="green" />
          <Text style={s.actionText}>Restore from a backup</Text>
          <Feather name="chevron-right" size={18} color={colors.textTertiary} />
        </Pressable>
      </Card>

      <Pressable onPress={confirmReset} style={s.resetBtn}>
        <Text style={s.resetText}>Delete all my data</Text>
      </Pressable>
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
  actionRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4 },
  actionText: { ...type.bodyMedium, fontSize: 15, flex: 1 },
  divider: { height: 1, backgroundColor: colors.border },
  resetBtn: { marginTop: spacing.xl, alignItems: 'center', paddingVertical: spacing.md },
  resetText: { ...type.label, color: colors.red },
});
