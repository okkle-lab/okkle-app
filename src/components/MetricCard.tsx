import React from 'react';
import { View, Text, ViewStyle } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { colors, radius, font, spacing, type } from '../theme';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

type Props = {
  label: string;
  value: string;
  sub?: string;
  accent?: boolean;
  icon?: FeatherName;
  style?: ViewStyle;
};

export function MetricCard({ label, value, sub, accent, icon, style }: Props) {
  return (
    <View style={[{
      backgroundColor: accent ? colors.brandLight : colors.bgCard,
      borderRadius: radius.lg,
      padding: spacing.lg,
      borderWidth: 1,
      borderColor: accent ? colors.brandMid : colors.border,
      flex: 1,
    }, style]}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 4 }}>
        {icon ? <Feather name={icon} size={14} color={accent ? colors.brandDeep : colors.textTertiary} /> : null}
        <Text style={[type.label, { fontSize: 13 }]}>
          {label}
        </Text>
      </View>
      <Text style={[type.metricValue, accent && { color: colors.brandDeep }]}>
        {value}
      </Text>
      {sub ? (
        <Text style={[type.small, { fontSize: 12, color: accent ? colors.brand : colors.textTertiary, marginTop: 3 }]}>
          {sub}
        </Text>
      ) : null}
    </View>
  );
}
