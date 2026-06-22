import React, { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, KeyboardAvoidingView,
  Platform, Pressable, StyleSheet, ActivityIndicator,
} from 'react-native';
import { useRouter } from 'expo-router';
import * as Location from 'expo-location';
import { colors, font, radius, spacing, type } from '../src/theme';
import { VEHICLES, PLATFORMS, REGIONS, regionFromArea, regionRate, regionLabel } from '../src/db/tax';
import { saveUser } from '../src/db';
import { PrimaryButton, Chip } from '../src/components';

const STEPS = ['Welcome', 'Name', 'Vehicle', 'Platforms', 'Region'];

export default function Onboarding() {
  const router = useRouter();
  const [step, setStep] = useState(0);
  const [name, setName] = useState('');
  const [vehicle, setVehicle] = useState('car');
  const [platforms, setPlatforms] = useState<string[]>(['Uber Eats']);
  const [region, setRegion] = useState('ruk');
  const [band, setBand] = useState<'basic' | 'higher'>('basic');
  const [detecting, setDetecting] = useState(false);

  function next() {
    if (step < STEPS.length - 1) { setStep(s => s + 1); return; }
    saveUser({
      name,
      vehicle,
      platforms: platforms.join(','),
      region,
      tax_rate: regionRate(region, band),
      onboarded: 1,
    });
    router.replace('/(tabs)');
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
    step === 0 ? true :
    step === 1 ? name.trim().length > 0 :
    step === 2 ? !!vehicle :
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
            <Text style={s.logo}>Okkle</Text>
            <Text style={s.hero}>Track your miles,{'\n'}keep more money.</Text>
            <Text style={s.sub}>Friendly mileage tracking built for UK delivery couriers. Free forever, and your data stays on your phone.</Text>
          </View>
        )}

        {step === 1 && (
          <View style={s.stepContent}>
            <Text style={s.hero}>What should we{'\n'}call you?</Text>
            <TextInput
              style={s.input}
              placeholder="Your first name"
              placeholderTextColor={colors.textTertiary}
              value={name}
              onChangeText={setName}
              autoFocus
              returnKeyType="next"
              onSubmitEditing={next}
            />
          </View>
        )}

        {step === 2 && (
          <View style={s.stepContent}>
            <Text style={s.hero}>What do you{'\n'}deliver with?</Text>
            <Text style={s.sub}>We use HMRC's approved mileage rates — these are the same across the whole UK.</Text>
            <View style={s.chipGrid}>
              {VEHICLES.map(v => (
                <Chip
                  key={v.key}
                  label={`${v.icon}  ${v.label} · ${(v.rate * 100).toFixed(0)}p/mi`}
                  selected={vehicle === v.key}
                  onPress={() => setVehicle(v.key)}
                  size="lg"
                  style={{ marginBottom: spacing.sm }}
                />
              ))}
            </View>
          </View>
        )}

        {step === 3 && (
          <View style={s.stepContent}>
            <Text style={s.hero}>Which platforms{'\n'}do you work for?</Text>
            <Text style={s.sub}>Select all that apply — you can change this anytime.</Text>
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
            <Text style={s.hero}>Where are you{'\n'}based?</Text>
            <Text style={s.sub}>Scotland has slightly different income tax rates to the rest of the UK. This is based on where you live, not where you drive. Used only to estimate your take-home.</Text>

            <Pressable onPress={detectRegion} style={s.detectBtn}>
              {detecting ? (
                <ActivityIndicator color={colors.brand} size="small" />
              ) : (
                <Text style={s.detectText}>📍  Detect from my location</Text>
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
              You'll be taxed at {(regionRate(region, band) * 100).toFixed(0)}% ({regionLabel(region)}). Okkle is a tracking tool, not tax advice — your accountant confirms the final figures.
            </Text>
          </View>
        )}

        <View style={s.footer}>
          <PrimaryButton
            label={step === STEPS.length - 1 ? "Let's go" : 'Continue'}
            onPress={next}
            disabled={!canContinue}
          />
          {step > 0 && (
            <Pressable onPress={() => setStep(s => s - 1)} style={{ marginTop: 14, alignItems: 'center' }}>
              <Text style={s.backText}>Back</Text>
            </Pressable>
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
  logo: { fontSize: 32, fontWeight: font.bold, color: colors.brand, letterSpacing: -1, marginBottom: spacing.lg },
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
    paddingVertical: 14, alignItems: 'center', marginBottom: spacing.lg,
    backgroundColor: colors.brandLight,
  },
  detectText: { ...type.bodyMedium, color: colors.brandDeep },
  note: { ...type.caption, color: colors.textTertiary, lineHeight: 20, marginTop: spacing.lg },
  footer: { marginTop: 'auto', paddingTop: spacing.xl },
  backText: { ...type.label, color: colors.textSecondary },
});
