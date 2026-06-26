import React from 'react';
import { StyleSheet, type StyleProp, type ViewStyle } from 'react-native';
import { radius as radii } from '../theme';
import { GlassPanel } from './GlassPanel';

type Props = {
  children: React.ReactNode;
  radius?: number;
  style?: StyleProp<ViewStyle>;
  contentStyle?: StyleProp<ViewStyle>;
};

export function AiGlowPanel({ children, radius = radii.xl, style, contentStyle }: Props) {
  return (
    <GlassPanel
      tone="neutral"
      radius={radius}
      isInteractive
      style={[s.panel, style]}
      clipStyle={s.panelClip}
      contentStyle={contentStyle}
    >
      {children}
    </GlassPanel>
  );
}

const s = StyleSheet.create({
  panel: {
    boxShadow: '0 16px 38px rgba(27,38,33,0.07), 0 4px 14px rgba(82,155,255,0.05)',
  },
  panelClip: {
    borderColor: 'rgba(255,255,255,0.70)',
    backgroundColor: 'transparent',
  },
});
