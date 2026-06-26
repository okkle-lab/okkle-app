import { useState } from 'react';
import { View, Text, TextInput, StyleSheet, Pressable, Alert } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, spacing, radius, type } from '../src/theme';
import { Card, Chip, PrimaryButton, VehicleChip, ModalHeader, ChipScroll } from '../src/components';
import { VEHICLES, PLATFORMS, REGIONS, regionRate, regionLabel } from '../src/db/tax';
import { getUser, saveUser } from '../src/db';

// Fixed (non-scrolling) layout: the whole form fits one screen and Save is
// pinned to the bottom, so Settings never needs to scroll.
export default function SettingsAccount() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const u = getUser();
  const [name, setName] = useState(u?.name ?? '');
  const [vehicles, setVehicles] = useState<string[]>(
    u?.vehicles?.split(',').map(s => s.trim()).filter(Boolean) ?? (u?.vehicle ? [u.vehicle] : ['car']),
  );
  const [platforms, setPlatforms] = useState<string[]>(
    u?.platforms?.split(',').map(s => s.trim()).filter(p => p && p.toLowerCase() !== 'other') ?? ['Uber Eats'],
  );
  const [region, setRegion] = useState(u?.region ?? 'ruk');
  const [band, setBand] = useState<'basic' | 'higher'>((u?.tax_rate ?? 0.2) >= 0.4 ? 'higher' : 'basic');

  const toggle = (p: string) => setPlatforms(prev => (prev.includes(p) ? prev.filter(x => x !== p) : [...prev, p]));
  const toggleVehicle = (k: string) => setVehicles(prev => (prev.includes(k) ? prev.filter(x => x !== k) : [...prev, k]));
  const allOptions = Array.from(new Set([...PLATFORMS, ...platforms])).filter(p => p.toLowerCase() !== 'other');

  function addCustom() {
    Alert.prompt('Add platform', 'Name of the delivery platform you work for', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Add', onPress: (n?: string) => {
        const clean = (n ?? '').trim();
        if (clean && !platforms.some(p => p.toLowerCase() === clean.toLowerCase())) setPlatforms([...platforms, clean]);
      } },
    ], 'plain-text');
  }

  function save() {
    const v = vehicles.length ? vehicles : ['car'];
    const cleaned = platforms.filter(p => p.trim() && p.toLowerCase() !== 'other');
    saveUser({ name, vehicle: v[0], vehicles: v.join(','), platforms: cleaned.join(','), region, tax_rate: regionRate(region, band) });
    router.back();
  }

  return (
    <View style={[s.screen, { paddingTop: insets.top + 8 }]}>
      <View style={s.body}>
        <ModalHeader title="Profile & tax" />

        <Card style={s.card}>
          <View>
            <Text style={s.label}>Name</Text>
            <TextInput style={s.input} value={name} onChangeText={setName} placeholder="Your name" placeholderTextColor={colors.textTertiary} />
          </View>
          <View>
            <Text style={s.label}>Vehicles you use</Text>
            <ChipScroll fadeColor={colors.bgCard}>
              {VEHICLES.map(v => <VehicleChip key={v.key} vehicle={v.key} label={v.label} selected={vehicles.includes(v.key)} onPress={() => toggleVehicle(v.key)} />)}
            </ChipScroll>
          </View>
          <View>
            <Text style={s.label}>Platforms</Text>
            <ChipScroll fadeColor={colors.bgCard}>
              {allOptions.map(p => <Chip key={p} label={p} selected={platforms.includes(p)} onPress={() => toggle(p)} />)}
              <Pressable onPress={addCustom} style={s.addChip}>
                <Feather name="plus" size={14} color={colors.brandDeep} />
                <Text style={s.addChipText}>Add</Text>
              </Pressable>
            </ChipScroll>
          </View>
        </Card>

        <Card style={s.card}>
          <View>
            <Text style={s.label}>Where you live</Text>
            <View style={s.chips}>
              {REGIONS.map(r => <Chip key={r.key} label={r.label} selected={region === r.key} onPress={() => setRegion(r.key)} />)}
            </View>
          </View>
          <View>
            <Text style={s.label}>Income tax band</Text>
            <View style={s.chips}>
              <Chip label="Basic rate" selected={band === 'basic'} onPress={() => setBand('basic')} />
              <Chip label="Higher rate" selected={band === 'higher'} onPress={() => setBand('higher')} />
            </View>
          </View>
          <Text style={s.note}>Estimating take-home at {(regionRate(region, band) * 100).toFixed(0)}% ({regionLabel(region)}).</Text>
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
  card: { gap: spacing.md },
  label: { ...type.label, marginBottom: 8 },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  addChip: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 14, paddingVertical: 10, borderRadius: radius.full, borderWidth: 1.5, borderStyle: 'dashed', borderColor: colors.brandMid, backgroundColor: colors.bg },
  addChipText: { ...type.bodyMedium, fontSize: 14, color: colors.brandDeep },
  note: { ...type.caption, color: colors.textTertiary },
  footer: { paddingHorizontal: spacing.xl, paddingTop: spacing.md },
});
