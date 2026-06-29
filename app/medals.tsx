import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, Modal } from 'react-native';
import { useRouter } from 'expo-router';
import Feather from '@expo/vector-icons/Feather';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Medal, Card, SectionHeader, IconBadge, GlassPanel } from '../src/components';
import { getAchievements, getStreak, getPersonalRecords, type Achievement } from '../src/db';

export default function MedalsScreen() {
  const router = useRouter();
  const all = getAchievements();
  const streak = getStreak();
  const records = getPersonalRecords();
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
            <Text style={s.bannerTitle}>{earned === all.length ? 'Every medal earned' : 'Keep collecting'}</Text>
            <Text style={s.bannerSub}>
              {streak > 0 ? `${streak}-day streak going` : 'Track a trip today to start a streak'}
            </Text>
          </View>
        </View>

        {/* Personal bests — your own records, moved here from Home */}
        {records.length > 0 && (
          <View style={{ marginTop: spacing.xl }}>
            <SectionHeader icon="award" title="Personal bests" />
            <Card style={{ padding: spacing.md }}>
              <View style={s.recGrid}>
                {records.map(r => (
                  <View key={r.key} style={s.recCell}>
                    <View style={{ opacity: r.set ? 1 : 0.4 }}><IconBadge icon={r.icon as any} tone={r.tone as any} size={34} /></View>
                    <Text style={[s.recValue, !r.set && { color: colors.textTertiary }]} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.7}>{r.value}</Text>
                    <Text style={s.recLabel} numberOfLines={2}>{r.label}</Text>
                    <Text style={s.recSub} numberOfLines={1}>{r.sub}</Text>
                  </View>
                ))}
              </View>
            </Card>
          </View>
        )}

        {categories.map(cat => (
          <View key={cat} style={{ marginTop: spacing.xl }}>
            <Text style={s.catTitle}>{cat}</Text>
            <View style={s.grid}>
              {byCat[cat].map(a => (
                <Pressable key={a.key} style={s.cell} onPress={() => setSelected(a)}>
                  <Medal icon={a.icon as any} category={a.category} tier={a.tier} unlocked={a.unlocked} size={62} />
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
          <GlassPanel
            tone={selected?.unlocked ? 'amber' : 'neutral'}
            radius={32}
            isInteractive
            style={s.modalCard}
            clipStyle={s.modalCardClip}
            contentStyle={s.modalCardContent}
          >
            {selected && <Medal icon={selected.icon as any} category={selected.category} tier={selected.tier} unlocked={selected.unlocked} size={108} />}
            <Text style={s.modalTier}>{selected?.unlocked ? `${selected?.tier} medal` : 'Locked'}</Text>
            <Text style={s.modalTitle}>{selected?.label}</Text>
            <Text style={s.modalDesc}>{selected?.desc}</Text>
            {!selected?.unlocked && selected?.progress !== undefined && (
              <View style={s.modalTrack}>
                <View style={[s.modalFill, { width: `${Math.round((selected?.progress ?? 0) * 100)}%` }]} />
              </View>
            )}
            <Pressable onPress={() => setSelected(null)} style={s.modalBtn}><Text style={s.modalBtnText}>Done</Text></Pressable>
          </GlassPanel>
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
  recGrid: { flexDirection: 'row', flexWrap: 'wrap' },
  recCell: { width: '33.33%', alignItems: 'center', paddingVertical: spacing.md, paddingHorizontal: 4 },
  recValue: { ...tabular, fontSize: 18, fontWeight: font.bold, color: colors.textPrimary, marginTop: 4, letterSpacing: -0.3 },
  recLabel: { ...type.small, color: colors.textSecondary, fontWeight: font.medium, textAlign: 'center', marginTop: 3, lineHeight: 14 },
  recSub: { ...type.small, fontSize: 10, color: colors.textTertiary, textAlign: 'center', marginTop: 1 },
  medalLabel: { fontSize: 11, color: colors.textSecondary, textAlign: 'center', lineHeight: 14, fontWeight: font.medium, marginTop: 2 },
  medalPct: { ...tabular, ...type.small, fontSize: 10, color: colors.brandDeep, marginTop: 1 },
  footnote: { ...type.small, lineHeight: 18, marginTop: spacing.xl, textAlign: 'center' },

  modalBg: { flex: 1, backgroundColor: 'rgba(15,28,25,0.32)', alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  modalCard: { width: '100%', maxWidth: 340, borderCurve: 'continuous' },
  modalCardClip: { backgroundColor: 'transparent', borderCurve: 'continuous' },
  modalCardContent: { padding: spacing.xl, alignItems: 'center' },
  modalTier: { ...type.label, color: colors.textTertiary, textTransform: 'capitalize', fontSize: 12, marginBottom: 2, marginTop: spacing.sm },
  modalTitle: { ...type.screenTitle, fontSize: 22, marginBottom: spacing.sm, textAlign: 'center' },
  modalDesc: { ...type.body, color: colors.textSecondary, textAlign: 'center', marginBottom: spacing.lg },
  modalTrack: { height: 6, width: '100%', borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden', marginBottom: spacing.lg },
  modalFill: { height: '100%', backgroundColor: colors.brand, borderRadius: radius.full },
  modalBtn: { backgroundColor: colors.brand, borderRadius: radius.lg, paddingVertical: 14, alignSelf: 'stretch', alignItems: 'center' },
  modalBtnText: { color: '#fff', fontSize: 16, fontWeight: font.semibold },
});
