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
import { saveRecord, getUser } from '../../src/db';

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

const EXPENSE_CATEGORIES = [
  'Charging', 'Fuel', 'Maintenance / repairs', 'Tyres',
  'Waterproof gear', 'Helmet / safety', 'Phone mount', 'Insulated bag',
  'Insurance', 'Congestion charge', 'ULEZ charge', 'Parking',
  'Phone / data', 'App subscription',
];

type Tab = 'mileage' | 'income' | 'expense';
const TABS: { key: Tab; label: string; icon: React.ComponentProps<typeof Feather>['name']; tone: 'amber' | 'green' | 'mint'; title: string; sub: string }[] = [
  { key: 'expense', label: 'Expense', icon: 'file-text', tone: 'amber', title: 'Add an expense', sub: 'A cost you can claim against tax' },
  { key: 'income', label: 'Earnings', icon: 'dollar-sign', tone: 'green', title: 'Log earnings', sub: 'Your weekly pay from a platform' },
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
  const [saved, setSaved] = useState(false);

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
    if (tab === 'mileage') {
      if (!miles) { Alert.alert('Enter miles'); return; }
      saveRecord({ record_type: 'mileage', platform, miles: parseFloat(miles), deduction, amount: null, category: null, period_start: null, period_end: null, receipt_uri: null, notes: null }, createdAt);
    } else if (tab === 'income') {
      if (!amount) { Alert.alert('Enter amount'); return; }
      saveRecord({ record_type: 'income', platform, amount: parseFloat(amount), miles: null, deduction: null, category: null, period_start: null, period_end: null, receipt_uri: null, notes: null }, createdAt);
    } else {
      if (!amount || !description) { Alert.alert('Enter amount and description'); return; }
      saveRecord({ record_type: 'expense', platform: null, amount: parseFloat(amount), miles: null, deduction: null, category: description, period_start: null, period_end: null, receipt_uri: receiptUri, notes: description }, createdAt);
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
                  {EXPENSE_CATEGORIES.map(cat => (
                    <Pressable key={cat} onPress={() => setDescription(cat)} style={[s.catChip, description === cat && s.catChipActive]}>
                      <Text style={[s.catChipText, description === cat && s.catChipTextActive]}>{cat}</Text>
                    </Pressable>
                  ))}
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

          {/* Date — compact, defaults to today */}
          <View style={s.dateRow}>
            <IconBadge icon="calendar" tone="neutral" size={32} />
            <Text style={s.dateLabel}>Date</Text>
            <View style={{ flex: 1 }}>
              <DatePickerField value={date} onChange={setDate} />
            </View>
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

  dateRow: { flexDirection: 'row', alignItems: 'center', gap: 12, borderTopWidth: 1, borderTopColor: colors.border, paddingTop: spacing.lg },
  dateLabel: { ...type.bodyMedium, fontSize: 15 },

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
    paddingHorizontal: 12, paddingVertical: 8, borderRadius: radius.full,
    borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bg,
  },
  catChipActive: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  catChipText: { fontSize: 13, fontWeight: font.medium, color: colors.textSecondary },
  catChipTextActive: { color: colors.brandDeep },

  saveBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingVertical: 18 },
  saveText: { color: '#fff', fontSize: 17, fontWeight: font.bold },
});
