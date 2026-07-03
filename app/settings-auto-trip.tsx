import React from 'react';
import { View, Text, TextInput, Pressable, StyleSheet, Switch, Alert, Linking, ScrollView } from 'react-native';
import Feather from '@expo/vector-icons/Feather';
import * as Location from 'expo-location';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, GradientCard, ModalHeader } from '../src/components';
import { enableAutoTrip, disableAutoTrip, isAutoTripEnabled } from '../src/autoTrip';
import { getExcludedPlaces, addExcludedPlace, removeExcludedPlace, type ExcludedPlace } from '../src/db';

export default function AutoTripSettings() {
  const [on, setOn] = React.useState(isAutoTripEnabled());
  const [busy, setBusy] = React.useState(false);
  const [places, setPlaces] = React.useState<ExcludedPlace[]>(getExcludedPlaces());
  const [label, setLabel] = React.useState('');
  const [address, setAddress] = React.useState('');
  const [geocoding, setGeocoding] = React.useState(false);

  async function addByAddress() {
    const cleanLabel = label.trim();
    const cleanAddress = address.trim();
    if (!cleanLabel || !cleanAddress || geocoding) return;
    setGeocoding(true);
    try {
      const results = await Location.geocodeAsync(cleanAddress);
      const hit = results[0];
      if (!hit) {
        Alert.alert("Couldn't find that address", 'Try a more specific address.');
        return;
      }
      addExcludedPlace({ label: cleanLabel, lat: hit.latitude, lng: hit.longitude });
      setPlaces(getExcludedPlaces());
      setLabel('');
      setAddress('');
    } catch {
      Alert.alert("Couldn't find that address", 'Try a more specific address.');
    } finally {
      setGeocoding(false);
    }
  }

  async function addByCurrentLocation() {
    const cleanLabel = label.trim();
    if (!cleanLabel) return;
    try {
      const { status } = await Location.getForegroundPermissionsAsync();
      if (status !== 'granted') {
        const req = await Location.requestForegroundPermissionsAsync();
        if (req.status !== 'granted') return;
      }
      const pos = await Location.getCurrentPositionAsync({});
      addExcludedPlace({ label: cleanLabel, lat: pos.coords.latitude, lng: pos.coords.longitude });
      setPlaces(getExcludedPlaces());
      setLabel('');
      setAddress('');
    } catch {
      Alert.alert("Couldn't get your location", 'Try again in a moment.');
    }
  }

  function remove(index: number) {
    removeExcludedPlace(index);
    setPlaces(getExcludedPlaces());
  }

  async function toggle(next: boolean) {
    if (busy) return;
    setBusy(true);
    if (next) {
      const res = await enableAutoTrip();
      if (res.ok) {
        setOn(true);
      } else if (res.reason === 'background') {
        Alert.alert(
          'Allow “Always”',
          'To nudge you while Okkle is closed, iOS needs location set to “Always”. Open Settings to change it.',
          [{ text: 'Not now' }, { text: 'Open Settings', onPress: () => Linking.openSettings() }],
        );
      } else if (res.reason === 'foreground') {
        Alert.alert('Location needed', 'Allow location access to detect when you start driving.');
      } else {
        Alert.alert('Couldn’t enable', 'Something went wrong turning this on. Please try again.');
      }
    } else {
      await disableAutoTrip();
      setOn(false);
    }
    setBusy(false);
  }

  return (
    <View style={s.screen}>
      <ScrollView style={s.content} contentContainerStyle={s.contentInner} keyboardShouldPersistTaps="handled">
        <ModalHeader title="Trip nudges" />

        <GradientCard colors={[colors.brand, colors.brandDeep, colors.dark]} radius={radius.xl} style={s.hero}>
          <Text style={s.heroTitle}>Never forget to track a trip</Text>
          <Text style={s.heroSub}>
            Nudges you to start tracking when you drive, and to save once you’ve stopped and parked for a while. You decide each time — nothing is recorded automatically.
          </Text>
        </GradientCard>

        <Card style={s.toggleCard}>
          <View style={{ flex: 1 }}>
            <Text style={s.toggleTitle}>Trip nudges</Text>
            <Text style={s.toggleDesc}>
              “Track this trip?” when you drive, “finished?” once you stop. Ignore on a personal drive.
            </Text>
            <Text style={s.toggleState}>{on ? 'On' : 'Off'}</Text>
          </View>
          <Switch value={on} onValueChange={toggle} disabled={busy} trackColor={{ true: colors.brand }} />
        </Card>

        <Card style={s.noteCard}>
          <Feather name="alert-circle" size={18} color={colors.amberDark} />
          <Text style={s.noteText}>
            Not perfect — a bus or train might trigger it. Nothing logs until you confirm.
          </Text>
        </Card>

        <Text style={s.sectionTitle}>Places to leave out</Text>
        <Card style={s.placesCard}>
          {places.length > 0 && (
            <View style={s.placesList}>
              {places.map((p, i) => (
                <View key={`${p.label}-${i}`} style={s.placeRow}>
                  <Text style={s.placeLabel}>{p.label}</Text>
                  <Pressable onPress={() => remove(i)} hitSlop={10}>
                    <Feather name="x" size={16} color={colors.textTertiary} />
                  </Pressable>
                </View>
              ))}
            </View>
          )}
          <TextInput
            style={s.input}
            value={label}
            onChangeText={setLabel}
            placeholder="Label, e.g. Home"
            placeholderTextColor={colors.textTertiary}
          />
          <TextInput
            style={s.input}
            value={address}
            onChangeText={setAddress}
            placeholder="Address"
            placeholderTextColor={colors.textTertiary}
          />
          <View style={s.placeActions}>
            <Pressable onPress={addByAddress} disabled={!label.trim() || !address.trim() || geocoding}>
              <Text style={[s.addAction, (!label.trim() || !address.trim() || geocoding) && s.addActionDisabled]}>Add</Text>
            </Pressable>
            <Pressable onPress={addByCurrentLocation} disabled={!label.trim()}>
              <Text style={[s.addAction, !label.trim() && s.addActionDisabled]}>Use current location</Text>
            </Pressable>
          </View>
        </Card>
        <Text style={s.placesFooter}>
          Kept out of “where to go” suggestions.
        </Text>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { flex: 1 },
  contentInner: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  hero: { padding: spacing.lg, gap: 6 },
  heroTitle: { color: '#fff', fontSize: 20, fontWeight: font.bold, letterSpacing: -0.2, marginTop: 4 },
  heroSub: { color: 'rgba(255,255,255,0.88)', fontSize: 14, lineHeight: 20 },
  toggleCard: { flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: spacing.lg },
  toggleTitle: { ...type.bodyMedium, fontSize: 16 },
  toggleDesc: { ...type.caption, marginTop: 4, lineHeight: 18 },
  toggleState: { ...type.caption, marginTop: 6, fontWeight: font.semibold, color: colors.brandDeep },
  noteCard: { flexDirection: 'row', gap: 10, marginTop: spacing.lg, backgroundColor: colors.amberLight },
  noteText: { ...type.caption, color: colors.amberDark, lineHeight: 18, flex: 1 },
  sectionTitle: { ...type.bodyMedium, fontSize: 16, marginTop: spacing.xl, marginBottom: spacing.sm },
  placesCard: { gap: spacing.sm },
  placesList: { gap: spacing.xs, marginBottom: spacing.xs },
  placeRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 6 },
  placeLabel: { ...type.bodyMedium, fontSize: 15 },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 16, color: colors.textPrimary, backgroundColor: colors.bg },
  placeActions: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 4 },
  addAction: { ...type.bodyMedium, fontSize: 14, color: colors.brandDeep },
  addActionDisabled: { color: colors.textTertiary },
  placesFooter: { ...type.caption, marginTop: spacing.sm, lineHeight: 18 },
});
