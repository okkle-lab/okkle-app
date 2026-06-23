import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import Constants from 'expo-constants';
import { colors, spacing, type } from '../src/theme';
import { Card } from '../src/components';

export default function SettingsAbout() {
  const router = useRouter();
  const version = Constants.expoConfig?.version ?? 'dev';
  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <View style={s.header}>
        <Pressable onPress={() => router.back()} hitSlop={12}><Text style={s.close}>Done</Text></Pressable>
        <Text style={s.heading}>About Okkle</Text>
        <View style={{ width: 50 }} />
      </View>

      <Card style={{ gap: spacing.md }}>
        <Text style={s.aboutText}>Okkle keeps a record of your delivery mileage and earnings so you (or your accountant) have what you need at tax time.</Text>
        <Text style={s.aboutText}>Mileage deductions use HMRC's approved simplified rates: 45p/mile for cars and vans (25p after 10,000 miles in a tax year), 24p for motorbikes and 20p for bicycles. These rates are the same across the whole UK.</Text>
        <Text style={s.aboutText}>All your data is stored only on this phone — nothing is sent to a server. Okkle is a record-keeping tool and does not provide tax advice or file your return.</Text>
      </Card>

      <Text style={s.version}>Version {version}</Text>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.heading, fontSize: 18 },
  close: { ...type.bodyMedium, color: colors.textSecondary },
  aboutText: { ...type.caption, color: colors.textSecondary, lineHeight: 20 },
  version: { ...type.small, textAlign: 'center', marginTop: spacing.xl },
});
