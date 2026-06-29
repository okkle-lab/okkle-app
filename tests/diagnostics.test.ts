import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { sanitizeDiagnosticsText } from '../src/diagnosticsPrivacy';

describe('diagnostics privacy', () => {
  it('redacts local macOS checkout paths while keeping useful file and line context', () => {
    const stack = [
      'Error: boom',
      '    at Home (/Users/henry/Developer/Okkle/okkle-app/app/(tabs)/index.tsx:151:7)',
      "module cache path '/Users/henry/Developer/AI Google/okkle-app/node_modules/expo-modules-jsi/apple/.DerivedData/SwiftShims.pcm'",
    ].join('\n');

    const sanitized = sanitizeDiagnosticsText(stack);

    assert.doesNotMatch(sanitized, /\/Users\/henry/);
    assert.doesNotMatch(sanitized, /Developer\/AI Google/);
    assert.match(sanitized, /\[local path\]\/index\.tsx:151:7/);
    assert.match(sanitized, /\[local path\]\/SwiftShims\.pcm/);
  });

  it('redacts file URLs and Windows user paths', () => {
    const sanitized = sanitizeDiagnosticsText([
      'file:///Users/henry/Developer/Okkle/okkle-app/src/diagnostics.ts:24:3',
      String.raw`C:\Users\Henry\Developer\okkle-app\src\App.tsx:8:4`,
    ].join('\n'));

    assert.doesNotMatch(sanitized, /\/Users\/henry/);
    assert.doesNotMatch(sanitized, /C:\\Users\\Henry/);
    assert.match(sanitized, /\[local path\]\/diagnostics\.ts:24:3/);
    assert.match(sanitized, /\[local path\]\/App\.tsx:8:4/);
  });

  it('does not redact non-local URLs or React component names', () => {
    const text = 'at Screen (https://example.com/bundle.js:10:2)\n    in AppErrorBoundary';

    assert.equal(sanitizeDiagnosticsText(text), text);
  });
});
