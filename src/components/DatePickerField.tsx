import React from 'react';
import { View, Text, Pressable, Platform, StyleSheet, Modal } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../theme';

// Pick a date for an entry (defaults to today; can't be in the future).
// Quick "Today/Yesterday" chips cover the common cases; the calendar covers the
// "receipt from last month" case. Works on iOS (compact) and Android (dialog).
export function DatePickerField({
  value,
  onChange,
  quickChips = true,
  variant = 'chips',
}: {
  value: Date;
  onChange: (d: Date) => void;
  quickChips?: boolean;
  variant?: 'chips' | 'ticker';
}) {
  const [showAndroid, setShowAndroid] = React.useState(false);
  const [showIOS, setShowIOS] = React.useState(false);
  const [draftDate, setDraftDate] = React.useState(value);
  const today = startOfDay(new Date());
  const maxDate = noon(new Date());
  const yesterday = addDays(today, -1);
  const isSameDay = (a: Date, b: Date) => startOfDay(a).getTime() === startOfDay(b).getTime();
  const formatted = value.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });

  const set = (d: Date) => onChange(noon(d));
  const openPicker = () => {
    setDraftDate(value);
    if (Platform.OS === 'android') setShowAndroid(true);
    else setShowIOS(true);
  };
  const closeIOS = () => {
    setDraftDate(value);
    setShowIOS(false);
  };
  const applyIOS = () => {
    set(draftDate);
    setShowIOS(false);
  };
  const picker = (
    <>
      {Platform.OS === 'android' && showAndroid && (
        <DateTimePicker
          value={value}
          mode="date"
          maximumDate={maxDate}
          onChange={(event, d) => {
            setShowAndroid(false);
            if (event.type === 'set' && d) set(d);
          }}
        />
      )}
      {Platform.OS === 'ios' && (
        <Modal visible={showIOS} transparent animationType="slide" onRequestClose={closeIOS}>
          <Pressable style={s.modalBackdrop} onPress={closeIOS} />
          <View style={s.modalSheet}>
            <View style={s.modalHandle} />
            <View style={s.modalHeader}>
              <Pressable onPress={closeIOS} hitSlop={12}>
                <Text style={s.modalAction}>Cancel</Text>
              </Pressable>
              <Text style={s.modalTitle}>Choose date</Text>
              <Pressable onPress={applyIOS} hitSlop={12}>
                <Text style={[s.modalAction, s.modalDone]}>Done</Text>
              </Pressable>
            </View>
            <DateTimePicker
              value={draftDate}
              mode="date"
              display="spinner"
              maximumDate={maxDate}
              onChange={(_, d) => d && setDraftDate(noon(d))}
              themeVariant="light"
              accentColor={colors.brand}
              style={s.iosPicker}
            />
          </View>
        </Modal>
      )}
    </>
  );

  if (variant === 'ticker') {
    return (
      <View>
        <Pressable
          onPress={openPicker}
          accessibilityRole="button"
          accessibilityLabel={`Change date, currently ${formatted}`}
          style={({ pressed }) => [s.ticker, pressed && s.tickerPressed]}
        >
          <View style={s.tickerIcon}>
            <Feather name="calendar" size={22} color={colors.brandDeep} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={s.tickerLabel}>Tap to change date</Text>
            <Text style={s.tickerDate}>{formatted}</Text>
          </View>
          <Feather name="chevron-down" size={24} color={colors.textSecondary} />
        </Pressable>
        {picker}
      </View>
    );
  }

  return (
    <View>
      <View style={s.chips}>
        {quickChips && <Quick label="Today" active={isSameDay(value, today)} onPress={() => set(today)} />}
        {quickChips && <Quick label="Yesterday" active={isSameDay(value, yesterday)} onPress={() => set(yesterday)} />}
        <Pressable onPress={openPicker} style={[s.chip, !isSameDay(value, today) && !isSameDay(value, yesterday) && s.chipOn]}>
          <Feather name="calendar" size={14} color={colors.brandDeep} />
          <Text style={s.chipText}>{value.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}</Text>
        </Pressable>
      </View>
      {picker}
    </View>
  );
}

function Quick({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={[s.chip, active && s.chipOn]}>
      <Text style={[s.chipText, active && s.chipTextOn]}>{label}</Text>
    </Pressable>
  );
}

function startOfDay(d: Date) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
function noon(d: Date) { const x = new Date(d); x.setHours(12, 0, 0, 0); return x; } // avoids TZ day-shift
function addDays(d: Date, n: number) { const x = new Date(d); x.setDate(x.getDate() + n); return x; }

const s = StyleSheet.create({
  ticker: {
    minHeight: 112, flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    padding: spacing.lg, borderRadius: radius.xl, borderWidth: 1.5,
    borderColor: colors.brandMid, backgroundColor: colors.bgCard,
  },
  tickerPressed: { opacity: 0.72 },
  tickerIcon: {
    width: 48, height: 48, alignItems: 'center', justifyContent: 'center',
    borderRadius: radius.full, backgroundColor: colors.brandLight,
  },
  tickerLabel: { ...type.caption, color: colors.brandDeep, fontWeight: font.semibold, marginBottom: 3 },
  tickerDate: { fontSize: 25, fontWeight: font.bold, letterSpacing: -0.3, color: colors.textPrimary },
  chips: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, flexWrap: 'wrap' },
  chip: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 14, paddingVertical: 9, borderRadius: radius.full, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bgCard },
  chipOn: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  chipText: { ...type.bodyMedium, fontSize: 14, color: colors.textSecondary },
  chipTextOn: { color: colors.brandDeep },
  modalBackdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.24)' },
  modalSheet: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    paddingTop: spacing.sm, paddingHorizontal: spacing.lg, paddingBottom: spacing.xl,
    borderTopLeftRadius: radius.xl, borderTopRightRadius: radius.xl,
    backgroundColor: colors.bgCard,
  },
  modalHandle: {
    width: 42, height: 5, borderRadius: radius.full,
    backgroundColor: colors.borderStrong, alignSelf: 'center', marginBottom: spacing.md,
  },
  modalHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  modalAction: { ...type.bodyMedium, color: colors.textSecondary },
  modalDone: { color: colors.brandDeep, fontWeight: font.bold },
  modalTitle: { ...type.heading, fontSize: 17 },
  iosPicker: { alignSelf: 'stretch' },
});
