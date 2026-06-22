import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, Modal } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { getAchievements, getStreak, type Achievement, type AchievementTier } from '../src/db';

const TIER_COLOR: { [k in AchievementTier]: string } = {
  bronze: '#B87333',
  silver: '#9AA3AE',
  gold: '#E0961F',
  special: colors.brand,
};
const TIER_LIGHT: { [k in AchievementTier]: string } = {
  bronze: '#F3E7DC',
  silver: '#ECEEF1',
  gold: '#FBEFD6',
  special: colors.brandLight,
};

export default function MedalsScreen() {
  const router = useRouter();
  const all = getAchievements();
  const streak = getStreak();
  const earned = all.filter(a => a.unlocked).length;
  const [selected, setSelected] = React.useState<Achievement | null>(null);

  // Group by category, preserving first-seen order.
  const categories: string[] = [];
  const byCat: { [c: string]: Achievement[] } = {};
  for (const a of all) {
    if (!byCat[a.category]) { byCat[a.category] = []; categories.push(a.category); }
    byCat[a.category].push(a);
  }

  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content}>
        <View style={s.header}>
          <Pressable onPress={() => router.back()} hitSlop={12} style={s.back}>
            <Feather name="chevron-left" size={26} color={colors.textPrimary} />
          </Pressable>
          <Text style={s.title}>Medals</Text>
          <View style={{ width: 26 }} />
        </View>

        {/* Summary banner */}
        <View style={s.banner}>
          <View style={s.bannerRing}>
            <Text style={s.bannerNum}>{earned}</Text>
            <Text style={s.bannerOf}>of {all.length}</Text>
          </View>
          <View style={{ flex: 1 }}>
            <Text style={s.bannerTitle}>{earned === all.length ? 'Every medal earned! 🏆' : 'Keep collecting'}</Text>
            <Text style={s.bannerSub}>
              {streak > 0 ? `🔥 ${streak}-day streak going` : 'Track a trip today to start a streak'}
            </Text>
          </View>
        </View>

        {categories.map(cat => (
          <View key={cat} style={{ marginTop: spacing.xl }}>
            <Text style={s.catTitle}>{cat}</Text>
            <View style={s.grid}>
              {byCat[cat].map(a => (
                <Pressable key={a.key} style={s.cell} onPress={() => setSelected(a)}>
                  <View style={[
                    s.medal,
                    a.unlocked
                      ? { backgroundColor: TIER_LIGHT[a.tier], borderColor: TIER_COLOR[a.tier] }
                      : { backgroundColor: colors.bgSoft, borderColor: colors.border },
                  ]}>
                    <Feather name={a.icon as any} size={26} color={a.unlocked ? TIER_COLOR[a.tier] : colors.textTertiary} />
                    {!a.unlocked && (
                      <View style={s.lockDot}><Feather name="lock" size={10} color={colors.textTertiary} /></View>
                    )}
                  </View>
                  <Text style={[s.medalLabel, !a.unlocked && { color: colors.textTertiary }]} numberOfLines={2}>{a.label}</Text>
                  {!a.unlocked && a.progress > 0 && a.progress < 1 && (
                    <Text style={s.medalPct}>{Math.round(a.progress * 100)}%</Text>
                  )}
                </Pressable>
              ))}
            </View>
          </View>
        ))}
        <Text style={s.footnote}>Tap a medal for details. New medals unlock as you track trips, log earnings and keep your streak alive.</Text>
      </ScrollView>

      {/* Medal detail */}
      <Modal visible={selected !== null} transparent animationType="fade" onRequestClose={() => setSelected(null)}>
        <Pressable style={s.modalBg} onPress={() => setSelected(null)}>
          <View style={s.modalCard}>
            <View style={[
              s.modalMedal,
              selected?.unlocked
                ? { backgroundColor: TIER_COLOR[selected.tier] }
                : { backgroundColor: colors.bgSoft, borderWidth: 2, borderColor: colors.border },
            ]}>
              <Feather name={(selected?.icon ?? 'award') as any} size={40} color={selected?.unlocked ? '#fff' : colors.textTertiary} />
            </View>
            <Text style={s.modalTier}>{selected?.unlocked ? `${selected?.tier} medal` : 'Locked'}</Text>
            <Text style={s.modalTitle}>{selected?.label}</Text>
            <Text style={s.modalDesc}>{selected?.desc}</Text>
            {!selected?.unlocked && selected?.progress !== undefined && (
              <View style={s.modalTrack}>
                <View style={[s.modalFill, { width: `${Math.round((selected?.progress ?? 0) * 100)}%` }]} />
              </View>
            )}
            <Pressable onPress={() => setSelected(null)} style={s.modalBtn}><Text style={s.modalBtnText}>Done</Text></Pressable>
          </View>
        </Pressable>
      </Modal>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.xl },
  back: { padding: 2 },
  title: { ...type.screenTitle },

  banner: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg, backgroundColor: colors.bgCard, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.border, padding: spacing.lg },
  bannerRing: { width: 72, height: 72, borderRadius: 36, borderWidth: 4, borderColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  bannerNum: { ...tabular, fontSize: 24, fontWeight: font.bold, color: colors.brandDeep, lineHeight: 26 },
  bannerOf: { ...type.small, fontSize: 11 },
  bannerTitle: { ...type.bodyMedium, fontSize: 16 },
  bannerSub: { ...type.caption, marginTop: 2 },

  catTitle: { ...type.label, fontWeight: font.semibold, color: colors.textSecondary, marginBottom: spacing.md, letterSpacing: 0.3 },
  grid: { flexDirection: 'row', flexWrap: 'wrap' },
  cell: { width: '25%', alignItems: 'center', marginBottom: spacing.lg, paddingHorizontal: 2 },
  medal: { width: 60, height: 60, borderRadius: 30, borderWidth: 2, alignItems: 'center', justifyContent: 'center', marginBottom: 6 },
  lockDot: { position: 'absolute', bottom: -2, right: -2, width: 18, height: 18, borderRadius: 9, backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.border, alignItems: 'center', justifyContent: 'center' },
  medalLabel: { fontSize: 11, color: colors.textSecondary, textAlign: 'center', lineHeight: 14, fontWeight: font.medium },
  medalPct: { ...tabular, ...type.small, fontSize: 10, color: colors.brandDeep, marginTop: 1 },
  footnote: { ...type.small, lineHeight: 18, marginTop: spacing.xl, textAlign: 'center' },

  modalBg: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  modalCard: { backgroundColor: colors.bgCard, borderRadius: radius.xl, padding: spacing.xl, alignItems: 'center', width: '100%', maxWidth: 340 },
  modalMedal: { width: 88, height: 88, borderRadius: 44, alignItems: 'center', justifyContent: 'center', marginBottom: spacing.md },
  modalTier: { ...type.label, color: colors.textTertiary, textTransform: 'capitalize', fontSize: 12, marginBottom: 2 },
  modalTitle: { ...type.screenTitle, fontSize: 22, marginBottom: spacing.sm, textAlign: 'center' },
  modalDesc: { ...type.body, color: colors.textSecondary, textAlign: 'center', marginBottom: spacing.lg },
  modalTrack: { height: 6, width: '100%', borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden', marginBottom: spacing.lg },
  modalFill: { height: '100%', backgroundColor: colors.brand, borderRadius: radius.full },
  modalBtn: { backgroundColor: colors.brand, borderRadius: radius.lg, paddingVertical: 14, alignSelf: 'stretch', alignItems: 'center' },
  modalBtnText: { color: '#fff', fontSize: 16, fontWeight: font.semibold },
});
