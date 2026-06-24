import React from 'react';
import { BlurView } from 'expo-blur';
import { Platform, Pressable, StyleSheet, useColorScheme, View, type PressableProps, type StyleProp, type ViewStyle } from 'react-native';
import { colors } from '../theme';
import { Icon } from './Icon';

type Props = {
  onPress: PressableProps['onPress'];
  style?: StyleProp<ViewStyle>;
  size?: number;
  hitSlop?: PressableProps['hitSlop'];
};

export function SettingsGlassButton({ onPress, style, size = 44, hitSlop = 12 }: Props) {
  const isDark = useColorScheme() === 'dark';
  const blurTint: React.ComponentProps<typeof BlurView>['tint'] = Platform.OS === 'ios' ? 'systemChromeMaterial' : isDark ? 'dark' : 'light';
  const radius = size / 2;

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel="Open settings"
      hitSlop={hitSlop}
      onPress={onPress}
      style={({ pressed }) => [
        s.outer,
        { width: size, height: size, borderRadius: radius },
        isDark && s.outerDark,
        pressed && s.pressed,
        style,
      ]}
    >
      <View style={[s.clip, { borderRadius: radius }, isDark && s.clipDark]}>
        <BlurView intensity={82} tint={blurTint} style={StyleSheet.absoluteFill} />
        <View style={[s.tint, isDark && s.tintDark]} />
        <View style={s.highlight} />
        <Icon name="settings" size={21} color={isDark ? colors.textPrimary : colors.textSecondary} />
      </View>
    </Pressable>
  );
}

const s = StyleSheet.create({
  outer: {
    alignItems: 'center',
    justifyContent: 'center',
    boxShadow: '0 12px 22px rgba(21,33,29,0.12), 0 3px 8px rgba(21,33,29,0.08)',
  },
  outerDark: {
    boxShadow: '0 14px 24px rgba(0,0,0,0.34), 0 3px 8px rgba(0,0,0,0.28)',
  },
  pressed: { opacity: 0.82, transform: [{ scale: 0.96 }] },
  clip: {
    width: '100%',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.68)',
  },
  clipDark: {
    borderColor: 'rgba(127,214,197,0.2)',
  },
  tint: {
    position: 'absolute',
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    backgroundColor: 'rgba(255,255,255,0.42)',
  },
  tintDark: {
    backgroundColor: 'rgba(18,28,25,0.38)',
  },
  highlight: {
    position: 'absolute',
    top: 4,
    left: 8,
    right: 8,
    height: 14,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.46)',
  },
});
