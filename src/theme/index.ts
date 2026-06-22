export const colors = {
  brand: '#E06A4E',
  brandDeep: '#C44E32',
  brandLight: '#FBE9E2',
  brandMid: '#EFA890',

  bg: '#FBF7F2',
  bgSoft: '#F4EDE4',
  bgCard: '#FFFFFF',

  textPrimary: '#2A2320',
  textSecondary: '#7A6E64',
  textTertiary: '#A89C90',

  border: '#EBE2D6',
  borderStrong: '#D9CCBC',

  green: '#3F9B6D',
  greenLight: '#E7F3EC',
  amber: '#D98A29',
  amberLight: '#FBEFD9',
  red: '#D2553F',
  redLight: '#FBEAE5',

  dark: '#2A211D',
  darkSoft: '#3A2F2A',
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

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
};
