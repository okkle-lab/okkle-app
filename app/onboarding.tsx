import { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, KeyboardAvoidingView,
  Platform, Pressable, StyleSheet, ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import * as Location from 'expo-location';
import { colors, font, radius, spacing, type } from '../src/theme';
import { VEHICLES, PLATFORMS, REGIONS, regionFromArea, regionRate, regionLabel } from '../src/db/tax';
import { saveUser, getUser } from '../src/db';
import { syncReminders } from '../src/notifications';
import { Feather } from '@expo/vector-icons';
import { PrimaryButton, Chip, VehicleChip } from '../src/components';

const STEPS = ['Welcome', 'Name', 'Vehicle', 'Platforms', 'Region', 'Ready'];

export default function Onboarding() {
  const router = useRouter();
  const [step, setStep] = useState(0);
  const [name, setName] = useState('');
  const [vehicles, setVehicles] = useState<string[]>(['car']);
  const [platforms, setPlatforms] = useState<string[]>(['Uber Eats']);
  const [region, setRegion] = useState('ruk');
  const [band, setBand] = useState<'basic' | 'higher'>('basic');
  const [detecting, setDetecting] = useState(false);

  function persist() {
    saveUser({
      name, vehicle: vehicles[0] ?? 'car', vehicles: vehicles.join(','),
      platforms: platforms.join(','), region,
      tax_rate: regionRate(region, band), onboarded: 1,
    });
    const u = getUser();
    if (u) { syncReminders(u).catch(() => {}); }
  }

  async function next() {
    if (step < STEPS.length - 1) { setStep(s => s + 1); return; }
    persist();
    router.replace('/(tabs)');
  }

  // On the final step, "Start a trip" saves and jumps straight to the Trip tab.
  function finishToTrip() {
    persist();
    router.replace('/(tabs)/trip');
  }

  function togglePlatform(p: string) {
    setPlatforms(prev => (prev.includes(p) ? prev.filter(x => x !== p) : [...prev, p]));
  }

  async function detectRegion() {
    setDetecting(true);
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') { setDetecting(false); return; }
      const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Low });
      const places = await Location.reverseGeocodeAsync(loc.coords);
      const area = places[0]?.region ?? places[0]?.subregion ?? null;
      setRegion(regionFromArea(area));
    } catch {
      // leave default
    }
    setDetecting(false);
  }

  const canContinue =
    step === 1 ? name.trim().length > 0 :
    step === 2 ? vehicles.length > 0 :
    step === 3 ? platforms.length > 0 :
    true;

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.bg }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.container} keyboardShouldPersistTaps="handled">
        <View style={s.progress}>
          {STEPS.map((_, i) => (
            <View key={i} style={[s.dot, i <= step && s.dotActive, i === step && s.dotCurrent]} />
          ))}
        </View>

        {step === 0 && (
          <View style={s.stepContent}>
            <View style={s.welcomeIcon}>
              <Feather name="navigation" size={30} color="#fff" />
            </View>
            <Text style={s.logo}>Okkle</Text>
            <Text style={s.hero}>Drive smarter.{'\n'}Keep more of it.</Text>
            <Text style={s.sub}>
              Built for UK delivery couriers. Okkle tracks your trips, shows you where the money is, and keeps you ready for the taxman — without the spreadsheet.
            </Text>
            <View style={s.welcomeList}>
              {[
                { icon: 'navigation' as const, text: 'Track every trip automatically with GPS' },
                { icon: 'trending-up' as const, text: 'See where and when you earn the most' },
                { icon: 'shield' as const, text: 'Stay HMRC-ready — and know what to set aside' },
                { icon: 'award' as const, text: 'Build streaks, earn medals, level up' },
              ].map(item => (
                <View key={item.text} style={s.welcomeRow}>
                  <View style={s.welcomeDot}><Feather name={item.icon} size={15} color={colors.brandDeep} /></View>
                  <Text style={s.welcomeText}>{item.text}</Text>
                </View>
              ))}
            </View>
            <Text style={s.note}>Your data stays on your phone.</Text>
          </View>
        )}

        {step === 1 && (
          <View style={s.stepContent}>
            <Text style={s.hero}>First — what{'\n'}should we call you?</Text>
            <Text style={s.sub}>So Okkle feels like yours.</Text>
            <TextInput
              style={s.input}
              placeholder="Your first name"
              placeholderTextColor={colors.textTertiary}
              value={name}
              onChangeText={setName}
              autoFocus
              returnKeyType="next"
              onSubmitEditing={() => { if (name.trim()) next(); }}
            />
          </View>
        )}

        {step === 2 && (
          <View style={s.stepContent}>
            <Text style={s.hero}>What do you{'\n'}ride or drive?</Text>
            <Text style={s.sub}>Pick all you use — each sets its own HMRC mileage rate, the tax-free amount you can claim per mile. You’ll choose which one per trip.</Text>
            <View style={s.chipGrid}>
              {VEHICLES.map(v => (
                <VehicleChip
                  key={v.key}
                  vehicle={v.key}
                  label={v.label}
                  suffix={`${(v.rate * 100).toFixed(0)}p/mi`}
                  selected={vehicles.includes(v.key)}
                  onPress={() => setVehicles(list =>
                    list.includes(v.key) ? list.filter(x => x !== v.key) : [...list, v.key])}
                  style={{ marginBottom: spacing.sm }}
                />
              ))}
            </View>
            <Text style={s.note}>
              Okkle works out your tax the simple way — HMRC’s flat-rate mileage (a set amount per mile that already covers fuel, insurance and repairs). It’s the easiest method and the best fit for most couriers. If you drive an expensive or electric car, the “actual costs” method can sometimes save more — worth asking an accountant.
            </Text>
          </View>
        )}

        {step === 3 && (
          <View style={s.stepContent}>
            <Text style={s.hero}>Who do you{'\n'}deliver for?</Text>
            <Text style={s.sub}>Pick all that apply. Okkle will show you which one actually pays you best per hour.</Text>
            <View style={s.chipGrid}>
              {PLATFORMS.map(p => (
                <Chip
                  key={p}
                  label={p}
                  selected={platforms.includes(p)}
                  onPress={() => togglePlatform(p)}
                  size="lg"
                  style={{ marginBottom: spacing.sm }}
                />
              ))}
            </View>
          </View>
        )}

        {step === 4 && (
          <View style={s.stepContent}>
            <Text style={s.hero}>Where are{'\n'}you based?</Text>
            <Text style={s.sub}>Scotland's income tax rates differ slightly. This is where you live, not where you drive — and it only sharpens your take-home estimate.</Text>

            <Pressable onPress={detectRegion} style={s.detectBtn}>
              {detecting ? (
                <ActivityIndicator color={colors.brand} size="small" />
              ) : (
                <>
                  <Feather name="map-pin" size={16} color={colors.brandDeep} />
                  <Text style={s.detectText}>Detect from my location</Text>
                </>
              )}
            </Pressable>

            <View style={s.chipGrid}>
              {REGIONS.map(r => (
                <Chip
                  key={r.key}
                  label={r.label}
                  selected={region === r.key}
                  onPress={() => setRegion(r.key)}
                  size="lg"
                  style={{ marginBottom: spacing.sm }}
                />
              ))}
            </View>

            <Text style={[s.sub, { marginTop: spacing.lg, marginBottom: spacing.sm }]}>Your income tax band</Text>
            <View style={s.chipGrid}>
              <Chip label="Basic rate" selected={band === 'basic'} onPress={() => setBand('basic')} size="lg" style={{ marginBottom: spacing.sm }} />
              <Chip label="Higher rate" selected={band === 'higher'} onPress={() => setBand('higher')} size="lg" style={{ marginBottom: spacing.sm }} />
            </View>

            <Text style={s.note}>
              We'll estimate your tax at {(regionRate(region, band) * 100).toFixed(0)}% ({regionLabel(region)}). Okkle is a tracking tool, not tax advice — your accountant confirms the final figures.
            </Text>
          </View>
        )}

        {step === 5 && (
          <View style={s.stepContent}>
            <View style={s.readyIcon}><Feather name="check" size={30} color="#fff" /></View>
            <Text style={s.hero}>You're set,{'\n'}{name || 'let’s go'}.</Text>
            <Text style={s.sub}>Here's how to get the most out of Okkle:</Text>

            <View style={s.doList}>
              {[
                { n: '1', icon: 'navigation' as const, title: 'Start a trip when you set off', body: 'GPS measures your miles and your tax savings as you ride.' },
                { n: '2', icon: 'dollar-sign' as const, title: 'Log your pay each week', body: 'Most couriers add their Friday bank transfer — it keeps your numbers honest.' },
                { n: '3', icon: 'trending-up' as const, title: 'Check Insights', body: 'After a week, see the spots and times that pay you best.' },
              ].map(item => (
                <View key={item.n} style={s.doRow}>
                  <View style={s.doNum}><Text style={s.doNumText}>{item.n}</Text></View>
                  <View style={{ flex: 1 }}>
                    <Text style={s.doTitle}>{item.title}</Text>
                    <Text style={s.doBody}>{item.body}</Text>
                  </View>
                </View>
              ))}
            </View>

            <View style={s.streakNote}>
              <Text style={{ fontSize: 16 }}>🔥</Text>
              <Text style={s.streakNoteText}>Track something every day to build your streak, earn medals and climb the ranks.</Text>
            </View>
          </View>
        )}

        <View style={s.footer}>
          {step === STEPS.length - 1 ? (
            <>
              <PrimaryButton label="Start my first trip" onPress={finishToTrip} />
              <Pressable onPress={next} style={{ marginTop: 14, alignItems: 'center' }}>
                <Text style={s.backText}>Explore the app first</Text>
              </Pressable>
            </>
          ) : (
            <>
              <PrimaryButton label={step === 0 ? 'Get started' : 'Continue'} onPress={next} disabled={!canContinue} />
              {step > 0 && (
                <Pressable onPress={() => setStep(s => s - 1)} style={{ marginTop: 14, alignItems: 'center' }}>
                  <Text style={s.backText}>Back</Text>
                </Pressable>
              )}
            </>
          )}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  container: { flexGrow: 1, padding: spacing.xl, paddingTop: 64 },
  progress: { flexDirection: 'row', gap: 5, marginBottom: spacing.xxl },
  dot: { height: 5, flex: 1, borderRadius: radius.full, backgroundColor: colors.border },
  dotActive: { backgroundColor: colors.brandMid },
  dotCurrent: { backgroundColor: colors.brand },
  stepContent: { flex: 1, paddingBottom: spacing.xl },
  welcomeIcon: { width: 62, height: 62, borderRadius: 20, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center', marginBottom: spacing.lg },
  readyIcon: { width: 62, height: 62, borderRadius: 31, backgroundColor: colors.green, alignItems: 'center', justifyContent: 'center', marginBottom: spacing.lg },
  welcomeList: { marginTop: spacing.xl, gap: spacing.lg },
  welcomeRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  welcomeDot: { width: 34, height: 34, borderRadius: 17, backgroundColor: colors.brandLight, alignItems: 'center', justifyContent: 'center' },
  welcomeText: { ...type.body, color: colors.textPrimary, flex: 1 },
  logo: { fontSize: 30, fontWeight: font.bold, color: colors.brand, letterSpacing: -1, marginBottom: spacing.md },
  hero: { ...type.hero, lineHeight: 38, marginBottom: spacing.md },
  sub: { ...type.body, color: colors.textSecondary, lineHeight: 24, marginBottom: spacing.xl },
  input: {
    borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    padding: spacing.lg, fontSize: 18, color: colors.textPrimary,
    backgroundColor: colors.bgCard,
  },
  chipGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  detectBtn: {
    borderWidth: 1.5, borderColor: colors.brandMid, borderRadius: radius.md,
    paddingVertical: 14, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    marginBottom: spacing.lg, backgroundColor: colors.brandLight,
  },
  detectText: { ...type.bodyMedium, color: colors.brandDeep },
  note: { ...type.caption, color: colors.textTertiary, lineHeight: 20, marginTop: spacing.lg },

  doList: { gap: spacing.lg, marginTop: spacing.xs },
  doRow: { flexDirection: 'row', gap: 14, alignItems: 'flex-start' },
  doNum: { width: 28, height: 28, borderRadius: 14, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  doNumText: { color: '#fff', fontWeight: font.bold, fontSize: 14 },
  doTitle: { ...type.bodyMedium, fontSize: 16 },
  doBody: { ...type.caption, color: colors.textSecondary, lineHeight: 20, marginTop: 2 },
  streakNote: { flexDirection: 'row', gap: 10, alignItems: 'center', backgroundColor: colors.amberLight, borderRadius: radius.md, padding: spacing.lg, marginTop: spacing.xl },
  streakNoteText: { ...type.caption, color: colors.amberDark, flex: 1, lineHeight: 19 },

  footer: { marginTop: 'auto', paddingTop: spacing.xl },
  backText: { ...type.label, color: colors.textSecondary },
});
