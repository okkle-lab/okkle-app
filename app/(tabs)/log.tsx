import React, { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, StyleSheet, Pressable, Alert, Image, Animated, Dimensions,
} from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import * as FileSystem from 'expo-file-system';
import * as Haptics from 'expo-haptics';
import { colors, font, spacing, radius, type, tabular } from '../../src/theme';
import { Feather } from '@expo/vector-icons';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Chip, Card, SectionHeader, VehicleChip, DatePickerField, CollapsingHeader, Icon, IconBadge, GradientCard } from '../../src/components';
import { PLATFORMS, calcDeduction, fmtGbp, VEHICLES } from '../../src/db/tax';
import { saveRecord, getUser, kvGet, kvSet } from '../../src/db';

// Copy a picked image into app storage so it survives even if the cache clears.
async function persistImage(uri: string): Promise<string> {
  try {
    const dir = (FileSystem as any).documentDirectory + 'receipts/';
    await FileSystem.makeDirectoryAsync(dir, { intermediates: true }).catch(() => {});
    const dest = `${dir}${Date.now()}.jpg`;
    await FileSystem.copyAsync({ from: uri, to: dest });
    return dest;
  } catch {
    return uri;
  }
}

// Category list with icons (benchmark accounting apps show an icon per category
// for fast scanning). Default order roughly follows how often couriers claim
// each one; this is then personalised by the user's own usage.
type Cat = { name: string; icon: React.ComponentProps<typeof Feather>['name'] };
const EXPENSE_CATEGORIES: Cat[] = [
  { name: 'Fuel', icon: 'droplet' },
  { name: 'Charging', icon: 'battery-charging' },
  { name: 'Parking', icon: 'map-pin' },
  { name: 'Phone / data', icon: 'smartphone' },
  { name: 'Insurance', icon: 'shield' },
  { name: 'Maintenance / repairs', icon: 'tool' },
  { name: 'Tyres', icon: 'disc' },
  { name: 'Congestion charge', icon: 'alert-circle' },
  { name: 'ULEZ charge', icon: 'wind' },
  { name: 'Insulated bag', icon: 'shopping-bag' },
  { name: 'Waterproof gear', icon: 'umbrella' },
  { name: 'Helmet / safety', icon: 'shield' },
  { name: 'Phone mount', icon: 'crosshair' },
  { name: 'App subscription', icon: 'repeat' },
];

function getCatCounts(): Record<string, number> {
  try { return JSON.parse(kvGet('expense_cat_counts') || '{}'); } catch { return {}; }
}
function bumpCat(name: string) {
  const c = getCatCounts(); c[name] = (c[name] || 0) + 1; kvSet('expense_cat_counts', JSON.stringify(c));
}

type Tab = 'mileage' | 'income' | 'expense';
const TABS: { key: Tab; label: string; icon: React.ComponentProps<typeof Feather>['name']; tone: 'amber' | 'green' | 'mint'; title: string; sub: string }[] = [
  { key: 'expense', label: 'Expense', icon: 'file-text', tone: 'amber', title: 'Add an expense', sub: 'A cost you can claim against tax' },
  { key: 'income', label: 'Earnings', icon: 'dollar-sign', tone: 'green', title: 'Log earnings', sub: 'A day or a week of pay — set the date below' },
  { key: 'mileage', label: 'Mileage', icon: 'map', tone: 'mint', title: 'Add mileage', sub: 'Miles you drove without GPS tracking' },
];

export default function LogScreen() {
  const router = useRouter();
  const user = getUser();
  const win = Dimensions.get('window');
  // Other screens can deep-link a tab (?tab=income).
  const params = useLocalSearchParams<{ tab?: string }>();
  const [tab, setTab] = useState<Tab>((params.tab === 'income' || params.tab === 'mileage') ? params.tab : 'expense');
  React.useEffect(() => {
    if (params.tab === 'income' || params.tab === 'mileage' || params.tab === 'expense') setTab(params.tab);
  }, [params.tab]);

  const [miles, setMiles] = useState('');
  const [vehicle, setVehicle] = useState(user?.vehicle ?? 'car');
  const [platform, setPlatform] = useState(user?.platforms?.split(',')[0] ?? 'Uber Eats');
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [receiptUri, setReceiptUri] = useState<string | null>(null);
  const [date, setDate] = useState(() => { const d = new Date(); d.setHours(12, 0, 0, 0); return d; });
  const [period, setPeriod] = useState<'day' | 'week'>('day');
  const [saved, setSaved] = useState(false);
  const [catCounts, setCatCounts] = useState(getCatCounts);

  // The Mon–Sun week the chosen date falls in (pay weeks run Monday–Sunday).
  const weekBounds = (d: Date) => {
    const day = d.getDay(); const mondayOffset = day === 0 ? 6 : day - 1;
    const start = new Date(d); start.setDate(d.getDate() - mondayOffset); start.setHours(12, 0, 0, 0);
    const end = new Date(start); end.setDate(start.getDate() + 6); end.setHours(12, 0, 0, 0);
    return { start, end };
  };
  const wb = weekBounds(date);
  const fmtShort = (d: Date) => d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });

  // Most-used categories first, then the default priority order (benchmark apps
  // surface what you reach for most so you're not hunting every time).
  const sortedCats = React.useMemo(
    () => EXPENSE_CATEGORIES.map((c, i) => ({ c, i })).sort((a, b) => (catCounts[b.c.name] || 0) - (catCounts[a.c.name] || 0) || a.i - b.i).map(x => x.c),
    [catCounts],
  );

  // Quick date presets so logging a single day's takings is one tap.
  const dayAt = (offset: number) => { const d = new Date(); d.setDate(d.getDate() + offset); d.setHours(12, 0, 0, 0); return d; };
  const isSameDay = (a: Date, b: Date) => a.toDateString() === b.toDateString();

  // Animated tab pill + content cross-fade for a smooth, premium transition.
  const tabIndex = TABS.findIndex(t => t.key === tab);
  const SEG_PAD = 4;
  const itemW = (win.width - spacing.xl * 2 - SEG_PAD * 2) / TABS.length;
  const pillX = React.useRef(new Animated.Value(0)).current;
  const contentAnim = React.useRef(new Animated.Value(1)).current;
  React.useEffect(() => {
    Animated.spring(pillX, { toValue: SEG_PAD + tabIndex * itemW, useNativeDriver: true, speed: 18, bounciness: 6 }).start();
    contentAnim.setValue(0);
    Animated.timing(contentAnim, { toValue: 1, duration: 240, useNativeDriver: true }).start();
  }, [tab]);
  const active = TABS[tabIndex];

  async function pickReceipt(useCamera: boolean) {
    const perm = useCamera
      ? await ImagePicker.requestCameraPermissionsAsync()
      : await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!perm.granted) { Alert.alert('Permission needed', 'Allow access to add a receipt photo.'); return; }
    const res = useCamera
      ? await ImagePicker.launchCameraAsync({ quality: 0.6 })
      : await ImagePicker.launchImageLibraryAsync({ quality: 0.6, mediaTypes: ['images'] });
    if (!res.canceled && res.assets[0]) {
      const saved = await persistImage(res.assets[0].uri);
      setReceiptUri(saved);
    }
  }

  const deduction = miles ? calcDeduction(parseFloat(miles) || 0, vehicle) : 0;

  function handleSave() {
    const createdAt = date.toISOString();
    // A weekly entry stores the Mon–Sun range so reports spread it across the days.
    const ps = period === 'week' ? wb.start.toISOString() : null;
    const pe = period === 'week' ? wb.end.toISOString() : null;
    if (tab === 'mileage') {
      if (!miles) { Alert.alert('Enter miles'); return; }
      saveRecord({ record_type: 'mileage', platform, miles: parseFloat(miles), deduction, amount: null, category: null, period_start: ps, period_end: pe, receipt_uri: null, notes: null }, createdAt);
    } else if (tab === 'income') {
      if (!amount) { Alert.alert('Enter amount'); return; }
      saveRecord({ record_type: 'income', platform, amount: parseFloat(amount), miles: null, deduction: null, category: null, period_start: ps, period_end: pe, receipt_uri: null, notes: null }, createdAt);
    } else {
      if (!amount || !description) { Alert.alert('Enter amount and description'); return; }
      saveRecord({ record_type: 'expense', platform: null, amount: parseFloat(amount), miles: null, deduction: null, category: description, period_start: ps, period_end: pe, receipt_uri: receiptUri, notes: description }, createdAt);
      bumpCat(description); setCatCounts(getCatCounts());
    }
    setMiles(''); setAmount(''); setDescription(''); setReceiptUri(null);
    const t = new Date(); t.setHours(12, 0, 0, 0); setDate(t);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  }

  const canSave = tab === 'mileage' ? !!miles : tab === 'income' ? !!amount : (!!amount && !!description);

  return (
    <CollapsingHeader
      title="Log entry"
      keyboardShouldPersistTaps="handled"
      right={
        <Pressable onPress={() => router.push('/settings')} hitSlop={10}>
          <Icon name="settings" size={22} color={colors.textSecondary} />
        </Pressable>
      }
    >
      {/* Animated segmented type switcher */}
      <View style={s.tabs}>
        <Animated.View style={[s.tabPill, { width: itemW, transform: [{ translateX: pillX }] }]} />
        {TABS.map(t => {
          const on = tab === t.key;
          return (
            <Pressable key={t.key} onPress={() => setTab(t.key)} style={s.tab}>
              <Feather name={t.icon} size={16} color={on ? colors.textPrimary : colors.textSecondary} />
              <Text style={[s.tabText, on && s.tabTextActive]}>{t.label}</Text>
            </Pressable>
          );
        })}
      </View>

      <Animated.View style={{ opacity: contentAnim, transform: [{ translateX: contentAnim.interpolate({ inputRange: [0, 1], outputRange: [16, 0] }) }] }}>
        {/* Friendly type header */}
        <View style={s.typeHead}>
          <IconBadge icon={active.icon} tone={active.tone} size={40} />
          <View style={{ flex: 1 }}>
            <Text style={s.typeTitle}>{active.title}</Text>
            <Text style={s.typeSub}>{active.sub}</Text>
          </View>
        </View>

        {/* The headline input — amount (or miles), big and front-and-centre */}
        {tab === 'mileage' ? (
          <GradientCard colors={[colors.brand, colors.brandDeep]} radius={radius.lg} style={s.amountHero}>
            <Text style={s.amountHeroLabel}>Miles driven</Text>
            <View style={s.amountHeroRow}>
              <TextInput
                style={s.amountHeroInput}
                placeholder="0"
                placeholderTextColor="rgba(255,255,255,0.5)"
                keyboardType="decimal-pad"
                value={miles}
                onChangeText={setMiles}
              />
              <Text style={s.amountHeroUnit}>mi</Text>
            </View>
            <Text style={s.amountHeroSub}>
              {miles ? `${fmtGbp(deduction)} tax deduction at the HMRC rate` : 'GPS tracking records miles more accurately — try the Trip tab'}
            </Text>
          </GradientCard>
        ) : (
          <GradientCard colors={tab === 'income' ? ['#3BC07E', colors.green, '#1C7048'] : [colors.amber, '#B5740F']} radius={radius.lg} style={s.amountHero}>
            <Text style={s.amountHeroLabel}>{tab === 'income' ? 'Amount received' : 'Amount spent'}</Text>
            <View style={s.amountHeroRow}>
              <Text style={s.amountHeroPrefix}>£</Text>
              <TextInput
                style={s.amountHeroInput}
                placeholder="0.00"
                placeholderTextColor="rgba(255,255,255,0.5)"
                keyboardType="decimal-pad"
                value={amount}
                onChangeText={setAmount}
              />
            </View>
            <Text style={s.amountHeroSub}>
              {tab === 'income' ? 'Gross pay before platform deductions' : description || 'Pick a category below'}
            </Text>
          </GradientCard>
        )}

        {/* Type-specific details */}
        <Card style={{ gap: spacing.lg, marginTop: spacing.md }}>
          {tab === 'expense' && (
            <>
              <View>
                <SectionHeader title="Category" />
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.chipRow}>
                  {sortedCats.map(cat => {
                    const on = description === cat.name;
                    return (
                      <Pressable key={cat.name} onPress={() => setDescription(cat.name)} style={[s.catChip, on && s.catChipActive]}>
                        <Feather name={cat.icon} size={14} color={on ? colors.brandDeep : colors.textSecondary} />
                        <Text style={[s.catChipText, on && s.catChipTextActive]}>{cat.name}</Text>
                      </Pressable>
                    );
                  })}
                </ScrollView>
                <TextInput
                  style={[s.input, { marginTop: spacing.sm }]}
                  placeholder="Or type your own description"
                  placeholderTextColor={colors.textTertiary}
                  value={description}
                  onChangeText={setDescription}
                />
              </View>
              <View>
                <SectionHeader title="Receipt (optional)" />
                {receiptUri ? (
                  <View style={s.receiptWrap}>
                    <Image source={{ uri: receiptUri }} style={s.receiptImg} />
                    <Pressable onPress={() => setReceiptUri(null)} style={s.receiptRemove}>
                      <Text style={s.receiptRemoveText}>Remove</Text>
                    </Pressable>
                  </View>
                ) : (
                  <View style={s.receiptButtons}>
                    <Pressable onPress={() => pickReceipt(true)} style={s.receiptBtn}>
                      <Feather name="camera" size={16} color={colors.textPrimary} />
                      <Text style={s.receiptBtnText}>Take photo</Text>
                    </Pressable>
                    <Pressable onPress={() => pickReceipt(false)} style={s.receiptBtn}>
                      <Feather name="image" size={16} color={colors.textPrimary} />
                      <Text style={s.receiptBtnText}>Choose</Text>
                    </Pressable>
                  </View>
                )}
              </View>
              <View style={s.notice}>
                <Text style={s.noticeText}>
                  Vehicle running costs (fuel, tyres, repairs) are flagged for accountant review when you use simplified mileage.
                </Text>
              </View>
            </>
          )}

          {tab === 'income' && (
            <View>
              <SectionHeader title="Platform" />
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.chipRow}>
                {PLATFORMS.map(p => (
                  <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} size="lg" />
                ))}
              </ScrollView>
            </View>
          )}

          {tab === 'mileage' && (
            <>
              <View>
                <SectionHeader title="Vehicle" />
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.chipRow}>
                  {VEHICLES.map(v => (
                    <VehicleChip key={v.key} vehicle={v.key} label={v.label} selected={vehicle === v.key} onPress={() => setVehicle(v.key)} />
                  ))}
                </ScrollView>
              </View>
              <View>
                <SectionHeader title="Platform" />
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.chipRow}>
                  {PLATFORMS.map(p => (
                    <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} size="lg" />
                  ))}
                </ScrollView>
              </View>
            </>
          )}

          {/* When — a single day or a whole pay-week */}
          <View style={s.dateBlock}>
            <View style={s.dateHeadRow}>
              <IconBadge icon="calendar" tone="neutral" size={32} />
              <Text style={s.dateLabel}>{period === 'week' ? 'Pay week' : 'Date'}</Text>
              <View style={s.periodSeg}>
                {(['day', 'week'] as const).map(p => (
                  <Pressable key={p} onPress={() => setPeriod(p)} style={[s.periodItem, period === p && s.periodItemOn]}>
                    <Text style={[s.periodText, period === p && s.periodTextOn]}>{p === 'day' ? 'Day' : 'Week'}</Text>
                  </Pressable>
                ))}
              </View>
            </View>

            {/* Week mode: This week / Last week presets + the covered range.
                Day mode uses the picker's own Today/Yesterday chips (no dupes). */}
            {period === 'week' && (
              <>
                <View style={s.quickDates}>
                  {([['This week', 0], ['Last week', -7]] as [string, number][]).map(([label, off]) => {
                    const on = isSameDay(weekBounds(date).start, weekBounds(dayAt(off)).start);
                    return (
                      <Pressable key={label} onPress={() => setDate(dayAt(off))} style={[s.quickChip, on && s.quickChipOn]}>
                        <Text style={[s.quickChipText, on && s.quickChipTextOn]}>{label}</Text>
                      </Pressable>
                    );
                  })}
                </View>
                <Text style={s.weekCaption}>Covers {fmtShort(wb.start)} – {fmtShort(wb.end)} · spread evenly across the 7 days</Text>
              </>
            )}
            <DatePickerField value={date} onChange={setDate} quickChips={period === 'day'} />
          </View>
        </Card>

        {/* Gradient save action */}
        <Pressable onPress={handleSave} disabled={!canSave && !saved} style={({ pressed }) => [pressed && { opacity: 0.9 }, { marginTop: spacing.lg }]}>
          <GradientCard
            colors={saved ? ['#3BC07E', colors.green, '#1C7048'] : canSave ? [colors.brand, colors.brandDeep] : [colors.borderStrong, colors.borderStrong]}
            radius={radius.lg}
            style={s.saveBtn}
          >
            <Feather name={saved ? 'check' : 'plus'} size={20} color="#fff" />
            <Text style={s.saveText}>{saved ? 'Saved!' : 'Save entry'}</Text>
          </GradientCard>
        </Pressable>
      </Animated.View>
    </CollapsingHeader>
  );
}

const s = StyleSheet.create({
  tabs: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.lg, padding: 4, marginBottom: spacing.lg },
  tabPill: { position: 'absolute', top: 4, bottom: 4, left: 0, backgroundColor: colors.bgCard, borderRadius: radius.md, shadowColor: '#000', shadowOpacity: 0.08, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  tab: { flex: 1, paddingVertical: 10, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, borderRadius: radius.md },
  tabText: { fontSize: 14, fontWeight: font.medium, color: colors.textSecondary },
  tabTextActive: { color: colors.textPrimary, fontWeight: font.semibold },

  typeHead: { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: spacing.md },
  typeTitle: { ...type.heading, fontSize: 19 },
  typeSub: { ...type.caption, marginTop: 1 },

  amountHero: { padding: spacing.lg },
  amountHeroLabel: { color: 'rgba(255,255,255,0.85)', fontSize: 13, fontWeight: font.medium },
  amountHeroRow: { flexDirection: 'row', alignItems: 'center', marginTop: 4 },
  amountHeroPrefix: { ...tabular, color: '#fff', fontSize: 34, fontWeight: font.bold, marginRight: 4 },
  amountHeroInput: { ...tabular, flex: 1, color: '#fff', fontSize: 40, fontWeight: font.bold, letterSpacing: -1, paddingVertical: 4 },
  amountHeroUnit: { color: 'rgba(255,255,255,0.85)', fontSize: 22, fontWeight: font.semibold, marginLeft: 6 },
  amountHeroSub: { color: 'rgba(255,255,255,0.85)', fontSize: 13, marginTop: 2 },

  input: {
    borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg,
  },
  chipRow: { flexDirection: 'row', gap: spacing.sm, paddingRight: spacing.lg },

  dateBlock: { borderTopWidth: 1, borderTopColor: colors.border, paddingTop: spacing.lg, gap: spacing.md },
  dateHeadRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  dateLabel: { ...type.bodyMedium, fontSize: 15, flex: 1 },
  periodSeg: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.md, padding: 3 },
  periodItem: { paddingHorizontal: 14, paddingVertical: 6, borderRadius: radius.sm },
  periodItemOn: { backgroundColor: colors.bgCard, shadowColor: '#000', shadowOpacity: 0.06, shadowRadius: 3, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  periodText: { fontSize: 13, fontWeight: font.medium, color: colors.textSecondary },
  periodTextOn: { color: colors.textPrimary, fontWeight: font.semibold },
  weekCaption: { ...type.caption, color: colors.brandDeep, fontWeight: font.medium },
  quickDates: { flexDirection: 'row', gap: 6 },
  quickChip: { paddingHorizontal: 12, paddingVertical: 7, borderRadius: radius.full, backgroundColor: colors.bgSoft },
  quickChipOn: { backgroundColor: colors.brandDeep },
  quickChipText: { fontSize: 12.5, fontWeight: font.semibold, color: colors.textSecondary },
  quickChipTextOn: { color: '#fff' },

  notice: { backgroundColor: colors.amberLight, borderRadius: radius.md, padding: spacing.md },
  noticeText: { fontSize: 13, color: colors.amberDark, lineHeight: 19 },
  receiptButtons: { flexDirection: 'row', gap: spacing.sm },
  receiptBtn: {
    flex: 1, borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    paddingVertical: 14, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, backgroundColor: colors.bg,
  },
  receiptBtnText: { ...type.bodyMedium, fontSize: 14 },
  receiptWrap: { position: 'relative' },
  receiptImg: { width: '100%', height: 180, borderRadius: radius.md, backgroundColor: colors.bgSoft },
  receiptRemove: {
    position: 'absolute', top: 8, right: 8, backgroundColor: 'rgba(0,0,0,0.6)',
    paddingHorizontal: 12, paddingVertical: 6, borderRadius: radius.full,
  },
  receiptRemoveText: { color: '#fff', fontSize: 13, fontWeight: font.medium },
  catChip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 12, paddingVertical: 8, borderRadius: radius.full,
    borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bg,
  },
  catChipActive: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  catChipText: { fontSize: 13, fontWeight: font.medium, color: colors.textSecondary },
  catChipTextActive: { color: colors.brandDeep },

  saveBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingVertical: 18 },
  saveText: { color: '#fff', fontSize: 17, fontWeight: font.bold },
});
