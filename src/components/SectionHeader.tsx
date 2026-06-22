import React from 'react';
import { Text, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { colors, font } from '../theme';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

export function SectionHeader({ title, icon }: { title: string; icon?: FeatherName }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 10, marginTop: 4 }}>
      {icon ? <Feather name={icon} size={13} color={colors.brand} /> : null}
      <Text style={{ fontSize: 13, fontWeight: font.semibold, color: colors.textSecondary, letterSpacing: 0.3 }}>
        {title}
      </Text>
    </View>
  );
}
