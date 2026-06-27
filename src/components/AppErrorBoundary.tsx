import React from 'react';
import { View, Text, Pressable, StyleSheet } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../theme';

// Catches any render/runtime error in the tree below it and shows a friendly
// fallback instead of a blank white screen. Release (App Store / TestFlight)
// builds have no red error overlay, so without this a single JS error anywhere
// in the app would just render white with no way to recover.
type Props = { children: React.ReactNode };
type State = { error: Error | null };

export class AppErrorBoundary extends React.Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error) {
    // Surfaces in device logs; no remote logging (Okkle has no backend).
    console.error('Okkle crashed:', error);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <View style={s.screen}>
        <View style={s.icon}><Feather name="alert-triangle" size={26} color={colors.amberDark} /></View>
        <Text style={s.title}>Something went wrong</Text>
        <Text style={s.body}>Okkle hit an unexpected error. Your data is safe on your phone — tap below to try again, or reopen the app.</Text>
        <Pressable onPress={() => this.setState({ error: null })} style={({ pressed }) => [s.btn, pressed && { opacity: 0.85 }]}>
          <Text style={s.btnText}>Try again</Text>
        </Pressable>
      </View>
    );
  }
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg, alignItems: 'center', justifyContent: 'center', padding: spacing.xl, gap: spacing.md },
  icon: { width: 56, height: 56, borderRadius: 28, backgroundColor: colors.amberLight, alignItems: 'center', justifyContent: 'center' },
  title: { ...type.screenTitle, fontSize: 20, textAlign: 'center' },
  body: { ...type.body, color: colors.textSecondary, textAlign: 'center', lineHeight: 21, maxWidth: 320 },
  btn: { marginTop: spacing.sm, paddingHorizontal: spacing.xl, height: 50, borderRadius: radius.lg, backgroundColor: colors.brandDeep, alignItems: 'center', justifyContent: 'center' },
  btnText: { color: '#fff', fontSize: 15, fontWeight: font.semibold },
});
