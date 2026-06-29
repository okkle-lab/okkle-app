import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';

function readJson<T>(path: string): T {
  return JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8')) as T;
}

describe('release metadata', () => {
  it('keeps native, npm, and lockfile versions in sync', () => {
    const app = readJson<{ expo: { version: string } }>('../app.json');
    const pkg = readJson<{ version: string }>('../package.json');
    const lock = readJson<{ version: string; packages: Record<string, { version?: string }> }>('../package-lock.json');

    assert.match(pkg.version, /^\d+\.\d+\.\d+$/);
    assert.equal(pkg.version, `${app.expo.version}.0`);
    assert.equal(lock.version, pkg.version);
    assert.equal(lock.packages[''].version, pkg.version);
  });

  it('keeps EAS and bundle identifiers consistent in docs', () => {
    const app = readJson<{
      expo: {
        ios: { bundleIdentifier: string };
        android: { package: string };
        extra: { eas: { projectId: string } };
      };
    }>('../app.json');
    const readme = readFileSync(new URL('../README.md', import.meta.url), 'utf8');
    const release = readFileSync(new URL('../RELEASE.md', import.meta.url), 'utf8');

    for (const doc of [readme, release]) {
      assert.match(doc, new RegExp(app.expo.extra.eas.projectId));
      assert.match(doc, new RegExp(app.expo.ios.bundleIdentifier));
      assert.match(doc, new RegExp(app.expo.android.package));
    }
  });

  it('includes a privacy notice for store review', () => {
    const privacy = readFileSync(new URL('../PRIVACY.md', import.meta.url), 'utf8');

    assert.match(privacy, /background location/i);
    assert.match(privacy, /camera/i);
    assert.match(privacy, /admin@okklelab\.com/i);
  });
});
