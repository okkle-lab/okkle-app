import React from 'react';
import { View, Text, Pressable, Platform, StyleSheet } from 'react-native';
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
  const today = startOfDay(new Date());
  const yesterday = addDays(today, -1);
  const isSameDay = (a: Date, b: Date) => startOfDay(a).getTime() === startOfDay(b).getTime();
  const formatted = value.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });

  const set = (d: Date) => onChange(noon(d));

  if (variant === 'ticker') {
    return (
      <View>
        <View style={s.ticker}>
          <View style={s.tickerIcon}>
            <Feather name="calendar" size={22} color={colors.brandDeep} />
          </View>
          <View style={{ flex: 1 }}>
            <Text style={s.tickerLabel}>Tap to change date</Text>
            <Text style={s.tickerDate}>{formatted}</Text>
          </View>
          <Feather name="chevron-down" size={24} color={colors.textSecondary} />
          {Platform.OS === 'ios' ? (
            <DateTimePicker
              value={value}
              mode="date"
              display="compact"
              maximumDate={today}
              onChange={(_, d) => d && set(d)}
              themeVariant="light"
              accentColor={colors.brand}
              style={s.tickerPicker}
            />
          ) : (
            <Pressable onPress={() => setShowAndroid(true)} style={StyleSheet.absoluteFill} />
          )}
        </View>
        {Platform.OS === 'android' && showAndroid && (
          <DateTimePicker
            value={value}
            mode="date"
            maximumDate={today}
            onChange={(_, d) => { setShowAndroid(false); if (d) set(d); }}
          />
        )}
      </View>
    );
  }

  return (
    <View>
      <View style={s.chips}>
        {quickChips && <Quick label="Today" active={isSameDay(value, today)} onPress={() => set(today)} />}
        {quickChips && <Quick label="Yesterday" active={isSameDay(value, yesterday)} onPress={() => set(yesterday)} />}
        {Platform.OS === 'ios' ? (
          <DateTimePicker
            value={value}
            mode="date"
            display="compact"
            maximumDate={today}
            onChange={(_, d) => d && set(d)}
            themeVariant="light"
            accentColor={colors.brand}
          />
        ) : (
          <Pressable onPress={() => setShowAndroid(true)} style={[s.chip, !isSameDay(value, today) && !isSameDay(value, yesterday) && s.chipOn]}>
            <Feather name="calendar" size={14} color={colors.brandDeep} />
            <Text style={s.chipText}>{value.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}</Text>
          </Pressable>
        )}
      </View>
      {Platform.OS === 'android' && showAndroid && (
        <DateTimePicker
          value={value}
          mode="date"
          maximumDate={today}
          onChange={(_, d) => { setShowAndroid(false); if (d) set(d); }}
        />
      )}
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
  tickerIcon: {
    width: 48, height: 48, alignItems: 'center', justifyContent: 'center',
    borderRadius: radius.full, backgroundColor: colors.brandLight,
  },
  tickerLabel: { ...type.caption, color: colors.brandDeep, fontWeight: font.semibold, marginBottom: 3 },
  tickerDate: { fontSize: 25, fontWeight: font.bold, letterSpacing: -0.3, color: colors.textPrimary },
  tickerPicker: { ...StyleSheet.absoluteFill, opacity: 0.02 },
  chips: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, flexWrap: 'wrap' },
  chip: { flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 14, paddingVertical: 9, borderRadius: radius.full, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bgCard },
  chipOn: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  chipText: { ...type.bodyMedium, fontSize: 14, color: colors.textSecondary },
  chipTextOn: { color: colors.brandDeep },
});
