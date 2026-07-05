import React from 'react';
import { View, Text, TextInput, Pressable, StyleSheet, Switch, Alert, Linking, ScrollView, KeyboardAvoidingView, Platform } from 'react-native';
import Feather from '@expo/vector-icons/Feather';
import * as Location from 'expo-location';
import { useFocusEffect } from 'expo-router';
import MapView, { Marker, type LatLng } from 'react-native-maps';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, ModalHeader, KeyboardDoneAccessory } from '../src/components';
import { enableAutoTrip, disableAutoTrip, isAutoTripEnabled } from '../src/autoTrip';
import { getExcludedPlaces, addExcludedPlace, removeExcludedPlace, updateExcludedPlace, getWorkingDays, setWorkingDays, type ExcludedPlace } from '../src/db';
import { trackEvent } from '../src/analytics';
import { getDiagLog, clearDiagLog } from '../src/diagnostics';

// Monday-first, matching how couriers think about a work week; values are the
// JS Date.getDay() index each chip represents (0=Sun..6=Sat).
const DAY_CHIPS: { label: string; day: number }[] = [
  { label: 'M', day: 1 }, { label: 'T', day: 2 }, { label: 'W', day: 3 },
  { label: 'T', day: 4 }, { label: 'F', day: 5 }, { label: 'S', day: 6 }, { label: 'S', day: 0 },
];

export default function AutoTripSettings() {
  const [on, setOn] = React.useState(isAutoTripEnabled());
  const [busy, setBusy] = React.useState(false);
  const [workingDays, setWorkingDaysState] = React.useState<number[]>(getWorkingDays());
  const [places, setPlaces] = React.useState<ExcludedPlace[]>(getExcludedPlaces());
  const [label, setLabel] = React.useState('');
  const [address, setAddress] = React.useState('');
  const [geocoding, setGeocoding] = React.useState(false);
  const [activityLog, setActivityLog] = React.useState(() => getDiagLog().filter(e => e.ctx === 'auto-trip'));

  // Real background-location behavior only happens on a physical device, out
  // of our control between visits to this screen — so re-read fresh every
  // time it regains focus (e.g. coming back after an actual drive) rather
  // than only once on mount.
  useFocusEffect(
    React.useCallback(() => {
      setActivityLog(getDiagLog().filter(e => e.ctx === 'auto-trip'));
    }, []),
  );

  function clearActivityLog() {
    clearDiagLog();
    setActivityLog([]);
  }

  function toggleDay(day: number) {
    const next = workingDays.includes(day) ? workingDays.filter(d => d !== day) : [...workingDays, day];
    setWorkingDaysState(next);
    setWorkingDays(next);
    trackEvent('working_days_set', { days: next.join(','), count: next.length });
  }

  // Reverse-geocodes the coordinate we actually resolved (not just echoing
  // back what the user typed) — so the saved place shows exactly where it
  // was matched, and it's obvious if geocoding got it wrong.
  async function resolveAddress(lat: number, lng: number): Promise<string | undefined> {
    try {
      const places = await Location.reverseGeocodeAsync({ latitude: lat, longitude: lng });
      const p = places[0];
      if (!p) return undefined;
      const line1 = [p.streetNumber, p.street].filter(Boolean).join(' ');
      const line2 = [p.city ?? p.district ?? p.subregion, p.postalCode].filter(Boolean).join(' ');
      return [line1, line2].filter(Boolean).join(', ') || undefined;
    } catch {
      return undefined;
    }
  }

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
      const resolved = await resolveAddress(hit.latitude, hit.longitude);
      addExcludedPlace({ label: cleanLabel, lat: hit.latitude, lng: hit.longitude, address: resolved ?? cleanAddress });
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
      const resolved = await resolveAddress(pos.coords.latitude, pos.coords.longitude);
      addExcludedPlace({ label: cleanLabel, lat: pos.coords.latitude, lng: pos.coords.longitude, address: resolved });
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

  // Geocoding can land a little off — dragging the pin corrects it directly
  // rather than fighting with a re-typed address.
  async function movePin(index: number, coordinate: LatLng) {
    const { latitude: lat, longitude: lng } = coordinate;
    updateExcludedPlace(index, { lat, lng });
    setPlaces(getExcludedPlaces());
    const resolved = await resolveAddress(lat, lng);
    if (resolved) {
      updateExcludedPlace(index, { address: resolved });
      setPlaces(getExcludedPlaces());
    }
  }

  async function toggle(next: boolean) {
    if (busy) return;
    setBusy(true);
    if (next) {
      const res = await enableAutoTrip();
      if (res.ok) {
        setOn(true);
        trackEvent('auto_trip_enabled', { source: 'settings' });
      } else if (res.reason === 'background') {
        Alert.alert(
          'Allow “Always”',
          'To track a trip with Okkle closed, iOS needs Location set to “Always”. Tap Open Settings, then Location → Always.',
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
      trackEvent('auto_trip_disabled', { source: 'settings' });
    }
    setBusy(false);
  }

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={s.content} contentContainerStyle={s.contentInner} keyboardShouldPersistTaps="handled">
        <ModalHeader title="Automatic tracking" />

        <Card style={s.toggleCard}>
          <View style={{ flex: 1 }}>
            <Text style={s.toggleTitle}>Automatic tracking</Text>
            <Text style={s.toggleDesc}>
              Logs GPS miles as soon as you start driving. Turn off if you'd rather track manually.
            </Text>
            <Text style={s.toggleState}>{on ? 'On' : 'Off'}</Text>
          </View>
          <Switch value={on} onValueChange={toggle} disabled={busy} trackColor={{ true: colors.brand }} />
        </Card>

        <Card style={s.noteCard}>
          <Feather name="alert-circle" size={18} color={colors.amberDark} />
          <Text style={s.noteText}>
            Not perfect — a bus or train might trigger it. You can always delete a trip afterwards.
          </Text>
        </Card>

        <View style={s.activityHeaderRow}>
          <Text style={s.sectionTitle}>Recent activity</Text>
          {activityLog.length > 0 && (
            <Pressable onPress={clearActivityLog} hitSlop={10}>
              <Text style={s.clearLink}>Clear</Text>
            </Pressable>
          )}
        </View>
        <Text style={s.placesFooter}>
          What the background watcher has actually seen — useful for checking it's working after a real drive.
        </Text>
        {activityLog.length === 0 ? (
          <Card style={s.activityEmpty}>
            <Text style={s.activityEmptyText}>
              Nothing logged yet — this fills in once the app has run in the background during a real drive.
            </Text>
          </Card>
        ) : (
          <Card style={s.activityCard}>
            {activityLog.slice(0, 20).map((e, i) => (
              <View key={i} style={[s.activityRow, i > 0 && s.activityRowBorder]}>
                <Text style={s.activityTime}>{new Date(e.t).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}</Text>
                <Text style={s.activityDetail}>{e.detail}</Text>
              </View>
            ))}
          </Card>
        )}

        <Text style={s.sectionTitle}>Working days</Text>
        <Text style={s.placesFooter}>
          Only auto-track on these days. Leave none selected to track every day.
        </Text>
        <View style={s.dayRow}>
          {DAY_CHIPS.map((c, i) => {
            const selected = workingDays.includes(c.day);
            return (
              <Pressable key={i} onPress={() => toggleDay(c.day)} style={[s.dayChip, selected && s.dayChipSelected]}>
                <Text style={[s.dayChipText, selected && s.dayChipTextSelected]}>{c.label}</Text>
              </Pressable>
            );
          })}
        </View>

        <Text style={s.sectionTitle}>Places to leave out</Text>
        <Text style={s.placesFooter}>
          Kept out of “where to go” suggestions.
        </Text>

        {places.length > 0 && (
          <View style={s.placesList}>
            {places.map((p, i) => (
              <Card key={`${p.label}-${i}`} style={s.placeCard}>
                <View style={s.placeMap}>
                  <MapView
                    style={StyleSheet.absoluteFill}
                    initialRegion={{ latitude: p.lat, longitude: p.lng, latitudeDelta: 0.006, longitudeDelta: 0.006 }}
                    rotateEnabled={false}
                    pitchEnabled={false}
                    showsCompass={false}
                  >
                    <Marker
                      coordinate={{ latitude: p.lat, longitude: p.lng }}
                      draggable
                      onDragEnd={e => movePin(i, e.nativeEvent.coordinate)}
                      anchor={{ x: 0.5, y: 0.5 }}
                    >
                      <View style={s.pinTouchTarget}>
                        <View style={s.pinDot} />
                      </View>
                    </Marker>
                  </MapView>
                  <Text style={s.placeMapHint}>Drag the pin if it's off</Text>
                </View>
                <View style={s.placeInfo}>
                  <View style={{ flex: 1 }}>
                    <Text style={s.placeLabel}>{p.label}</Text>
                    {!!p.address && <Text style={s.placeAddress}>{p.address}</Text>}
                  </View>
                  <Pressable onPress={() => remove(i)} hitSlop={10}>
                    <Feather name="x" size={16} color={colors.textTertiary} />
                  </Pressable>
                </View>
              </Card>
            ))}
          </View>
        )}

        <Text style={s.addTitle}>Add a place</Text>
        <Card style={s.placesCard}>
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
            <Pressable
              onPress={addByCurrentLocation}
              disabled={!label.trim()}
              style={({ pressed }) => [s.actionBtn, s.actionBtnSecondary, !label.trim() && s.actionBtnDisabled, pressed && !!label.trim() && s.actionBtnPressed]}
            >
              <Feather name="crosshair" size={16} color={label.trim() ? colors.brandDeep : colors.textTertiary} />
              <Text style={[s.actionBtnSecondaryText, !label.trim() && s.actionBtnTextDisabled]}>Use current location</Text>
            </Pressable>
            <Pressable
              onPress={addByAddress}
              disabled={!label.trim() || !address.trim() || geocoding}
              style={({ pressed }) => [
                s.actionBtn, s.actionBtnPrimary,
                (!label.trim() || !address.trim() || geocoding) && s.actionBtnPrimaryDisabled,
                pressed && !!label.trim() && !!address.trim() && !geocoding && s.actionBtnPressed,
              ]}
            >
              <Text style={[s.actionBtnPrimaryText, (!label.trim() || !address.trim() || geocoding) && s.actionBtnPrimaryTextDisabled]}>Add</Text>
            </Pressable>
          </View>
        </Card>
      </ScrollView>
      <KeyboardDoneAccessory />
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { flex: 1 },
  contentInner: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  toggleCard: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  toggleTitle: { ...type.bodyMedium, fontSize: 16 },
  toggleDesc: { ...type.caption, marginTop: 4, lineHeight: 18 },
  toggleState: { ...type.caption, marginTop: 6, fontWeight: font.semibold, color: colors.brandDeep },
  noteCard: { flexDirection: 'row', gap: 10, marginTop: spacing.lg, backgroundColor: colors.amberLight },
  noteText: { ...type.caption, color: colors.amberDark, lineHeight: 18, flex: 1 },
  sectionTitle: { ...type.bodyMedium, fontSize: 16, marginTop: spacing.xl, marginBottom: 2 },
  placesFooter: { ...type.caption, lineHeight: 18 },
  activityHeaderRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginTop: spacing.xl },
  clearLink: { ...type.bodyMedium, fontSize: 14, color: colors.brandDeep },
  activityEmpty: { marginTop: spacing.md, alignItems: 'center', paddingVertical: spacing.lg },
  activityEmptyText: { ...type.caption, textAlign: 'center', lineHeight: 18 },
  activityCard: { padding: 0, overflow: 'hidden', marginTop: spacing.md },
  activityRow: { padding: spacing.md, gap: 3 },
  activityRowBorder: { borderTopWidth: 1, borderTopColor: colors.border },
  activityTime: { ...type.caption, fontWeight: font.semibold, color: colors.brandDeep },
  activityDetail: { ...type.caption, lineHeight: 17 },
  dayRow: { flexDirection: 'row', gap: 8, marginTop: spacing.md },
  dayChip: {
    width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center',
    backgroundColor: colors.bg, borderWidth: 1.5, borderColor: colors.border,
  },
  dayChipSelected: { backgroundColor: colors.brandDeep, borderColor: colors.brandDeep },
  dayChipText: { ...type.bodyMedium, fontSize: 14, color: colors.textSecondary },
  dayChipTextSelected: { color: '#fff' },
  placesList: { gap: spacing.sm, marginTop: spacing.md },
  placeCard: { padding: 0, overflow: 'hidden' },
  placeMap: { height: 280, width: '100%' },
  placeMapHint: {
    position: 'absolute', top: 8, left: 8,
    ...type.caption, fontSize: 11, color: '#fff',
    backgroundColor: 'rgba(0,0,0,0.55)', paddingHorizontal: 8, paddingVertical: 4, borderRadius: radius.sm,
    overflow: 'hidden',
  },
  pinTouchTarget: { width: 56, height: 56, alignItems: 'center', justifyContent: 'center' },
  pinDot: {
    width: 30, height: 30, borderRadius: 15,
    backgroundColor: colors.brandDeep, borderWidth: 3, borderColor: '#fff',
  },
  placeInfo: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', padding: spacing.md },
  placeLabel: { ...type.bodyMedium, fontSize: 15 },
  placeAddress: { ...type.caption, marginTop: 2 },
  addTitle: { ...type.caption, fontWeight: font.semibold, marginTop: spacing.lg, marginBottom: spacing.xs },
  placesCard: { gap: spacing.sm },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 16, color: colors.textPrimary, backgroundColor: colors.bg },
  placeActions: { flexDirection: 'row', alignItems: 'stretch', gap: spacing.sm, marginTop: 4 },
  actionBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    minHeight: 48, paddingHorizontal: spacing.lg, borderRadius: radius.full,
  },
  actionBtnPressed: { opacity: 0.75 },
  actionBtnSecondary: { flex: 1, borderWidth: 1.5, borderColor: colors.brandMid, backgroundColor: colors.brandLight },
  actionBtnSecondaryText: { ...type.bodyMedium, fontSize: 15, color: colors.brandDeep },
  actionBtnDisabled: { borderColor: colors.border, backgroundColor: colors.bg },
  actionBtnTextDisabled: { color: colors.textTertiary },
  actionBtnPrimary: { backgroundColor: colors.brandDeep, paddingHorizontal: spacing.xl },
  actionBtnPrimaryText: { ...type.bodyMedium, fontSize: 15, color: '#fff', fontWeight: font.semibold },
  actionBtnPrimaryDisabled: { backgroundColor: colors.border },
  actionBtnPrimaryTextDisabled: { color: colors.textTertiary },
});
