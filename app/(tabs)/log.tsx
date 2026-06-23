import React, { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, StyleSheet, Pressable, Alert, Image,
} from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import * as FileSystem from 'expo-file-system';
import * as Haptics from 'expo-haptics';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { Feather } from '@expo/vector-icons';
import { Chip, PrimaryButton, Card, SectionHeader, VehicleChip, DatePickerField, ScreenHeader } from '../../src/components';
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

export default function LogScreen() {
  const user = getUser();
  // Expense first, then earnings; manual mileage last so GPS tracking is the
  // encouraged way to record miles.
  const [tab, setTab] = useState<Tab>('expense');

  const [miles, setMiles] = useState('');
  const [vehicle, setVehicle] = useState(user?.vehicle ?? 'car');
  const [platform, setPlatform] = useState(user?.platforms?.split(',')[0] ?? 'Uber Eats');
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [receiptUri, setReceiptUri] = useState<string | null>(null);
  const [date, setDate] = useState(() => { const d = new Date(); d.setHours(12, 0, 0, 0); return d; });
  const [saved, setSaved] = useState(false);

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

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
      <ScreenHeader title="Log entry" />

      <View style={s.tabs}>
        {([
          ['expense', 'Expense', 'file-text'],
          ['income', 'Earnings', 'dollar-sign'],
          ['mileage', 'Mileage', 'map'],
        ] as [Tab, string, React.ComponentProps<typeof Feather>['name']][]).map(([t, label, icon]) => (
          <Pressable key={t} onPress={() => setTab(t)} style={[s.tab, tab === t && s.tabActive]}>
            <Feather name={icon} size={16} color={tab === t ? colors.textPrimary : colors.textSecondary} />
            <Text style={[s.tabText, tab === t && s.tabTextActive]}>{label}</Text>
          </Pressable>
        ))}
      </View>

      {/* Date — defaults to today; back-date a receipt or pay from any past day. */}
      <Card style={{ marginBottom: spacing.md }}>
        <SectionHeader title="Date" />
        <DatePickerField value={date} onChange={setDate} />
      </Card>

      {tab === 'mileage' && (
        <Card style={{ gap: spacing.md }}>
          <View style={s.gpsHint}>
            <Feather name="navigation" size={14} color={colors.brandDeep} />
            <Text style={s.gpsHintText}>Tip: tracking a trip with GPS records miles automatically and more accurately.</Text>
          </View>
          <View>
            <SectionHeader title="Miles driven" />
            <TextInput
              style={s.input}
              placeholder="e.g. 120"
              placeholderTextColor={colors.textTertiary}
              keyboardType="decimal-pad"
              value={miles}
              onChangeText={setMiles}
            />
            {miles ? (
              <Text style={s.deductionPreview}>
                Mileage deduction: {fmtGbp(deduction)} at HMRC rate
              </Text>
            ) : null}
          </View>
          <View>
            <SectionHeader title="Vehicle" />
            <View style={s.chips}>
              {VEHICLES.map(v => (
                <VehicleChip key={v.key} vehicle={v.key} label={v.label} selected={vehicle === v.key} onPress={() => setVehicle(v.key)} />
              ))}
            </View>
          </View>
          <View>
            <SectionHeader title="Platform" />
            <View style={s.chips}>
              {PLATFORMS.map(p => (
                <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} size="lg" />
              ))}
            </View>
          </View>
        </Card>
      )}

      {tab === 'income' && (
        <Card style={{ gap: spacing.md }}>
          <View>
            <SectionHeader title="Platform" />
            <View style={s.chips}>
              {PLATFORMS.map(p => (
                <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} size="lg" />
              ))}
            </View>
          </View>
          <View>
            <SectionHeader title="Amount (£)" />
            <TextInput
              style={s.input}
              placeholder="0.00"
              placeholderTextColor={colors.textTertiary}
              keyboardType="decimal-pad"
              value={amount}
              onChangeText={setAmount}
            />
          </View>
        </Card>
      )}

      {tab === 'expense' && (
        <Card style={{ gap: spacing.md }}>
          <View>
            <SectionHeader title="Category" />
            <View style={s.chips}>
              {EXPENSE_CATEGORIES.map(cat => (
                <Pressable
                  key={cat}
                  onPress={() => setDescription(cat)}
                  style={[s.catChip, description === cat && s.catChipActive]}
                >
                  <Text style={[s.catChipText, description === cat && s.catChipTextActive]}>{cat}</Text>
                </Pressable>
              ))}
            </View>
            <TextInput
              style={[s.input, { marginTop: spacing.sm }]}
              placeholder="Or type your own description"
              placeholderTextColor={colors.textTertiary}
              value={description}
              onChangeText={setDescription}
            />
          </View>
          <View>
            <SectionHeader title="Amount (£)" />
            <TextInput
              style={s.input}
              placeholder="0.00"
              placeholderTextColor={colors.textTertiary}
              keyboardType="decimal-pad"
              value={amount}
              onChangeText={setAmount}
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
              Vehicle running costs (fuel, tyres, repairs) are flagged for accountant review when you use simplified mileage — your accountant will advise.
            </Text>
          </View>
        </Card>
      )}

      <PrimaryButton
        label={saved ? '✓ Saved!' : 'Save entry'}
        onPress={handleSave}
        variant={saved ? 'ghost' : 'primary'}
        style={{ marginTop: spacing.lg }}
      />
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  heading: { ...type.screenTitle, marginBottom: spacing.lg },
  tabs: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.lg, padding: 4, marginBottom: spacing.lg },
  tab: { flex: 1, paddingVertical: 10, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, borderRadius: radius.md },
  tabActive: { backgroundColor: colors.bgCard },
  tabText: { fontSize: 14, fontWeight: font.medium, color: colors.textSecondary },
  tabTextActive: { color: colors.textPrimary, fontWeight: font.semibold },
  input: {
    borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    padding: spacing.md, fontSize: 17, color: colors.textPrimary,
    backgroundColor: colors.bgCard,
  },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  deductionPreview: { fontSize: 14, color: colors.brandDeep, fontWeight: font.medium, marginTop: 8 },
  notice: { backgroundColor: colors.amberLight, borderRadius: radius.md, padding: spacing.md },
  noticeText: { fontSize: 13, color: colors.amber, lineHeight: 19 },
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
  gpsHint: { flexDirection: 'row', gap: 8, alignItems: 'flex-start', backgroundColor: colors.brandLight, borderRadius: radius.md, padding: spacing.md },
  gpsHintText: { ...type.caption, color: colors.brandDeep, flex: 1, lineHeight: 18 },
  catChip: {
    paddingHorizontal: 12, paddingVertical: 8, borderRadius: radius.full,
    borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bg,
    marginBottom: spacing.xs ?? 4,
  },
  catChipActive: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  catChipText: { fontSize: 13, fontWeight: font.medium, color: colors.textSecondary },
  catChipTextActive: { color: colors.brandDeep },
});
