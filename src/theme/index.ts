export const colors = {
  brand: '#1FB89A',
  brandDeep: '#0E8E78',
  brandLight: '#E2F6F1',
  brandMid: '#7FD6C5',

  bg: '#FBF9F6',
  bgSoft: '#F1EFEA',
  bgCard: '#FFFFFF',

  textPrimary: '#22302C',
  textSecondary: '#6B756F',
  textTertiary: '#A2ABA5',

  border: '#E8E6E0',
  borderStrong: '#D3D1C9',

  green: '#2FA36B',
  greenLight: '#E5F4EC',
  amber: '#E0961F',
  amberLight: '#FBEFD6',
  red: '#E2604A',
  redLight: '#FBEAE5',

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

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
};
