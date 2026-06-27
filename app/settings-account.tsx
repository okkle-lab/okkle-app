import { useState } from 'react';
import { View, Text, TextInput, StyleSheet, Pressable, Alert, ScrollView } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, spacing, radius, type } from '../src/theme';
import { Card, Chip, PrimaryButton, VehicleChip, ModalHeader, ChipScroll } from '../src/components';
import { VEHICLES, PLATFORMS } from '../src/db/tax';
import { getUser, saveUser, kvGet, kvSet } from '../src/db';

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
  // Identity for the Accountant Pack — optional, stored on-device only.
  const [utr, setUtr] = useState(kvGet('utr') ?? '');
  const [ni, setNi] = useState(kvGet('ni_number') ?? '');
  const [address, setAddress] = useState(kvGet('address') ?? '');
  const [business, setBusiness] = useState(kvGet('business_desc') ?? '');

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
    saveUser({ name, vehicle: v[0], vehicles: v.join(','), platforms: cleaned.join(',') });
    kvSet('utr', utr.trim());
    kvSet('ni_number', ni.trim());
    kvSet('address', address.trim());
    kvSet('business_desc', business.trim());
    router.back();
  }

  return (
    <View style={[s.screen, { paddingTop: insets.top + 8 }]}>
      <ScrollView style={s.body} contentContainerStyle={s.bodyContent} keyboardShouldPersistTaps="handled">
        <ModalHeader title="Profile" />

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

        <Text style={s.sectionHead}>Details for your accountant pack</Text>
        <Card style={s.card}>
          <View>
            <Text style={s.label}>Unique Taxpayer Reference (UTR)</Text>
            <TextInput style={s.input} value={utr} onChangeText={setUtr} placeholder="10-digit HMRC reference" placeholderTextColor={colors.textTertiary} keyboardType="number-pad" />
          </View>
          <View>
            <Text style={s.label}>National Insurance number</Text>
            <TextInput style={s.input} value={ni} onChangeText={setNi} placeholder="QQ 12 34 56 C" placeholderTextColor={colors.textTertiary} autoCapitalize="characters" />
          </View>
          <View>
            <Text style={s.label}>Address</Text>
            <TextInput style={[s.input, s.inputMultiline]} value={address} onChangeText={setAddress} placeholder="Home or business address" placeholderTextColor={colors.textTertiary} multiline textAlignVertical="top" />
          </View>
          <View>
            <Text style={s.label}>Nature of business</Text>
            <TextInput style={s.input} value={business} onChangeText={setBusiness} placeholder="Delivery courier" placeholderTextColor={colors.textTertiary} />
          </View>
          <View style={s.privacyRow}>
            <Feather name="lock" size={14} color={colors.brandDeep} />
            <Text style={s.privacyText}>Optional. Stored only on this phone and added to your exported Accountant Pack. Okkle never uploads it and does not file to HMRC.</Text>
          </View>
        </Card>
      </ScrollView>

      <View style={[s.footer, { paddingBottom: Math.max(insets.bottom, 12) }]}>
        <PrimaryButton label="Save changes" onPress={save} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  body: { flex: 1 },
  bodyContent: { paddingHorizontal: spacing.xl, paddingBottom: spacing.xl, gap: spacing.md },
  card: { gap: spacing.md },
  sectionHead: { ...type.label, color: colors.textSecondary, marginTop: spacing.sm, marginLeft: 2 },
  label: { ...type.label, marginBottom: 8 },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg },
  inputMultiline: { minHeight: 76, paddingTop: spacing.md },
  privacyRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 8, backgroundColor: colors.brandLight, borderRadius: radius.md, padding: spacing.md },
  privacyText: { ...type.small, color: colors.brandDeep, lineHeight: 17, flex: 1 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  addChip: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 14, paddingVertical: 10, borderRadius: radius.full, borderWidth: 1.5, borderStyle: 'dashed', borderColor: colors.brandMid, backgroundColor: colors.bg },
  addChipText: { ...type.bodyMedium, fontSize: 14, color: colors.brandDeep },
  note: { ...type.caption, color: colors.textTertiary },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: spacing.md, paddingVertical: spacing.sm },
  linkText: { ...type.bodyMedium, fontSize: 15, color: colors.textPrimary, flex: 1 },
  footer: { paddingHorizontal: spacing.xl, paddingTop: spacing.md },
});
