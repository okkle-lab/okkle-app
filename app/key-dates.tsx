import { View, Text, ScrollView, StyleSheet, Pressable, Alert, Linking } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Card, SectionHeader, ModalHeader } from '../src/components';
import { addDeadlineToCalendar } from '../src/calendar';

// month is 1-12. Real HMRC Self Assessment deadlines.
const KEY_DEADLINES: { title: string; month: number; day: number; note: string }[] = [
  { title: 'Register for Self Assessment', month: 10, day: 5, note: 'Only if this was your first year self-employed.' },
  { title: 'File your return & pay your tax', month: 1, day: 31, note: 'Online Self Assessment deadline for the previous tax year.' },
  { title: 'Second payment on account', month: 7, day: 31, note: 'Only if HMRC asked you for payments on account.' },
];

function nextOccurrence(month: number, day: number): Date {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let d = new Date(now.getFullYear(), month - 1, day);
  if (d < today) d = new Date(now.getFullYear() + 1, month - 1, day);
  return d;
}
function daysUntil(d: Date): number {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.round((d.getTime() - today.getTime()) / 86400000);
}

export default function KeyDatesScreen() {
  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content}>
        <ModalHeader title="Key tax dates" />

        <SectionHeader icon="calendar" title="HMRC deadlines" />
        <Card style={{ padding: 0, overflow: 'hidden' }}>
          {KEY_DEADLINES.map((d, i) => {
            const next = nextOccurrence(d.month, d.day);
            const days = daysUntil(next);
            return (
              <View key={d.title} style={[s.deadlineRow, i < KEY_DEADLINES.length - 1 && s.qBorder]}>
                <View style={{ flex: 1 }}>
                  <Text style={s.deadlineTitle}>{d.title}</Text>
                  <Text style={s.deadlineDate}>
                    {next.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })}
                    {' · '}{days === 0 ? 'today' : days === 1 ? 'tomorrow' : `in ${days} days`}
                  </Text>
                  <Text style={s.deadlineNote}>{d.note}</Text>
                </View>
                <Pressable
                  onPress={async () => {
                    const res = await addDeadlineToCalendar(`HMRC: ${d.title}`, next, d.note);
                    if (res === 'added') {
                      Alert.alert('Added to your calendar', `${d.title} — ${next.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}, with a reminder a week before.`);
                    } else if (res === 'denied') {
                      Alert.alert('Allow calendar access', 'Tap Open Settings, then turn on Calendars to add this deadline.', [{ text: 'Not now', style: 'cancel' }, { text: 'Open Settings', onPress: () => Linking.openSettings() }]);
                    } else {
                      Alert.alert('Couldn’t add it', 'Tap Open Settings, then turn on Calendars and try again.', [{ text: 'Not now', style: 'cancel' }, { text: 'Open Settings', onPress: () => Linking.openSettings() }]);
                    }
                  }}
                  style={s.calBtn}
                  hitSlop={6}
                >
                  <Feather name="calendar" size={15} color={colors.brandDeep} />
                  <Text style={s.calBtnText}>Add</Text>
                </Pressable>
              </View>
            );
          })}
        </Card>
        <Text style={s.note}>Keep your records for at least 5 years after the 31 January deadline. MTD for Income Tax adds quarterly updates once your income passes the threshold.</Text>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.xl },
  back: { padding: 2 },
  title: { ...type.screenTitle },
  deadlineRow: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: spacing.lg },
  deadlineTitle: { ...type.bodyMedium, fontSize: 15 },
  deadlineDate: { ...type.caption, ...tabular, color: colors.brandDeep, fontWeight: font.medium, marginTop: 2 },
  deadlineNote: { ...type.small, lineHeight: 17, marginTop: 3 },
  qBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  calBtn: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 12, paddingVertical: 8, borderRadius: radius.full, backgroundColor: colors.brandLight },
  calBtnText: { ...type.caption, color: colors.brandDeep, fontWeight: font.semibold },
  note: { ...type.small, lineHeight: 18, marginTop: spacing.md },
});
