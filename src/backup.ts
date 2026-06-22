import * as FileSystem from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import * as DocumentPicker from 'expo-document-picker';
import { dumpData, restoreData, type BackupPayload } from './db';

// Save the whole database to a JSON file and open the share sheet so the user
// can store it in their own iCloud Drive / Files / email. Nothing goes to us.
export async function backupNow(): Promise<void> {
  const data = dumpData();
  const date = new Date().toISOString().slice(0, 10);
  const dir = (FileSystem as any).cacheDirectory ?? (FileSystem as any).documentDirectory;
  const uri = `${dir}Okkle_Backup_${date}.json`;
  await (FileSystem as any).writeAsStringAsync(uri, JSON.stringify(data, null, 2));
  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(uri, { mimeType: 'application/json', dialogTitle: 'Save your Okkle backup' });
  }
}

export type RestoreResult = { trips: number; records: number };

// Let the user pick a backup file and restore it (replaces current data).
export async function restoreFromFile(): Promise<RestoreResult | null> {
  const res = await DocumentPicker.getDocumentAsync({ type: ['application/json', 'public.json', '*/*'] });
  if (res.canceled || !res.assets?.[0]) return null;
  const text = await (FileSystem as any).readAsStringAsync(res.assets[0].uri);
  const payload = JSON.parse(text) as BackupPayload;
  restoreData(payload);
  return { trips: payload.trips?.length ?? 0, records: payload.records?.length ?? 0 };
}
