import React from 'react';
import { View, Text, ViewStyle } from 'react-native';
import { colors, radius, font, spacing, type } from '../theme';

type Props = {
  label: string;
  value: string;
  sub?: string;
  accent?: boolean;
  style?: ViewStyle;
};

export function MetricCard({ label, value, sub, accent, style }: Props) {
  return (
    <View style={[{
      backgroundColor: accent ? colors.brandLight : colors.bgCard,
      borderRadius: radius.lg,
      padding: spacing.lg,
      borderWidth: 1,
      borderColor: accent ? colors.brandMid : colors.border,
      flex: 1,
    }, style]}>
      <Text style={[type.label, { fontSize: 13, marginBottom: 4 }]}>
        {label}
      </Text>
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
