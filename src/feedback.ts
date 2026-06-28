import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as MailComposer from 'expo-mail-composer';
import { Platform, Linking } from 'react-native';

// Where feedback and bug reports are sent.
export const FEEDBACK_EMAIL = 'admin@okklelab.com';

// Minimal, non-sensitive diagnostics — explicitly NOT financial data, receipts,
// location history or tax records.
export function collectDiagnostics(screen: string): string {
  const version = Constants.expoConfig?.version ?? 'dev';
  return [
    `— Diagnostics (no personal/financial data) —`,
    `App version: ${version}`,
    `Platform: ${Platform.OS} ${Platform.Version}`,
    `Device: ${Device.modelName ?? 'unknown'} · ${Device.osName ?? Platform.OS} ${Device.osVersion ?? ''}`,
    `Screen: ${screen}`,
    `Time: ${new Date().toISOString()}`,
  ].join('\n');
}

export type FeedbackInput = {
  mode: 'problem' | 'suggestion';
  category?: string;
  description: string;
  contact?: string;
  screen: string;
  includeDiagnostics: boolean;
  screenshotUri?: string | null;
};

// Compose an email to the support inbox (with the user in control of sending).
// Returns 'sent' | 'cancelled' | 'unavailable'.
export async function sendFeedback(input: FeedbackInput): Promise<'sent' | 'cancelled' | 'unavailable'> {
  const subjectTag = input.mode === 'problem' ? 'Problem' : 'Suggestion';
  const subject = `[Okkle ${subjectTag}]${input.category ? ` ${input.category}` : ''}`;

  const bodyParts = [
    input.description.trim(),
    '',
    input.contact ? `Reply to: ${input.contact}` : '',
    input.includeDiagnostics ? `\n${collectDiagnostics(input.screen)}` : '',
  ].filter(Boolean);
  const body = bodyParts.join('\n');

  if (await MailComposer.isAvailableAsync()) {
    const res = await MailComposer.composeAsync({
      recipients: [FEEDBACK_EMAIL],
      subject,
      body,
      attachments: input.screenshotUri ? [input.screenshotUri] : undefined,
    });
    return res.status === 'sent' ? 'sent' : 'cancelled';
  }

  // Fallback: mailto (no attachment support).
  const url = `mailto:${FEEDBACK_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  const can = await Linking.canOpenURL(url);
  if (!can) return 'unavailable';
  await Linking.openURL(url);
  return 'sent';
}
