import React from 'react';
import { View, Text, Pressable, StyleSheet, ScrollView } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../theme';
import { kvSet } from '../db';
import { logError } from '../diagnostics';

// Catches any render/runtime error in the tree below it and shows a friendly
// fallback instead of a blank white screen. Release (App Store / TestFlight)
// builds have no red error overlay, so without this a single JS error anywhere
// in the app would just render white with no way to recover.
//
// It also captures the error message + stack on screen (and persists it), so a
// crash on a real device can be screenshotted and diagnosed — release builds
// otherwise hide the cause entirely.
type Props = { children: React.ReactNode };
type State = { error: Error | null; info: string };

export class AppErrorBoundary extends React.Component<Props, State> {
  state: State = { error: null, info: '' };

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { error };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    const detail = [
      String(error?.message ?? error),
      (error?.stack ?? '').split('\n').slice(0, 6).join('\n'),
      (errorInfo?.componentStack ?? '').split('\n').slice(0, 8).join('\n'),
    ].filter(Boolean).join('\n');
    this.setState({ info: detail });
    // Persist so it can be retrieved later (Settings → Diagnostics) even after "Try again".
    try { kvSet('last_crash', `${new Date().toISOString()}\n${detail}`); } catch { /* ignore */ }
    logError('render-crash', error);
    console.error('Okkle crashed:', error);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <View style={s.screen}>
        <View style={s.icon}><Feather name="alert-triangle" size={26} color={colors.amberDark} /></View>
        <Text style={s.title}>Something went wrong</Text>
        <Text style={s.body}>Okkle hit an unexpected error. Your data is safe on your phone — tap below to try again, or reopen the app.</Text>
        {!!this.state.info && (
          <ScrollView style={s.detailBox} contentContainerStyle={{ padding: spacing.md }}>
            <Text style={s.detailText} selectable>{this.state.info}</Text>
          </ScrollView>
        )}
        <Pressable onPress={() => this.setState({ error: null, info: '' })} style={({ pressed }) => [s.btn, pressed && { opacity: 0.85 }]}>
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
  detailBox: { alignSelf: 'stretch', maxHeight: 220, backgroundColor: colors.bgSoft, borderRadius: radius.md, borderWidth: 1, borderColor: colors.border },
  detailText: { fontSize: 11, lineHeight: 16, color: colors.textSecondary, fontFamily: 'Courier' },
  btn: { marginTop: spacing.sm, paddingHorizontal: spacing.xl, height: 50, borderRadius: radius.lg, backgroundColor: colors.brandDeep, alignItems: 'center', justifyContent: 'center' },
  btnText: { color: '#fff', fontSize: 15, fontWeight: font.semibold },
});
