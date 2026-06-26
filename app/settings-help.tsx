import { useRouter } from 'expo-router';
import { SettingsMenuPage, type SettingsMenuItem } from '../src/components/SettingsMenuPage';
import { kvSet } from '../src/db';

export default function HelpSettings() {
  const router = useRouter();
  const items: SettingsMenuItem[] = [
    { icon: 'alert-triangle', tone: 'amber', title: 'Report a problem', sub: 'Send diagnostics with context', onPress: () => router.push({ pathname: '/feedback', params: { mode: 'problem', screen: 'Settings' } }) },
    { icon: 'message-circle', tone: 'violet', title: 'Suggest an improvement', sub: 'Share a product idea', onPress: () => router.push({ pathname: '/feedback', params: { mode: 'suggestion', screen: 'Settings' } }) },
    { icon: 'compass', tone: 'mint', title: 'Replay app tour', sub: 'Show onboarding coach marks again', onPress: () => {
      kvSet('coach_seen', '');
      // Close the Settings modals so Home is revealed; it re-checks on focus and
      // shows the tour. (replace() alone left the Settings sheet on top.)
      try { (router as any).dismissAll?.(); } catch { /* older router */ }
      router.navigate('/(tabs)');
    } },
    { icon: 'info', tone: 'neutral', title: 'About Okkle', sub: 'Version and app notes', onPress: () => router.push('/settings-about') },
  ];
  return <SettingsMenuPage title="Help & feedback" subtitle="Support, app information and ways to tell us what should improve." items={items} onBack={() => router.back()} />;
}
