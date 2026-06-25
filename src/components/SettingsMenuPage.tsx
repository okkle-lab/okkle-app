import React from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { colors, spacing, radius, type } from '../theme';
import { IconBadge } from './IconBadge';
import { ModalHeader } from './ModalHeader';

type Tone = React.ComponentProps<typeof IconBadge>['tone'];
type FeatherName = React.ComponentProps<typeof Feather>['name'];

export type SettingsMenuItem = {
  icon: FeatherName;
  tone: Tone;
  title: string;
  sub: string;
  onPress: () => void;
};

export function SettingsMenuPage({ title, subtitle, items, onBack }: {
  title: string;
  subtitle: string;
  items: SettingsMenuItem[];
  onBack: () => void;
}) {
  return (
    <View style={s.screen}>
      <View style={s.content}>
        <ModalHeader title={title} onBack={onBack} />
        <Text style={s.subtitle} numberOfLines={2}>{subtitle}</Text>

        <View style={s.group}>
          {items.map((item, index) => (
            <Pressable key={item.title} onPress={item.onPress} style={({ pressed }) => [s.row, index < items.length - 1 && s.rowBorder, pressed && s.rowPressed]}>
              <IconBadge icon={item.icon} tone={item.tone} size={36} />
              <View style={s.rowText}>
                <Text style={s.rowTitle} numberOfLines={1}>{item.title}</Text>
                <Text style={s.rowSub} numberOfLines={1}>{item.sub}</Text>
              </View>
              <Feather name="chevron-right" size={20} color={colors.textTertiary} />
            </Pressable>
          ))}
        </View>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { flex: 1, padding: spacing.xl, paddingTop: 60, gap: spacing.lg },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  back: { width: 34, height: 34, alignItems: 'flex-start', justifyContent: 'center' },
  title: { ...type.screenTitle, flex: 1, textAlign: 'center' },
  subtitle: { ...type.body, color: colors.textSecondary, lineHeight: 22, marginTop: -spacing.sm },
  group: { overflow: 'hidden', borderRadius: radius.xl, backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.border },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 68, paddingHorizontal: spacing.lg, paddingVertical: spacing.sm },
  rowText: { flex: 1, minWidth: 0 },
  rowPressed: { backgroundColor: colors.bgSoft },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  rowTitle: { ...type.bodyMedium, fontSize: 16 },
  rowSub: { ...type.caption, marginTop: 2 },
});
