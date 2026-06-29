const REDACTED_PATH_PREFIX = '[local path]';

const LOCAL_UNIX_PATH =
  /(?:file:\/\/)?(?:\/(?:Users|Volumes)\/[^\n\r"'`<>[\]{}]+|\/(?:private\/var|var\/folders|tmp)\/[^\n\r"'`<>[\]{}]+)/g;
const LOCAL_WINDOWS_PATH =
  /(?:file:\/\/\/)?[A-Za-z]:\\(?:Users|Documents and Settings)\\[^\n\r"'`<>[\]{}]+/g;
const SOURCE_LOCATION_SUFFIX = /(?::\d+(?::\d+)?)$/;
const TRAILING_WRAPPER_PUNCTUATION = /[),.;]+$/;

function redactLocalPath(match: string): string {
  const trailing = match.match(TRAILING_WRAPPER_PUNCTUATION)?.[0] ?? '';
  const withoutTrailing = trailing ? match.slice(0, -trailing.length) : match;
  const location = withoutTrailing.match(SOURCE_LOCATION_SUFFIX)?.[0] ?? '';
  const withoutLocation = location ? withoutTrailing.slice(0, -location.length) : withoutTrailing;
  const normalized = withoutLocation.replace(/^file:\/\/\/?/, '').replace(/\\/g, '/');
  const filename = normalized.split('/').filter(Boolean).pop() || 'file';

  return `${REDACTED_PATH_PREFIX}/${filename}${location}${trailing}`;
}

export function sanitizeDiagnosticsText(value: unknown): string {
  return String(value)
    .replace(LOCAL_UNIX_PATH, redactLocalPath)
    .replace(LOCAL_WINDOWS_PATH, redactLocalPath);
}
