import { useState } from 'react';
import { View, Text, StyleSheet, Switch, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, spacing, type } from '../src/theme';
import { Card, Chip, PrimaryButton, ModalHeader } from '../src/components';
import { getUser, saveUser, kvGet, kvSet } from '../src/db';
import { syncReminders, WEEKDAYS } from '../src/notifications';

const DAY_LABELS: { [k: string]: string } = { sun: 'Sun', mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat' };

export default function SettingsReminders() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const u = getUser();
  const [reminderOn, setReminderOn] = useState((u?.reminder_enabled ?? 1) === 1);
  const [reminderDay, setReminderDay] = useState(u?.reminder_day ?? 'sun');
  const [frequency, setFrequency] = useState(u?.log_frequency ?? 'weekly');
  const [deadlinesOn, setDeadlinesOn] = useState((kvGet('deadline_reminders') ?? 'on') !== 'off');

  async function save() {
    kvSet('deadline_reminders', deadlinesOn ? 'on' : 'off');
    saveUser({ reminder_enabled: reminderOn ? 1 : 0, reminder_day: reminderDay, log_frequency: frequency });
    const updated = getUser();
    if (updated) await syncReminders(updated);
    router.back();
  }

  return (
    <View style={[s.screen, { paddingTop: insets.top + 8 }]}>
      <View style={s.body}>
      <ModalHeader title="Reminders" />

      <Card style={{ gap: spacing.md }}>
        <View style={s.rowBetween}>
          <View style={{ flex: 1 }}>
            <Text style={s.rowTitle}>Logging reminder</Text>
            <Text style={s.rowSub}>A nudge to log your miles and earnings</Text>
          </View>
          <Switch value={reminderOn} onValueChange={setReminderOn} trackColor={{ true: colors.brand, false: colors.borderStrong }} />
        </View>
        {reminderOn && (
          <>
            <View>
              <Text style={s.fieldLabel}>Frequency</Text>
              <View style={s.chips}>
                <Chip label="Weekly" selected={frequency === 'weekly'} onPress={() => setFrequency('weekly')} />
                <Chip label="Monthly" selected={frequency === 'monthly'} onPress={() => setFrequency('monthly')} />
              </View>
            </View>
            <View>
              <Text style={s.fieldLabel}>Reminder day</Text>
              <View style={s.chips}>
                {WEEKDAYS.map(d => <Chip key={d} label={DAY_LABELS[d]} selected={reminderDay === d} onPress={() => setReminderDay(d)} />)}
              </View>
            </View>
          </>
        )}
        <View style={s.divider} />
        <View style={s.rowBetween}>
          <View style={{ flex: 1 }}>
            <Text style={s.rowTitle}>Tax deadline reminders</Text>
            <Text style={s.rowSub}>Self Assessment, payment & MTD dates</Text>
          </View>
          <Switch value={deadlinesOn} onValueChange={setDeadlinesOn} trackColor={{ true: colors.brand, false: colors.borderStrong }} />
        </View>
        <View style={s.divider} />
        <Pressable onPress={() => router.push('/key-dates')} style={({ pressed }) => [s.rowBetween, pressed && { opacity: 0.6 }]}>
          <View style={{ flex: 1 }}>
            <Text style={s.rowTitle}>Key tax dates</Text>
            <Text style={s.rowSub}>View HMRC deadlines & add to calendar</Text>
          </View>
          <Feather name="chevron-right" size={20} color={colors.textTertiary} />
        </Pressable>
      </Card>
      </View>

      <View style={[s.footer, { paddingBottom: Math.max(insets.bottom, 12) }]}>
        <PrimaryButton label="Save changes" onPress={save} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  body: { flex: 1, paddingHorizontal: spacing.xl, gap: spacing.md },
  footer: { paddingHorizontal: spacing.xl, paddingTop: spacing.md },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.heading, fontSize: 18 },
  close: { ...type.bodyMedium, color: colors.textSecondary },
  fieldLabel: { ...type.label, marginBottom: 8 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  rowTitle: { ...type.bodyMedium, fontSize: 15 },
  rowSub: { ...type.caption, marginTop: 2 },
  divider: { height: 1, backgroundColor: colors.border },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: spacing.lg, paddingVertical: spacing.sm },
  linkText: { ...type.bodyMedium, fontSize: 15, color: colors.textPrimary, flex: 1 },
});
