import { kvGet, kvSet } from './db';
import { sanitizeDiagnosticsText } from './diagnosticsPrivacy';

// Lightweight on-device diagnostics so bugs are easier to investigate.
// Everything is logged to a capped, persisted list (kv) and can be included
// in explicit user-initiated bug reports.

export type DiagEntry = { t: string; ctx: string; detail: string };
const KEY = 'diag_log';
const MAX = 60;

export function getDiagLog(): DiagEntry[] {
  try { return JSON.parse(kvGet(KEY) || '[]'); } catch { return []; }
}
export function clearDiagLog() { try { kvSet(KEY, '[]'); } catch { /* ignore */ } }

export function logEvent(ctx: string, detail: string) {
  try {
    const log = getDiagLog();
    log.unshift({
      t: new Date().toISOString(),
      ctx: sanitizeDiagnosticsText(ctx).slice(0, 120),
      detail: sanitizeDiagnosticsText(detail).slice(0, 1500),
    });
    kvSet(KEY, JSON.stringify(log.slice(0, MAX)));
  } catch { /* never let logging throw */ }
}

export function logError(ctx: string, err: unknown) {
  const e = err as any;
  const detail = [
    String(e?.message ?? e),
    (e?.stack ?? '').split('\n').slice(0, 8).join('\n'),
  ].filter(Boolean).join('\n');
  logEvent(ctx, detail);
}

// Catch otherwise-invisible fatal JS errors (release builds have no red box).
let installed = false;
export function installGlobalErrorLogging() {
  if (installed) return;
  installed = true;
  try {
    const g: any = globalThis as any;
    const prev = g.ErrorUtils?.getGlobalHandler?.();
    g.ErrorUtils?.setGlobalHandler?.((error: any, isFatal?: boolean) => {
      logError(isFatal ? 'fatal-js' : 'js-error', error);
      prev?.(error, isFatal);
    });
  } catch { /* ignore */ }
}
