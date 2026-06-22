import React from 'react';
import { Text } from 'react-native';
import { colors, font } from '../theme';

export function SectionHeader({ title }: { title: string }) {
  return (
    <Text style={{ fontSize: 13, fontWeight: font.semibold, color: colors.textSecondary, letterSpacing: 0.3, marginBottom: 10, marginTop: 4 }}>
      {title}
    </Text>
  );
}
