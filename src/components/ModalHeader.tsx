import React from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing } from '../theme';

// One consistent header for every modal/settings layer: a left chevron back
// button, a centred title in one shared font, and a matched spacer so the title
// stays centred. Replaces the mix of "Cancel"/"Done" text buttons and varied
// title styles that had crept in.
export function ModalHeader({ title, onBack, right }: { title: string; onBack?: () => void; right?: React.ReactNode }) {
  const router = useRouter();
  return (
    <View style={s.header}>
      <Pressable onPress={onBack ?? (() => router.back())} hitSlop={12} style={s.side}>
        <Feather name="chevron-left" size={26} color={colors.textPrimary} />
      </Pressable>
      <Text style={s.title} numberOfLines={1}>{title}</Text>
      <View style={s.side}>{right}</View>
    </View>
  );
}

const HEADER_SIDE = 40;

const s = StyleSheet.create({
  header: { flexDirection: 'row', alignItems: 'center', marginBottom: spacing.lg },
  side: { width: HEADER_SIDE, height: HEADER_SIDE, alignItems: 'flex-start', justifyContent: 'center' },
  title: { flex: 1, textAlign: 'center', fontSize: 18, fontWeight: font.bold, letterSpacing: -0.3, color: colors.textPrimary },
});
