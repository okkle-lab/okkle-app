import React, { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, StyleSheet, Pressable, Alert, Image, Animated, ActivityIndicator,
  KeyboardAvoidingView, Platform,
} from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import * as FileSystem from 'expo-file-system';
import * as Haptics from 'expo-haptics';
import { colors, font, spacing, radius, type, tabular } from '../../src/theme';
import { Feather } from '@expo/vector-icons';
import { useRouter, useLocalSearchParams, useFocusEffect } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Chip, VehicleChip, DatePickerField, IconBadge, SettingsGlassButton, KeyboardDoneAccessory, numberKeyboardDoneProps, ChipScroll, NativeGreenButton, GlassPanel } from '../../src/components';
import { calcDeduction, fmtGbp, VEHICLES } from '../../src/db/tax';
import { saveRecord, getUser, kvGet, kvSet, getPlatforms, getVehicleKeys, getLearnedCategory, learnCategory } from '../../src/db';
import { recognizeText } from '../../modules/okkle-vision';
import { parseReceipt } from '../../src/receiptParse';

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
type LogStep = 'kind' | 'receipt' | 'primary' | 'details' | 'date' | 'review';
const TABS: { key: Tab; label: string; icon: React.ComponentProps<typeof Feather>['name']; tone: 'red' | 'green' | 'blue'; title: string; sub: string }[] = [
  { key: 'expense', label: 'Expense', icon: 'file-text', tone: 'red', title: 'Add an expense', sub: 'A cost you can claim against tax' },
  { key: 'income', label: 'Earnings', icon: 'dollar-sign', tone: 'green', title: 'Log earnings', sub: 'A day or a week of pay — set the date below' },
  { key: 'mileage', label: 'Mileage', icon: 'map', tone: 'blue', title: 'Add mileage', sub: 'Miles you drove without GPS tracking' },
];

// Only ask the things that have a choice: mileage skips receipt+platform and only
// asks the vehicle when there's more than one; earnings only asks the platform
// when the user works more than one. Expense always needs its category.
function stepsFor(tab: Tab, multiVehicle: boolean, multiPlatform: boolean): LogStep[] {
  if (tab === 'mileage') {
    return multiVehicle ? ['kind', 'primary', 'details', 'date', 'review'] : ['kind', 'primary', 'date', 'review'];
  }
  if (tab === 'income') {
    return multiPlatform ? ['kind', 'receipt', 'primary', 'details', 'date', 'review'] : ['kind', 'receipt', 'primary', 'date', 'review'];
  }
  return ['kind', 'receipt', 'primary', 'details', 'date', 'review'];
}
const SUCCESS_SHEET_EDGE_GAP = spacing.sm;
const SUCCESS_SHEET_RADIUS = 40;

export default function LogScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const user = getUser();
  // Other screens can deep-link a tab (?tab=income).
  const params = useLocalSearchParams<{ tab?: string }>();
  const [tab, setTab] = useState<Tab>((params.tab === 'income' || params.tab === 'mileage') ? params.tab : 'expense');
  React.useEffect(() => {
    if (params.tab === 'income' || params.tab === 'mileage' || params.tab === 'expense') setTab(params.tab);
  }, [params.tab]);

  const [miles, setMiles] = useState('');
  // Platforms/vehicles are managed in Settings; we only show the chosen ones and
  // refresh on focus (e.g. after adding one in Settings).
  const [myVehicles, setMyVehicles] = useState(() => VEHICLES.filter(v => getVehicleKeys().includes(v.key)));
  const [vehicle, setVehicle] = useState(user?.vehicle ?? VEHICLES.find(v => getVehicleKeys().includes(v.key))?.key ?? 'car');
  const [platformList, setPlatformList] = useState(getPlatforms);
  const [platform, setPlatform] = useState(() => getPlatforms()[0]);

  useFocusEffect(
    React.useCallback(() => {
      const plats = getPlatforms();
      setPlatformList(plats);
      setPlatform(current => plats.includes(current) ? current : (plats[0] ?? ''));
      const vehicleKeys = getVehicleKeys();
      const nextVehicles = VEHICLES.filter(v => vehicleKeys.includes(v.key));
      setMyVehicles(nextVehicles);
      setVehicle(current => vehicleKeys.includes(current) ? current : (vehicleKeys[0] ?? 'car'));
    }, []),
  );
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [receiptUri, setReceiptUri] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [scannedMerchant, setScannedMerchant] = useState<string | null>(null);
  const [date, setDate] = useState(() => { const d = new Date(); d.setHours(12, 0, 0, 0); return d; });
  const [period, setPeriod] = useState<'day' | 'week'>('day');
  const [saved, setSaved] = useState(false);
  const [catCounts, setCatCounts] = useState(getCatCounts);
  const [descFocus, setDescFocus] = useState(false);
  const [stepIndex, setStepIndex] = useState(0);
  const [submitted, setSubmitted] = useState(false);
  const stepAnim = React.useRef(new Animated.Value(1)).current;
  const stepDirection = React.useRef(1);
  const successAnim = React.useRef(new Animated.Value(0)).current;

  // Predictive suggestions while typing a description: everything you've used
  // before (most-used first) plus the standard categories, matched by substring.
  const suggestionPool = React.useMemo(() => {
    const used = Object.entries(catCounts).sort((a, b) => b[1] - a[1]).map(([k]) => k);
    return Array.from(new Set([...used, ...EXPENSE_CATEGORIES.map(c => c.name)]));
  }, [catCounts]);
  const q = description.trim().toLowerCase();
  const suggestions = q.length > 0
    ? suggestionPool.filter(sg => sg.toLowerCase().includes(q) && sg.toLowerCase() !== q).slice(0, 6)
    : [];

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

  const tabIndex = Math.max(0, TABS.findIndex(t => t.key === tab));
  const active = TABS[tabIndex];
  const steps = stepsFor(tab, myVehicles.length > 1, platformList.length > 1);
  const currentStep = steps[stepIndex] ?? 'kind';

  React.useEffect(() => {
    if (!submitted) return;
    successAnim.setValue(0);
    Animated.spring(successAnim, {
      toValue: 1,
      useNativeDriver: true,
      speed: 18,
      bounciness: 5,
    }).start();
    // Briefly confirm "Saved to Records", then end — back to a fresh log screen.
    const id = setTimeout(() => { resetEntryFields(); resetWorkflow(); }, 1300);
    return () => clearTimeout(id);
  }, [submitted, successAnim]);

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
      scanReceipt(saved);
    }
  }

  // Read the receipt on-device (Apple Vision) and pre-fill the amount + category.
  // Best-effort: silently does nothing if the native module isn't present, and the
  // user always reviews/edits before saving.
  async function scanReceipt(uri: string) {
    setScanning(true);
    try {
      const { available, lines } = await recognizeText(uri);
      if (available && lines.length) {
        const { amount: amt, merchant, category, date: receiptDate } = parseReceipt(lines);
        if (amt && !amount && tab !== 'mileage') setAmount(amt.toFixed(2));
        // Prefer what Okkle has *learned* for this merchant, then the keyword guess,
        // then the merchant name.
        const learned = getLearnedCategory(merchant);
        if (tab === 'expense' && !description) setDescription(learned ?? category ?? merchant ?? '');
        if (receiptDate) setDate(receiptDate);
        setScannedMerchant(merchant);
      }
    } finally {
      setScanning(false);
    }
  }

  // Pass the record's date so a back-dated entry uses that tax year's rate.
  const deduction = miles ? calcDeduction(parseFloat(miles) || 0, vehicle, 0, date) : 0;

  function resetEntryFields() {
    setMiles('');
    setAmount('');
    setDescription('');
    setReceiptUri(null);
    setScannedMerchant(null);
    const t = new Date();
    t.setHours(12, 0, 0, 0);
    setDate(t);
  }

  function handleSave() {
    const createdAt = date.toISOString();
    // A weekly entry stores the Mon–Sun range so reports spread it across the days.
    const ps = period === 'week' ? wb.start.toISOString() : null;
    const pe = period === 'week' ? wb.end.toISOString() : null;
    if (tab === 'mileage') {
      if (!miles) { Alert.alert('Enter miles'); return; }
      saveRecord({ record_type: 'mileage', platform: null, vehicle, miles: parseFloat(miles), deduction, amount: null, category: null, period_start: ps, period_end: pe, receipt_uri: null, notes: null }, createdAt);
    } else if (tab === 'income') {
      if (!amount) { Alert.alert('Enter amount'); return; }
      saveRecord({ record_type: 'income', platform, amount: parseFloat(amount), miles: null, deduction: null, category: null, period_start: ps, period_end: pe, receipt_uri: receiptUri, notes: null }, createdAt);
    } else {
      if (!amount || !description) { Alert.alert('Enter amount and description'); return; }
      saveRecord({ record_type: 'expense', platform: null, amount: parseFloat(amount), miles: null, deduction: null, category: description, period_start: ps, period_end: pe, receipt_uri: receiptUri, notes: description }, createdAt);
      bumpCat(description); setCatCounts(getCatCounts());
      // Learn: this merchant → this category, so the next receipt nails it.
      if (scannedMerchant) learnCategory(scannedMerchant, description);
    }
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
    setSaved(true);
    setSubmitted(true);
  }

  const canSave = tab === 'mileage' ? !!miles : tab === 'income' ? !!amount : (!!amount && !!description);

  function goToStep(next: number) {
    const bounded = Math.max(0, Math.min(steps.length - 1, next));
    if (bounded === stepIndex) return;
    stepDirection.current = bounded > stepIndex ? 1 : -1;
    stepAnim.setValue(0);
    setStepIndex(bounded);
    Animated.timing(stepAnim, { toValue: 1, duration: 260, useNativeDriver: true }).start();
  }

  function chooseKind(nextTab: Tab) {
    setTab(nextTab);
    Haptics.selectionAsync().catch(() => {});
  }

  function resetWorkflow() {
    setSaved(false);
    setSubmitted(false);
    setStepIndex(0);
    stepDirection.current = 1;
    stepAnim.setValue(1);
  }

  function addAnotherLog() {
    resetEntryFields();
    resetWorkflow();
  }

  function viewRecords() {
    resetEntryFields();
    resetWorkflow();
    router.push('/records');
  }

  const canContinue =
    currentStep === 'kind' ? !!tab :
    currentStep === 'receipt' ? !scanning :
    currentStep === 'primary' ? (tab === 'mileage' ? !!miles : !!amount) :
    currentStep === 'details' ? (tab === 'expense' ? !!description.trim() : true) :
    currentStep === 'review' ? canSave :
    true;

  const nextLabel =
    currentStep === 'review' ? (saved ? 'Saved!' : 'Save entry') :
    currentStep === 'receipt' && !receiptUri ? 'Skip receipt' :
    'Continue';

  const kindOptions = [TABS[2], TABS[0], TABS[1]];
  const stepTitle =
    currentStep === 'kind' ? 'What are you logging?' :
    currentStep === 'receipt' ? 'Add a receipt' :
    currentStep === 'primary' ? (tab === 'mileage' ? 'How many miles?' : tab === 'income' ? 'How much did you earn?' : 'How much was it?') :
    currentStep === 'details' ? (tab === 'expense' ? 'What was it for?' : tab === 'mileage' ? 'Which vehicle?' : 'Which platform?') :
    currentStep === 'date' ? 'When was it?' :
    'Review and save';

  const stepSub =
    currentStep === 'kind' ? 'Okkle will ask one thing at a time.' :
    currentStep === 'receipt' ? (tab === 'expense' ? 'Take a photo or upload one, then Okkle will try to fill the next answers.' : 'Optional. Upload a receipt or screenshot and Okkle will fill what it can.') :
    currentStep === 'primary' ? (tab === 'mileage' ? 'Use the manually driven miles for this log.' : 'You can edit anything Okkle read from the receipt.') :
    currentStep === 'details' ? (tab === 'expense' ? 'Pick a category or type your own.' : tab === 'mileage' ? 'Which vehicle did you drive?' : 'Which app paid you?') :
    currentStep === 'date' ? 'Choose a day, or log the amount across a whole pay week.' :
    'Check the details before adding it to your records.';

  function renderReceiptStep() {
    return (
      <View style={s.stepStack}>
        {receiptUri ? (
          <View style={s.receiptWrap}>
            <Image source={{ uri: receiptUri }} style={s.receiptImgLarge} />
            <Pressable onPress={() => { setReceiptUri(null); setScannedMerchant(null); }} style={s.receiptRemove}>
              <Text style={s.receiptRemoveText}>Remove</Text>
            </Pressable>
            {scanning && (
              <View style={s.scanBadge}>
                <ActivityIndicator size="small" color="#fff" />
                <Text style={s.scanText}>Reading receipt...</Text>
              </View>
            )}
          </View>
        ) : null}
        {scannedMerchant ? (
          <View style={s.filledPill}>
            <Feather name="check-circle" size={16} color={colors.brandDeep} />
            <Text style={s.filledPillText}>Found {scannedMerchant}</Text>
          </View>
        ) : null}
        <NativeGreenButton label="Choose from photos" onPress={() => pickReceipt(false)} height={62} />
        <NativeGreenButton label="Take a photo" onPress={() => pickReceipt(true)} variant="neutral" height={62} />
      </View>
    );
  }

  function renderAmountGlass(children: React.ReactNode) {
    return (
      <GlassPanel
        tone={tab === 'expense' ? 'red' : tab === 'mileage' ? 'blue' : 'green'}
        minHeight={176}
        contentStyle={s.amountHeroContent}
      >
        {children}
      </GlassPanel>
    );
  }

  function renderPrimaryStep() {
    return tab === 'mileage' ? renderAmountGlass(
      <>
        <Text style={s.amountHeroLabel}>Miles driven</Text>
        <View style={s.amountHeroRow}>
          <TextInput
            style={s.amountHeroInput}
            placeholder="0"
            placeholderTextColor={colors.textTertiary}
            keyboardType="decimal-pad"
            value={miles}
            onChangeText={setMiles}
            autoFocus
            {...numberKeyboardDoneProps}
          />
          <Text style={s.amountHeroUnit}>mi</Text>
        </View>
        <Text style={s.amountHeroSub}>
          {miles ? `${fmtGbp(deduction)} tax deduction at the HMRC rate` : 'GPS tracking records miles more accurately in the Trip tab.'}
        </Text>
      </>
    ) : renderAmountGlass(
      <>
        <Text style={s.amountHeroLabel}>{tab === 'income' ? 'Amount received' : 'Amount spent'}</Text>
        <View style={s.amountHeroRow}>
          <Text style={s.amountHeroPrefix}>£</Text>
          <TextInput
            style={s.amountHeroInput}
            placeholder="0.00"
            placeholderTextColor={colors.textTertiary}
            keyboardType="decimal-pad"
            value={amount}
            onChangeText={setAmount}
            autoFocus
            {...numberKeyboardDoneProps}
          />
        </View>
        <Text style={s.amountHeroSub}>
          {tab === 'income' ? 'Gross pay before platform deductions.' : description || 'Receipt scans can prefill this.'}
        </Text>
      </>
    );
  }

  function renderDetailsStep() {
    if (tab === 'expense') {
      return (
        <View style={s.stepStack}>
          <ChipScroll>
            {sortedCats.map(cat => {
              const on = description === cat.name;
              return (
                <Pressable key={cat.name} onPress={() => setDescription(cat.name)} style={[s.catChip, on && s.catChipActive]}>
                  <Feather name={cat.icon} size={15} color={on ? colors.brandDeep : colors.textSecondary} />
                  <Text style={[s.catChipText, on && s.catChipTextActive]}>{cat.name}</Text>
                </Pressable>
              );
            })}
          </ChipScroll>
          <View style={s.searchWrap}>
            <Feather name="search" size={16} color={colors.textTertiary} />
            <TextInput
              style={s.searchInput}
              placeholder="Search or type your own"
              placeholderTextColor={colors.textTertiary}
              value={description}
              onChangeText={setDescription}
              onFocus={() => setDescFocus(true)}
              onBlur={() => setDescFocus(false)}
            />
          </View>
          {descFocus && suggestions.length > 0 && (
            <View style={s.suggestBox}>
              {suggestions.map((sg, i) => {
                const known = EXPENSE_CATEGORIES.find(c => c.name === sg);
                return (
                  <Pressable key={sg} onPress={() => { setDescription(sg); setDescFocus(false); }} style={[s.suggestRow, i < suggestions.length - 1 && s.suggestBorder]}>
                    <Feather name={known?.icon ?? 'corner-down-left'} size={15} color={colors.textSecondary} />
                    <Text style={s.suggestText}>{sg}</Text>
                  </Pressable>
                );
              })}
            </View>
          )}
          <View style={s.notice}>
            <Text style={s.noticeText}>Vehicle running costs are flagged for accountant review when you use simplified mileage.</Text>
          </View>
        </View>
      );
    }

    // Mileage: vehicle only (no platform — a day's miles aren't tied to one app).
    if (tab === 'mileage') {
      return (
        <View style={s.stepStack}>
          <View style={s.choiceGroup}>
            <Text style={s.groupLabel}>Vehicle</Text>
            <View style={s.wrapRow}>
              {myVehicles.map(v => (
                <VehicleChip key={v.key} vehicle={v.key} label={v.label} selected={vehicle === v.key} onPress={() => setVehicle(v.key)} />
              ))}
            </View>
          </View>
        </View>
      );
    }
    // Earnings: platform only.
    return (
      <View style={s.stepStack}>
        <View style={s.choiceGroup}>
          <Text style={s.groupLabel}>Platform</Text>
          <View style={s.wrapRow}>
            {platformList.map(p => (
              <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} size="lg" />
            ))}
          </View>
        </View>
      </View>
    );
  }

  function renderDateStep() {
    return (
      <View style={s.stepStack}>
        <View style={s.periodSegLarge}>
          {(['day', 'week'] as const).map(p => (
            <Pressable key={p} onPress={() => setPeriod(p)} style={[s.periodItemLarge, period === p && s.periodItemOn]}>
              <Text style={[s.periodText, period === p && s.periodTextOn]}>{p === 'day' ? 'Day' : 'Week'}</Text>
            </Pressable>
          ))}
        </View>
        {period === 'week' ? <Text style={s.weekHint}>Pick any day in the week you were paid for.</Text> : null}
        <DatePickerField value={date} onChange={setDate} quickChips={false} variant="ticker" />
        {period === 'week' ? (
          <Text style={s.weekCaption}>Covers {fmtShort(wb.start)} - {fmtShort(wb.end)}. Spread evenly across the 7 days.</Text>
        ) : null}
      </View>
    );
  }

  function renderReviewStep() {
    const rows = [
      ['Type', active.label],
      [tab === 'mileage' ? 'Miles' : 'Amount', tab === 'mileage' ? `${miles || '0'} mi` : fmtGbp(parseFloat(amount) || 0)],
      ...(tab === 'income' ? [['Platform', platform || '-']] : []),
      ...(tab === 'expense' ? [['Category', description || '-']] : []),
      ...(tab === 'mileage' ? [['Vehicle', myVehicles.find(v => v.key === vehicle)?.label ?? vehicle]] : []),
      ['When', period === 'week' ? `${fmtShort(wb.start)} - ${fmtShort(wb.end)}` : fmtShort(date)],
      ['Receipt', receiptUri ? 'Attached' : 'Not attached'],
    ];
    return (
      <View style={s.reviewCard}>
        <IconBadge icon={active.icon} tone={active.tone} size={48} />
        {rows.map(([label, value], index) => (
          <View key={label} style={[s.reviewRow, index < rows.length - 1 && s.reviewBorder]}>
            <Text style={s.reviewLabel}>{label}</Text>
            <Text style={s.reviewValue}>{value}</Text>
          </View>
        ))}
      </View>
    );
  }

  function renderStep() {
    if (currentStep === 'kind') {
      return (
        <View style={s.stepStack}>
          {kindOptions.map(t => {
            const on = tab === t.key;
            return (
              <Pressable key={t.key} onPress={() => chooseKind(t.key)} style={[s.kindCard, on && s.kindCardActive]}>
                <IconBadge icon={t.icon} tone={t.tone} size={48} />
                <View style={{ flex: 1 }}>
                  <Text style={s.kindTitle}>{t.label}</Text>
                  <Text style={s.kindSub}>{t.sub}</Text>
                </View>
                <Feather name={on ? 'check-circle' : 'circle'} size={24} color={on ? colors.brandDeep : colors.textTertiary} />
              </Pressable>
            );
          })}
        </View>
      );
    }
    if (currentStep === 'receipt') return renderReceiptStep();
    if (currentStep === 'primary') return renderPrimaryStep();
    if (currentStep === 'details') return renderDetailsStep();
    if (currentStep === 'date') return renderDateStep();
    return renderReviewStep();
  }

  function renderSuccessSheet() {
    if (!submitted) return null;

    return (
      <View style={s.successOverlay}>
        <View pointerEvents="none" style={s.successDim} />
        <Animated.View
          style={[
            s.successSheetWrap,
            {
              transform: [{ translateY: successAnim.interpolate({ inputRange: [0, 1], outputRange: [260, 0] }) }],
            },
          ]}
        >
          <GlassPanel
            tone="green"
            radius={SUCCESS_SHEET_RADIUS}
            isInteractive
            style={s.successSheet}
            clipStyle={s.successSheetClip}
            contentStyle={[s.successSheetContent, { paddingBottom: insets.bottom + spacing.xl }]}
          >
            <View style={s.successContent}>
              <View style={s.successBadge}>
                <Feather name="check" size={42} color="#fff" />
              </View>
              <Text style={s.successSub}>Saved to Records.</Text>
            </View>
          </GlassPanel>
        </Animated.View>
      </View>
    );
  }

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <View style={[s.header, { paddingTop: insets.top + spacing.sm }]}>
        <View style={{ flex: 1 }}>
          <Text style={s.headerEyebrow}>Log entry</Text>
          <Text style={s.headerTitle}>{active.label}</Text>
        </View>
        <SettingsGlassButton onPress={() => router.push('/settings')} />
      </View>

      <View style={s.progressTrack}>
        <View style={[s.progressFill, { width: `${((stepIndex + 1) / steps.length) * 100}%` }]} />
      </View>

      <ScrollView
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
        contentInsetAdjustmentBehavior="never"
        contentContainerStyle={[s.scrollContent, { paddingBottom: insets.bottom + 132 }]}
      >
        <Animated.View
          style={[
            s.page,
            {
              opacity: stepAnim,
              transform: [{ translateX: stepAnim.interpolate({ inputRange: [0, 1], outputRange: [stepDirection.current * 28, 0] }) }],
            },
          ]}
        >
          <Text style={s.stepCount}>Step {stepIndex + 1} of {steps.length}</Text>
          <Text style={s.questionTitle}>{stepTitle}</Text>
          <Text style={s.questionSub}>{stepSub}</Text>
          <View style={s.questionBody}>{renderStep()}</View>
        </Animated.View>
      </ScrollView>

      {!submitted ? (
        <View style={[s.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          <NativeGreenButton
            label="Back"
            onPress={() => goToStep(stepIndex - 1)}
            disabled={stepIndex === 0}
            variant="neutral"
            height={52}
            style={s.backBtnWrap}
            leftIcon={<Feather name="arrow-left" size={18} color={stepIndex === 0 ? colors.textTertiary : colors.textPrimary} />}
          />
          <NativeGreenButton
            label={nextLabel}
            onPress={() => currentStep === 'review' ? handleSave() : goToStep(stepIndex + 1)}
            disabled={!canContinue}
            style={s.nextBtnWrap}
          />
        </View>
      ) : null}
      {renderSuccessSheet()}
      <KeyboardDoneAccessory />
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  successOverlay: {
    position: 'absolute', left: 0, right: 0, top: 0, bottom: 0,
    justifyContent: 'flex-end',
  },
  successDim: {
    position: 'absolute', left: 0, right: 0, top: 0, bottom: 0,
    backgroundColor: 'rgba(15, 28, 25, 0.34)',
  },
  successSheetWrap: { paddingHorizontal: SUCCESS_SHEET_EDGE_GAP, paddingBottom: SUCCESS_SHEET_EDGE_GAP, zIndex: 1 },
  successSheet: { width: '100%', borderCurve: 'continuous' },
  successSheetClip: { backgroundColor: 'transparent', borderCurve: 'continuous' },
  successSheetContent: { paddingHorizontal: spacing.xl, paddingTop: spacing.xl, gap: spacing.xl },
  successContent: { alignItems: 'center', justifyContent: 'center', gap: spacing.md, paddingTop: spacing.md },
  successBadge: {
    width: 92, height: 92, borderRadius: radius.full,
    alignItems: 'center', justifyContent: 'center', backgroundColor: colors.green,
    boxShadow: '0 18px 34px rgba(47,163,107,0.28)',
  },
  successSub: { ...type.heading, fontSize: 25, color: colors.textPrimary, textAlign: 'center', lineHeight: 31, maxWidth: 300 },
  successActions: { gap: spacing.md },
  successSecondary: {
    height: 56, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: spacing.sm,
    borderRadius: radius.full, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bgCard,
  },
  successSecondaryText: { ...type.bodyMedium, color: colors.brandDeep },
  header: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    paddingHorizontal: spacing.xl, paddingBottom: spacing.md, backgroundColor: colors.bg,
  },
  headerEyebrow: { ...type.caption, color: colors.textTertiary, fontWeight: font.medium },
  headerTitle: { ...type.heading, fontSize: 24, marginTop: 2 },
  progressTrack: { height: 4, marginHorizontal: spacing.xl, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden' },
  progressFill: { height: '100%', borderRadius: radius.full, backgroundColor: colors.brand },
  scrollContent: { paddingHorizontal: spacing.xl, paddingTop: spacing.xl },
  page: { minHeight: 500 },
  stepCount: { ...type.caption, color: colors.brandDeep, fontWeight: font.bold, textTransform: 'uppercase', letterSpacing: 0.5 },
  questionTitle: { ...type.screenTitle, fontSize: 30, marginTop: spacing.sm },
  questionSub: { ...type.body, color: colors.textSecondary, lineHeight: 23, marginTop: spacing.sm },
  questionBody: { marginTop: spacing.xl },
  stepStack: { gap: spacing.md },
  kindCard: {
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    padding: spacing.lg, minHeight: 104, borderRadius: radius.xl,
    borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bgCard,
  },
  kindCardActive: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  kindTitle: { ...type.heading, fontSize: 18 },
  kindSub: { ...type.caption, lineHeight: 18, marginTop: 2 },
  receiptImgLarge: { width: '100%', height: 260, borderRadius: radius.xl, backgroundColor: colors.bgSoft },
  filledPill: {
    alignSelf: 'flex-start', flexDirection: 'row', alignItems: 'center', gap: 7,
    paddingHorizontal: 12, paddingVertical: 8, borderRadius: radius.full, backgroundColor: colors.brandLight,
  },
  filledPillText: { fontSize: 13, fontWeight: font.semibold, color: colors.brandDeep },
  choiceGroup: { gap: spacing.md },
  groupLabel: { ...type.label, fontWeight: font.bold, textTransform: 'uppercase', letterSpacing: 0.5 },
  periodSegLarge: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.lg, padding: 4 },
  periodItemLarge: { flex: 1, alignItems: 'center', paddingVertical: 12, borderRadius: radius.md },
  reviewCard: {
    gap: spacing.sm, padding: spacing.lg, borderRadius: radius.xl,
    borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bgCard,
  },
  reviewRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.lg, paddingVertical: spacing.md },
  reviewBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  reviewLabel: { ...type.label },
  reviewValue: { ...type.bodyMedium, flex: 1, textAlign: 'right' },
  footer: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    flexDirection: 'row', alignItems: 'center', gap: spacing.md,
    paddingHorizontal: spacing.xl, paddingTop: spacing.md,
    backgroundColor: colors.bg,
    borderTopWidth: 1, borderTopColor: colors.border,
  },
  backBtnWrap: { width: 112 },
  nextBtnWrap: { flex: 1 },

  tabs: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.lg, padding: 4, marginBottom: spacing.lg },
  tabPill: { position: 'absolute', top: 4, bottom: 4, left: 0, backgroundColor: colors.bgCard, borderRadius: radius.md, shadowColor: '#000', shadowOpacity: 0.08, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  tab: { flex: 1, paddingVertical: 10, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, borderRadius: radius.md },
  tabText: { fontSize: 14, fontWeight: font.medium, color: colors.textSecondary },
  tabTextActive: { color: colors.textPrimary, fontWeight: font.semibold },

  typeHead: { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: spacing.md },
  typeTitle: { ...type.heading, fontSize: 19 },
  typeSub: { ...type.caption, marginTop: 1 },

  amountHeroContent: { padding: spacing.lg },
  amountHeroLabel: { color: colors.textSecondary, fontSize: 13, fontWeight: font.semibold },
  amountHeroRow: { flexDirection: 'row', alignItems: 'center', marginTop: 4 },
  amountHeroPrefix: { ...tabular, color: colors.textPrimary, fontSize: 34, fontWeight: font.bold, marginRight: 4 },
  amountHeroInput: { ...tabular, flex: 1, color: colors.textPrimary, fontSize: 42, fontWeight: font.bold, letterSpacing: -1, paddingVertical: 4 },
  amountHeroUnit: { color: colors.textPrimary, fontSize: 22, fontWeight: font.semibold, marginLeft: 6 },
  amountHeroSub: { color: colors.textSecondary, fontSize: 13, marginTop: 2, lineHeight: 18 },

  input: {
    borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg,
  },
  chipRow: { flexDirection: 'row', gap: spacing.sm, paddingRight: spacing.lg },
  searchWrap: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: spacing.sm, borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, paddingHorizontal: spacing.md, backgroundColor: colors.bg },
  searchInput: { flex: 1, fontSize: 16, color: colors.textPrimary, paddingVertical: 12 },
  suggestBox: { marginTop: spacing.sm, backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.border, borderRadius: radius.md, overflow: 'hidden' },
  suggestRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 12, paddingHorizontal: spacing.md },
  suggestBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  suggestText: { ...type.bodyMedium, fontSize: 15 },

  dateBlock: { borderTopWidth: 1, borderTopColor: colors.border, paddingTop: spacing.lg, gap: spacing.md },
  dateHeadRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  dateLabel: { ...type.bodyMedium, fontSize: 15, flex: 1 },
  periodSeg: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.md, padding: 3 },
  periodItem: { paddingHorizontal: 14, paddingVertical: 6, borderRadius: radius.sm },
  periodItemOn: { backgroundColor: colors.bgCard, shadowColor: '#000', shadowOpacity: 0.06, shadowRadius: 3, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  periodText: { fontSize: 13, fontWeight: font.medium, color: colors.textSecondary },
  periodTextOn: { color: colors.textPrimary, fontWeight: font.semibold },
  weekCaption: { ...type.caption, color: colors.brandDeep, fontWeight: font.medium, marginTop: spacing.sm },
  weekHint: { ...type.caption, color: colors.textSecondary, marginBottom: spacing.sm },
  wrapRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  addChip: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 14, paddingVertical: 10, borderRadius: radius.full, borderWidth: 1.5, borderStyle: 'dashed', borderColor: colors.brandMid, backgroundColor: colors.bg },
  addChipText: { ...type.bodyMedium, fontSize: 14, color: colors.brandDeep },
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
  scanBadge: { position: 'absolute', left: 8, bottom: 8, flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: 'rgba(0,0,0,0.6)', paddingHorizontal: 12, paddingVertical: 7, borderRadius: radius.full },
  scanText: { color: '#fff', fontSize: 13, fontWeight: font.medium },
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

});
