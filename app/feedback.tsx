import { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, StyleSheet, Pressable, Alert, Image,
  KeyboardAvoidingView, Platform, Switch,
} from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Feather from '@expo/vector-icons/Feather';
import * as ImagePicker from 'expo-image-picker';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Chip, PrimaryButton, Card, SectionHeader, ModalHeader } from '../src/components';
import { FEEDBACK_EMAIL, sendFeedback } from '../src/feedback';

const PROBLEM_CATEGORIES = [
  'App not working', 'GPS / trip tracking', 'Earnings or expenses',
  'Tax estimate', 'Export or backup', 'Subscription', 'Feature request', 'Other',
];

export default function FeedbackScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ mode?: string; screen?: string; category?: string }>();
  const mode: 'problem' | 'suggestion' = params.mode === 'suggestion' ? 'suggestion' : 'problem';
  const screen = params.screen ?? 'Settings';

  const [category, setCategory] = useState(params.category ?? (mode === 'problem' ? 'App not working' : ''));
  const [description, setDescription] = useState('');
  const [contact, setContact] = useState('');
  const [shot, setShot] = useState<string | null>(null);
  const [includeDiag, setIncludeDiag] = useState(true);
  const [busy, setBusy] = useState(false);

  async function pickShot() {
    const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!perm.granted) { Alert.alert('Permission needed', 'Allow photo access to attach a screenshot.'); return; }
    const res = await ImagePicker.launchImageLibraryAsync({ quality: 0.6, mediaTypes: ['images'] });
    if (!res.canceled && res.assets[0]) setShot(res.assets[0].uri);
  }

  async function submit() {
    if (!description.trim()) { Alert.alert('Add a description', 'Tell us a little about what happened.'); return; }
    setBusy(true);
    try {
      const result = await sendFeedback({ mode, category: category || undefined, description, contact: contact.trim() || undefined, screen, includeDiagnostics: includeDiag, screenshotUri: shot });
      setBusy(false);
      if (result === 'unavailable') {
        Alert.alert('No mail set up', `Add an email account to your phone, or email us directly at ${FEEDBACK_EMAIL}.`);
        return;
      }
      if (result === 'cancelled') {
        return;
      }
      router.back();
      setTimeout(() => Alert.alert('Thank you', 'Your message is on its way. We read every one.'), 250);
    } catch {
      setBusy(false);
      Alert.alert('Couldn’t send', `Please try again, or email ${FEEDBACK_EMAIL} directly.`);
    }
  }

  const title = mode === 'problem' ? 'Report a problem' : 'Suggest an improvement';
  const placeholder = mode === 'problem'
    ? 'What happened? The more detail, the faster we can fix it.'
    : 'What would make Okkle more useful? What’s missing?';

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
        <ModalHeader title={title} />
        <Text style={s.sub}>
          {mode === 'problem'
            ? 'Sorry something went wrong. A few details help us fix it fast.'
            : 'We build Okkle around what couriers actually need. Tell us.'}
        </Text>

        {mode === 'problem' && (
          <>
            <SectionHeader title="What's it about?" />
            <View style={s.chips}>
              {PROBLEM_CATEGORIES.map(c => (
                <Chip key={c} label={c} selected={category === c} onPress={() => setCategory(c)} />
              ))}
            </View>
          </>
        )}

        <SectionHeader title="Tell us more" />
        <TextInput
          style={s.input}
          placeholder={placeholder}
          placeholderTextColor={colors.textTertiary}
          value={description}
          onChangeText={setDescription}
          multiline
          autoFocus
        />

        <SectionHeader title="Screenshot (optional)" />
        {shot ? (
          <View style={s.shotWrap}>
            <Image source={{ uri: shot }} style={s.shot} />
            <Pressable onPress={() => setShot(null)} style={s.shotRemove}><Text style={s.shotRemoveText}>Remove</Text></Pressable>
          </View>
        ) : (
          <Pressable onPress={pickShot} style={s.attachBtn}>
            <Feather name="image" size={16} color={colors.textPrimary} />
            <Text style={s.attachText}>Attach a screenshot</Text>
          </Pressable>
        )}

        <SectionHeader title="Your email (optional)" />
        <TextInput
          style={[s.input, { minHeight: 0 }]}
          placeholder="So we can reply"
          placeholderTextColor={colors.textTertiary}
          value={contact}
          onChangeText={setContact}
          keyboardType="email-address"
          autoCapitalize="none"
        />

        <Card style={{ marginTop: spacing.md, gap: 4 }}>
          <View style={s.diagRow}>
            <View style={{ flex: 1 }}>
              <Text style={s.diagTitle}>Include basic diagnostics</Text>
              <Text style={s.diagSub}>App version, phone, OS & current screen. Never your earnings, receipts, location or tax records.</Text>
            </View>
            <Switch value={includeDiag} onValueChange={setIncludeDiag} trackColor={{ true: colors.brand }} />
          </View>
        </Card>
      </ScrollView>

      {/* Send stays pinned so it's never cut off, whatever the screen height. */}
      <View style={[s.footer, { paddingBottom: Math.max(insets.bottom, 12) }]}>
        <PrimaryButton label={busy ? 'Opening mail…' : 'Send'} onPress={submit} disabled={busy} />
      </View>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 56, paddingBottom: spacing.md },
  footer: { paddingHorizontal: spacing.xl, paddingTop: spacing.md, borderTopWidth: 1, borderTopColor: colors.border, backgroundColor: colors.bg },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  heading: { ...type.screenTitle },
  close: { ...type.label, color: colors.textSecondary },
  sub: { ...type.body, color: colors.textSecondary, lineHeight: 21, marginTop: 4, marginBottom: spacing.md },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  input: {
    borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    padding: spacing.md, fontSize: 16, color: colors.textPrimary, backgroundColor: colors.bgCard,
    minHeight: 84, textAlignVertical: 'top',
  },
  attachBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, paddingVertical: 14, backgroundColor: colors.bgCard },
  attachText: { ...type.bodyMedium, fontSize: 15 },
  shotWrap: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  shot: { width: 70, height: 70, borderRadius: radius.md, borderWidth: 1, borderColor: colors.border },
  shotRemove: { paddingVertical: 8, paddingHorizontal: 14, borderRadius: radius.full, backgroundColor: colors.redLight },
  shotRemoveText: { ...type.caption, color: colors.red, fontWeight: font.semibold },
  diagRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  diagTitle: { ...type.bodyMedium, fontSize: 15 },
  diagSub: { ...type.caption, marginTop: 2, lineHeight: 18 },
  privacy: { ...type.small, lineHeight: 17, color: colors.textTertiary },
});
