import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, Linking, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, IconBadge, GradientCard } from '../src/components';

// Paste the iCloud share link of the Okkle "Log earnings" shortcut here once it's
// built (see docs/ios-shortcut-earnings.md). Until then the Add button explains
// it's coming. Example: 'https://www.icloud.com/shortcuts/xxxxxxxx'
const SHORTCUT_ICLOUD_URL = '';

export default function EarningsShortcut() {
  const router = useRouter();

  function addShortcut() {
    if (!SHORTCUT_ICLOUD_URL) {
      Alert.alert('Almost ready', 'The one-tap shortcut link will be added in an upcoming update. For now you can set it up manually from the guide.');
      return;
    }
    Linking.openURL(SHORTCUT_ICLOUD_URL).catch(() => Alert.alert("Couldn't open", 'Open the Shortcuts app and try again.'));
  }

  function openShortcutsApp() {
    Linking.openURL('shortcuts://').catch(() => Alert.alert("Couldn't open Shortcuts", 'Open the Shortcuts app from your home screen.'));
  }

  function testIt() {
    Linking.openURL('okkle://log-earnings?amount=84.50&period=week&platform=Uber%20Eats')
      .catch(() => Alert.alert("Couldn't open", 'Try again from the home screen.'));
  }

  const Step = ({ n, title, children }: { n: number; title: string; children: React.ReactNode }) => (
    <View style={s.step}>
      <View style={s.stepNum}><Text style={s.stepNumText}>{n}</Text></View>
      <View style={{ flex: 1 }}>
        <Text style={s.stepTitle}>{title}</Text>
        {children}
      </View>
    </View>
  );

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <View style={s.header}>
        <Pressable onPress={() => router.back()} hitSlop={12} style={s.back}>
          <Feather name="chevron-left" size={26} color={colors.textPrimary} />
        </Pressable>
        <Text style={s.title}>Auto-log earnings</Text>
        <View style={{ width: 26 }} />
      </View>

      {/* What it does */}
      <GradientCard colors={[colors.brand, colors.brandDeep, colors.dark]} radius={radius.xl} style={s.hero}>
        <Feather name="camera" size={22} color="#fff" />
        <Text style={s.heroTitle}>Screenshot → earnings</Text>
        <Text style={s.heroSub}>
          Take a screenshot of your pay screen in any delivery app and Okkle pops up with the
          amount ready to save. The screenshot is read on your phone — nothing is uploaded.
        </Text>
      </GradientCard>

      <Text style={s.sectionLabel}>One-time setup (~1 minute)</Text>
      <Card style={{ gap: spacing.lg }}>
        <Step n={1} title="Add the Okkle shortcut">
          <Text style={s.stepBody}>Tap below, then tap “Add Shortcut”. This installs the little helper that reads the figure.</Text>
          <Pressable onPress={addShortcut} style={({ pressed }) => [pressed && { opacity: 0.9 }]}>
            <GradientCard colors={[colors.brand, colors.brandDeep]} radius={radius.md} style={s.cta}>
              <Feather name="download" size={16} color="#fff" />
              <Text style={s.ctaText}>Add Okkle shortcut</Text>
            </GradientCard>
          </Pressable>
        </Step>

        <Step n={2} title="Make it run on screenshots">
          <Text style={s.stepBody}>
            In the Shortcuts app: <Text style={s.b}>Automation</Text> → <Text style={s.b}>＋</Text> → <Text style={s.b}>Screenshot Taken</Text> →
            choose <Text style={s.b}>Run “Okkle Earnings”</Text>. (Turn off “Ask Before Running” if you want it instant.)
          </Text>
          <Pressable onPress={openShortcutsApp} style={s.linkBtn}>
            <Feather name="external-link" size={15} color={colors.brandDeep} />
            <Text style={s.linkText}>Open Shortcuts app</Text>
          </Pressable>
        </Step>

        <Step n={3} title="That's it">
          <Text style={s.stepBody}>Screenshot any earnings screen — Okkle opens with the amount filled in. You always check it and tap Save; nothing is logged automatically.</Text>
        </Step>
      </Card>

      {/* Test */}
      <Text style={s.sectionLabel}>Try the confirm screen</Text>
      <Pressable onPress={testIt} style={({ pressed }) => [pressed && { opacity: 0.9 }]}>
        <Card style={s.testRow}>
          <IconBadge icon="play" tone="green" size={36} />
          <View style={{ flex: 1 }}>
            <Text style={s.testTitle}>Preview with a sample</Text>
            <Text style={s.testSub}>Opens the confirm card with £84.50 so you can see how it looks.</Text>
          </View>
          <Feather name="chevron-right" size={20} color={colors.textTertiary} />
        </Card>
      </Pressable>

      <View style={s.note}>
        <Feather name="lock" size={14} color={colors.textTertiary} />
        <Text style={s.noteText}>
          Private by design: the screenshot is read on your device with Apple's text recognition —
          no servers, no AI, nothing leaves your phone. You confirm every figure before it's saved.
        </Text>
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.lg },
  back: { padding: 2 },
  title: { ...type.screenTitle },

  hero: { padding: spacing.xl, gap: 6 },
  heroTitle: { color: '#fff', fontSize: 22, fontWeight: font.bold, letterSpacing: -0.4, marginTop: 4 },
  heroSub: { color: 'rgba(255,255,255,0.88)', fontSize: 14, lineHeight: 20 },

  sectionLabel: { ...type.label, color: colors.textSecondary, fontWeight: font.semibold, marginTop: spacing.xl, marginBottom: spacing.sm },

  step: { flexDirection: 'row', gap: 12 },
  stepNum: { width: 26, height: 26, borderRadius: 13, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  stepNumText: { color: '#fff', fontSize: 14, fontWeight: font.bold },
  stepTitle: { ...type.bodyMedium, fontSize: 15, marginBottom: 4 },
  stepBody: { ...type.caption, lineHeight: 19 },
  b: { fontWeight: font.semibold, color: colors.textPrimary },

  cta: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingVertical: 14, marginTop: spacing.sm },
  ctaText: { color: '#fff', fontSize: 15, fontWeight: font.bold },
  linkBtn: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: spacing.sm },
  linkText: { ...type.bodyMedium, fontSize: 14, color: colors.brandDeep },

  testRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  testTitle: { ...type.bodyMedium, fontSize: 15 },
  testSub: { ...type.caption, marginTop: 2, lineHeight: 18 },

  note: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md, flexDirection: 'row', alignItems: 'flex-start', gap: 8 },
  noteText: { ...type.small, lineHeight: 18, flex: 1 },
});
