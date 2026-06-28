import React from 'react';
import { View, Text, ViewStyle } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { colors, radius, spacing, type, tabular } from '../theme';

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
      minHeight: 96,
      justifyContent: 'flex-start',
    }, style]}>
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 10 }}>
        {icon ? (
          <View style={{
            width: 28, height: 28, borderRadius: 14,
            backgroundColor: accent ? 'rgba(255,255,255,0.5)' : colors.brandLight,
            alignItems: 'center', justifyContent: 'center',
          }}>
            <Feather name={icon} size={15} color={colors.brandDeep} />
          </View>
        ) : null}
        <Text style={[type.label, { fontSize: 13 }]} numberOfLines={1}>
          {label}
        </Text>
      </View>
      <Text
        style={[type.metricValue, tabular, accent && { color: colors.brandDeep }]}
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.7}
      >
        {value}
      </Text>
      {sub ? (
        <Text
          style={[type.small, tabular, { fontSize: 12, color: accent ? colors.brand : colors.textTertiary, marginTop: 4 }]}
          numberOfLines={1}
        >
          {sub}
        </Text>
      ) : null}
    </View>
  );
}
