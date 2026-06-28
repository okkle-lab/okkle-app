import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import * as DocumentPicker from 'expo-document-picker';
import { dumpData, restoreData, kvSet, type BackupPayload } from './db';

export type BackupResult = { fileName: string; uri: string; shared: boolean };

function backupFileName(date = new Date()): string {
  const stamp = date.toISOString().replace(/[:.]/g, '-').slice(0, 19);
  return `Okkle_Backup_${stamp}.json`;
}

// Save the whole database to a JSON file and open the share sheet so the user
// can store it in their own iCloud Drive / Files / email. Nothing goes to us.
export async function backupNow(): Promise<BackupResult> {
  const data = dumpData();
  const fileName = backupFileName();
  const file = new File(Paths.cache, fileName);
  file.create({ overwrite: true, intermediates: true });
  file.write(JSON.stringify(data, null, 2));
  kvSet('backup_made', 1); // unlocks the "Safe keeper" medal

  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(file.uri, {
      mimeType: 'application/json',
      UTI: 'public.json',
      dialogTitle: 'Save your Okkle backup',
    });
    return { fileName, uri: file.uri, shared: true };
  }

  return { fileName, uri: file.uri, shared: false };
}

export type RestoreResult = { trips: number; records: number };

// Let the user pick a backup file and restore it (replaces current data).
export async function restoreFromFile(): Promise<RestoreResult | null> {
  const res = await DocumentPicker.getDocumentAsync({
    type: ['application/json', 'text/json', '*/*'],
    copyToCacheDirectory: true,
  });
  if (res.canceled || !res.assets?.[0]) return null;
  const text = await new File(res.assets[0].uri).text();
  const payload = JSON.parse(text) as BackupPayload;
  restoreData(payload);
  return { trips: payload.trips?.length ?? 0, records: payload.records?.length ?? 0 };
}
