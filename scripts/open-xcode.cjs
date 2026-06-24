#!/usr/bin/env node

const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const projectRoot = path.resolve(__dirname, '..');
const workspacePath = path.join(projectRoot, 'ios', 'Okkle.xcworkspace');
const packageJsonPath = path.join(projectRoot, 'package.json');
const packageLockPath = path.join(projectRoot, 'package-lock.json');
const nodeModulesLockPath = path.join(
  projectRoot,
  'node_modules',
  '.package-lock.json',
);

const args = new Set(process.argv.slice(2));
const skipMetro =
  args.has('--no-metro') || process.env.OKKLE_XCODE_SKIP_METRO === '1';
const skipOpen =
  args.has('--no-open') || process.env.OKKLE_XCODE_SKIP_OPEN === '1';
const skipPrebuild =
  args.has('--no-prebuild') || process.env.OKKLE_XCODE_SKIP_PREBUILD === '1';
const noClean =
  args.has('--no-clean') || process.env.OKKLE_XCODE_NO_CLEAN === '1';

function log(message) {
  console.log(`\n> ${message}`);
}

function fail(message) {
  console.error(`\n${message}`);
  process.exit(1);
}

function run(command, commandArgs, options = {}) {
  const result = spawnSync(command, commandArgs, {
    cwd: projectRoot,
    env: { ...process.env, ...options.env },
    stdio: options.capture ? 'pipe' : 'inherit',
    encoding: 'utf8',
  });

  if (result.error) {
    fail(`Could not run ${command}: ${result.error.message}`);
  }

  if (result.status !== 0) {
    if (options.capture && result.stderr) {
      process.stderr.write(result.stderr);
    }
    fail(`${command} ${commandArgs.join(' ')} failed.`);
  }

  return result;
}

function commandExists(command) {
  const result = spawnSync('which', [command], {
    stdio: 'ignore',
  });
  return result.status === 0;
}

function assertMac() {
  if (process.platform !== 'darwin') {
    fail('Opening this app in Xcode requires macOS.');
  }
}

function assertNodeVersion() {
  const [major, minor] = process.versions.node.split('.').map(Number);
  if (major < 22 || (major === 22 && minor < 13)) {
    fail(
      `Expo SDK 56 requires Node.js 22.13 or newer. Current Node is ${process.version}.`,
    );
  }
}

function assertXcode() {
  if (!commandExists('xcodebuild')) {
    fail('Xcode command line tools were not found. Install Xcode first.');
  }

  const result = run('xcodebuild', ['-version'], { capture: true });
  const versionLine = result.stdout.split('\n').find((line) => line.startsWith('Xcode '));
  const match = versionLine && versionLine.match(/^Xcode\s+(\d+)(?:\.(\d+))?/);

  if (!match) {
    console.warn('Could not determine the installed Xcode version.');
    return;
  }

  const major = Number(match[1]);
  const minor = Number(match[2] || 0);
  if (major < 26 || (major === 26 && minor < 4)) {
    fail(
      `Expo SDK 56 requires Xcode 26.4 or newer. Current ${versionLine}.`,
    );
  }
}

function assertCocoaPods() {
  if (!commandExists('pod')) {
    fail(
      'CocoaPods was not found. Install it with `brew install cocoapods`, then rerun `npm run xcode`.',
    );
  }
}

function newerThan(filePath, otherPath) {
  if (!fs.existsSync(filePath) || !fs.existsSync(otherPath)) {
    return false;
  }
  return fs.statSync(filePath).mtimeMs > fs.statSync(otherPath).mtimeMs;
}

function dependenciesNeedInstall() {
  const expoPackage = path.join(projectRoot, 'node_modules', 'expo', 'package.json');

  if (!fs.existsSync(expoPackage)) {
    return true;
  }

  if (!fs.existsSync(nodeModulesLockPath)) {
    return true;
  }

  return (
    newerThan(packageJsonPath, nodeModulesLockPath) ||
    newerThan(packageLockPath, nodeModulesLockPath)
  );
}

function installDependenciesIfNeeded() {
  if (dependenciesNeedInstall()) {
    log('Installing npm dependencies');
    run('npm', ['install']);
  } else {
    log('npm dependencies are already installed');
  }

  log('Applying local iOS build patches');
  run('npm', ['run', 'postinstall']);
}

function prebuildIos() {
  if (skipPrebuild) {
    log('Skipping iOS prebuild');
    return;
  }

  const prebuildArgs = ['expo', 'prebuild', '--platform', 'ios', '--npm'];

  if (!noClean) {
    prebuildArgs.push('--clean');
  }

  log(`Generating the iOS project with ${noClean ? 'prebuild' : 'clean prebuild'}`);
  run('npx', prebuildArgs, {
    env: {
      EXPO_NO_GIT_STATUS: '1',
    },
  });

  log('Applying patches to the generated iOS project');
  run('npm', ['run', 'postinstall']);
}

function validateWorkspace() {
  if (!fs.existsSync(workspacePath)) {
    fail(
      'The Xcode workspace was not generated. Check the Expo prebuild output above.',
    );
  }

  log('Validating the Xcode workspace');
  run('xcodebuild', ['-list', '-workspace', workspacePath]);
}

function shellQuote(value) {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function appleScriptString(value) {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

function readMetroStatus() {
  return new Promise((resolve) => {
    const request = http.get(
      {
        host: 'localhost',
        port: 8081,
        path: '/status',
        timeout: 1000,
      },
      (response) => {
        const rootHeader = response.headers['x-react-native-project-root'];
        response.resume();

        let projectRootHeader = null;
        if (typeof rootHeader === 'string') {
          try {
            projectRootHeader = decodeURIComponent(rootHeader);
          } catch {
            projectRootHeader = rootHeader;
          }
        }

        resolve({
          ok: response.statusCode === 200,
          projectRoot: projectRootHeader,
        });
      },
    );

    request.on('timeout', () => {
      request.destroy();
      resolve({ ok: false, projectRoot: null });
    });

    request.on('error', () => {
      resolve({ ok: false, projectRoot: null });
    });
  });
}

async function waitForMetro(timeoutMs) {
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const status = await readMetroStatus();
    if (status.ok) {
      return status;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }

  return { ok: false, projectRoot: null };
}

function startMetroInTerminal() {
  const command = `cd ${shellQuote(projectRoot)} && npm run metro`;
  const script = [
    'tell application "Terminal"',
    'activate',
    `do script ${appleScriptString(command)}`,
    'end tell',
  ].join('\n');

  run('osascript', ['-e', script]);
}

async function ensureMetro() {
  if (skipMetro) {
    log('Skipping Metro startup');
    return;
  }

  const status = await readMetroStatus();
  if (status.ok) {
    if (status.projectRoot && path.resolve(status.projectRoot) !== projectRoot) {
      fail(
        `Port 8081 is already running Metro for ${status.projectRoot}. Stop that server, then rerun npm run xcode.`,
      );
    }

    log('Metro is already running for this project');
    return;
  }

  log('Starting Metro in a separate Terminal window');
  startMetroInTerminal();

  const nextStatus = await waitForMetro(45000);
  if (!nextStatus.ok) {
    console.warn(
      'Metro did not answer within 45 seconds. A Terminal window was opened; wait for Metro there before pressing Run in Xcode.',
    );
    return;
  }

  log('Metro is running at http://localhost:8081');
}

function openWorkspace() {
  if (skipOpen) {
    log('Skipping Xcode open');
    return;
  }

  log('Opening ios/Okkle.xcworkspace in Xcode');
  run('open', [workspacePath]);
}

async function main() {
  assertMac();
  assertNodeVersion();
  assertXcode();
  assertCocoaPods();
  installDependenciesIfNeeded();
  prebuildIos();
  validateWorkspace();
  await ensureMetro();
  openWorkspace();

  console.log(
    [
      '',
      'Ready.',
      'In Xcode, select the Okkle scheme, choose an iPhone simulator, and press Run.',
      'Keep the Metro Terminal window open while testing.',
    ].join(os.EOL),
  );
}

main().catch((error) => {
  fail(error && error.stack ? error.stack : String(error));
});
