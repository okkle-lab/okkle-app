import { DynamicColorIOS, Platform } from 'react-native';

function adaptive(light: string, dark: string): string {
  if (Platform.OS !== 'ios') return light;
  return DynamicColorIOS({ light, dark }) as unknown as string;
}

export const colors = {
  brand: '#1FB89A',
  brandDeep: '#0E8E78',
  brandLight: adaptive('#E2F6F1', '#123B34'),
  brandMid: '#7FD6C5',

  bg: adaptive('#FFFFFF', '#101816'),
  bgSoft: adaptive('#F4F6F5', '#1A2420'),
  bgCard: adaptive('#FFFFFF', '#17201D'),

  textPrimary: adaptive('#22302C', '#EEF5F1'),
  textSecondary: adaptive('#6B756F', '#B2BDB7'),
  textTertiary: adaptive('#A2ABA5', '#7E8B85'),

  border: adaptive('#E3E8E5', '#2A3631'),
  borderStrong: adaptive('#CBD5D0', '#3A4640'),

  green: '#2FA36B',
  greenLight: adaptive('#E5F4EC', '#173A29'),
  amber: '#E0961F',
  amberLight: adaptive('#FBEFD6', '#3D2B13'),
  amberDark: adaptive('#8A5510', '#F0BD63'),   // readable amber text on amberLight backgrounds
  red: '#E2604A',
  redLight: adaptive('#FBEAE5', '#3F211D'),

  dark: '#15211D',
  darkSoft: '#26332E',
};

export const radius = {
  sm: 10,
  md: 14,
  lg: 18,
  xl: 26,
  full: 999,
};

export const font = {
  regular: '400' as const,
  medium: '500' as const,
  semibold: '600' as const,
  bold: '700' as const,
};

// One shared type scale so sizes stay consistent across every screen.
export const type = {
  screenTitle: { fontSize: 26, fontWeight: font.bold, letterSpacing: -0.5, color: colors.textPrimary },
  hero: { fontSize: 30, fontWeight: font.bold, letterSpacing: -0.6, color: colors.textPrimary },
  heading: { fontSize: 19, fontWeight: font.semibold, letterSpacing: -0.2, color: colors.textPrimary },
  body: { fontSize: 16, fontWeight: font.regular, color: colors.textPrimary },
  bodyMedium: { fontSize: 16, fontWeight: font.medium, color: colors.textPrimary },
  label: { fontSize: 14, fontWeight: font.medium, color: colors.textSecondary },
  caption: { fontSize: 13, fontWeight: font.regular, color: colors.textSecondary },
  small: { fontSize: 12, fontWeight: font.regular, color: colors.textTertiary },
  metricValue: { fontSize: 24, fontWeight: font.bold, letterSpacing: -0.5, color: colors.textPrimary },
} as const;

// Apply to any Text that shows numbers so digits sit in even columns and don't
// jitter between values (tabular/monospaced figures).
export const tabular = { fontVariant: ['tabular-nums' as const] };

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
};
