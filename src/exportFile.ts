import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import { Share } from 'react-native';
import { taxYearLabel } from './db/tax';

// Consistent, human-readable export filenames:
//   Okkle_<What>_TaxYear-2025-26_2026-06-23.<ext>
// i.e. app name · what it is · which tax year · the date it was exported.
export function exportFilename(what: string, ext: string): string {
  const taxYear = taxYearLabel().replace('/', '-');           // "2025/26" -> "2025-26"
  const exportedOn = new Date().toISOString().slice(0, 10);    // "2026-06-23"
  return `Okkle_${what}_TaxYear-${taxYear}_${exportedOn}.${ext}`;
}

const UTI: { [ext: string]: string } = {
  csv: 'public.comma-separated-values-text',
  txt: 'public.plain-text',
  pdf: 'com.adobe.pdf',
};

const MIME: { [ext: string]: string } = {
  csv: 'text/csv',
  txt: 'text/plain',
  pdf: 'application/pdf',
};

// Write text content to a clearly-named file and open the share sheet.
export async function shareTextExport(what: string, ext: 'csv' | 'txt', content: string): Promise<void> {
  const name = exportFilename(what, ext);
  try {
    const file = new File(Paths.cache, name);
    file.create({ overwrite: true, intermediates: true });
    file.write(content);
    if (await Sharing.isAvailableAsync()) {
      await Sharing.shareAsync(file.uri, { mimeType: MIME[ext], dialogTitle: name, UTI: UTI[ext] });
      return;
    }
  } catch {
    // fall through to the plain share sheet below
  }
  Share.share({ message: content, title: name });
}

// Share an already-generated file (e.g. a printed PDF) under a clear name.
export async function shareFileAs(srcUri: string, what: string, ext: 'pdf'): Promise<void> {
  const name = exportFilename(what, ext);
  let uri = srcUri;
  try {
    const dest = new File(Paths.cache, name);
    await new File(srcUri).copy(dest, { overwrite: true });
    uri = dest.uri;
  } catch {
    // if the copy fails, share the original file
  }
  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(uri, { mimeType: MIME[ext], dialogTitle: name, UTI: UTI[ext] });
  }
}
