import React, { useState } from 'react';
import { Platform, View, Text, TextInput, ScrollView, StyleSheet, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, Chip, SectionHeader, PrimaryButton, VehicleChip } from '../src/components';
import { VEHICLES, PLATFORMS, REGIONS, regionRate, regionLabel } from '../src/db/tax';
import { getUser, saveUser } from '../src/db';

export default function SettingsAccount() {
  const router = useRouter();
  const u = getUser();
  const [name, setName] = useState(u?.name ?? '');
  const [vehicle, setVehicle] = useState(u?.vehicle ?? 'car');
  const [platforms, setPlatforms] = useState<string[]>(u?.platforms?.split(',').filter(Boolean) ?? ['Uber Eats']);
  const [region, setRegion] = useState(u?.region ?? 'ruk');
  const [band, setBand] = useState<'basic' | 'higher'>((u?.tax_rate ?? 0.2) >= 0.4 ? 'higher' : 'basic');

  const toggle = (p: string) => setPlatforms(prev => (prev.includes(p) ? prev.filter(x => x !== p) : [...prev, p]));

  function save() {
    saveUser({ name, vehicle, platforms: platforms.join(','), region, tax_rate: regionRate(region, band) });
    router.back();
  }

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <View style={s.header}>
        <Pressable onPress={() => router.back()} hitSlop={12}><Text style={s.close}>Cancel</Text></Pressable>
        <Text style={s.heading}>Profile & tax</Text>
        <View style={{ width: 50 }} />
      </View>

      <SectionHeader title="Your details" />
      <Card style={{ gap: spacing.lg }}>
        <View>
          <Text style={s.fieldLabel}>Name</Text>
          <TextInput style={s.input} value={name} onChangeText={setName} placeholder="Your name" placeholderTextColor={colors.textTertiary} />
        </View>
        <View>
          <Text style={s.fieldLabel}>Default vehicle</Text>
          <View style={s.chips}>
            {VEHICLES.map(v => <VehicleChip key={v.key} vehicle={v.key} label={v.label} selected={vehicle === v.key} onPress={() => setVehicle(v.key)} />)}
          </View>
        </View>
        <View>
          <Text style={s.fieldLabel}>Platforms</Text>
          <View style={s.chips}>
            {PLATFORMS.map(p => <Chip key={p} label={p} selected={platforms.includes(p)} onPress={() => toggle(p)} />)}
          </View>
        </View>
      </Card>

      <SectionHeader title="Tax region" />
      <Card style={{ gap: spacing.lg }}>
        <View>
          <Text style={s.fieldLabel}>Where you live</Text>
          <View style={s.chips}>
            {REGIONS.map(r => <Chip key={r.key} label={r.label} selected={region === r.key} onPress={() => setRegion(r.key)} />)}
          </View>
        </View>
        <View>
          <Text style={s.fieldLabel}>Income tax band</Text>
          <View style={s.chips}>
            <Chip label="Basic rate" selected={band === 'basic'} onPress={() => setBand('basic')} />
            <Chip label="Higher rate" selected={band === 'higher'} onPress={() => setBand('higher')} />
          </View>
        </View>
        <Text style={s.note}>Estimating take-home at {(regionRate(region, band) * 100).toFixed(0)}% ({regionLabel(region)}).</Text>
      </Card>

      <PrimaryButton label="Save changes" onPress={save} style={{ marginTop: spacing.xl }} />
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: Platform.OS === 'ios' ? 'transparent' : colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.heading, fontSize: 18 },
  close: { ...type.bodyMedium, color: colors.textSecondary },
  fieldLabel: { ...type.label, marginBottom: 8 },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  note: { ...type.caption, color: colors.textTertiary },
});
