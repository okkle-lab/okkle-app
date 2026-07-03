import analytics from '@react-native-firebase/analytics';
import crashlytics from '@react-native-firebase/crashlytics';

// Firebase Analytics/Crashlytics are native modules — no-op safely if the
// native module isn't present (e.g. still running in Expo Go rather than a
// dev-client/EAS build) so the rest of the app never crashes on this.
function safe<T extends (...args: any[]) => any>(fn: T): T {
  return ((...args: Parameters<T>) => {
    try { return fn(...args); } catch { /* native module unavailable */ }
  }) as T;
}

export const trackScreen = safe((name: string) => {
  analytics().logScreenView({ screen_name: name, screen_class: name });
});

export const trackEvent = safe((name: string, params?: Record<string, any>) => {
  analytics().logEvent(name, params);
});

export const setUserId = safe((id: string | null) => {
  analytics().setUserId(id);
  crashlytics().setUserId(id ?? '');
});

export const recordError = safe((error: Error, context?: string) => {
  if (context) crashlytics().log(context);
  crashlytics().recordError(error);
});

export const logBreadcrumb = safe((message: string) => {
  crashlytics().log(message);
});
