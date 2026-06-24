const fs = require('fs');
const path = require('path');

const projectRoot = path.join(__dirname, '..');
const changes = [];

function replaceAllInFile(filePath, replacements, label) {
  if (!fs.existsSync(filePath)) {
    return;
  }

  let contents = fs.readFileSync(filePath, 'utf8');
  let nextContents = contents;
  let changed = false;

  for (const [before, after] of replacements) {
    if (nextContents.includes(before)) {
      nextContents = nextContents.split(before).join(after);
      changed = true;
    }
  }

  if (changed && nextContents !== contents) {
    fs.writeFileSync(filePath, nextContents);
    changes.push(label);
  }
}

function patchReactNativePodFileUrls() {
  const replacement = [
    'URI::File.build(path: destinationDebug).to_s',
    '"file://" + URI::DEFAULT_PARSER.escape(File.expand_path(destinationDebug))',
  ];

  replaceAllInFile(
    path.join(
      projectRoot,
      'node_modules',
      'react-native',
      'scripts',
      'cocoapods',
      'rncore.rb',
    ),
    [replacement],
    'React Native core podspec file URL handling',
  );

  replaceAllInFile(
    path.join(
      projectRoot,
      'node_modules',
      'react-native',
      'scripts',
      'cocoapods',
      'rndependencies.rb',
    ),
    [replacement],
    'React Native dependencies podspec file URL handling',
  );
}

function patchReactNativeFindCommands() {
  replaceAllInFile(
    path.join(
      projectRoot,
      'node_modules',
      'react-native',
      'scripts',
      'cocoapods',
      'new_architecture.rb',
    ),
    [
      [
        'infoPlistFiles = `find #{projectFolderPath} -name "Info.plist"`',
        'infoPlistFiles = `find #{Shellwords.escape(projectFolderPath)} -name "Info.plist"`',
      ],
    ],
    'React Native new architecture Info.plist search',
  );
}

function patchExpoConstantsPodspec() {
  const podspecPath = path.join(
    projectRoot,
    'node_modules',
    'expo-constants',
    'ios',
    'EXConstants.podspec',
  );

  if (!fs.existsSync(podspecPath)) {
    return;
  }

  let podspec = fs.readFileSync(podspecPath, 'utf8');
  let nextPodspec = podspec;

  if (!nextPodspec.includes("require 'shellwords'")) {
    nextPodspec = nextPodspec.replace(
      "require 'json'\n",
      "require 'json'\nrequire 'shellwords'\n",
    );
  }

  const before =
    '  env_vars = ENV[\'PROJECT_ROOT\'] ? "PROJECT_ROOT=#{ENV[\'PROJECT_ROOT\']} " : ""\n' +
    '  script_phase = {\n' +
    '    :name => \'Generate app.config for prebuilt Constants.manifest\',\n' +
    '    :script => "bash -l -c \\"#{env_vars}$PODS_TARGET_SRCROOT/../scripts/get-app-config-ios.sh\\"",\n';
  const after =
    '  env_vars = ENV[\'PROJECT_ROOT\'] ? "export PROJECT_ROOT=#{Shellwords.escape(ENV[\'PROJECT_ROOT\'])}; " : ""\n' +
    '  script_phase = {\n' +
    '    :name => \'Generate app.config for prebuilt Constants.manifest\',\n' +
    '    :script => "#{env_vars}\\"$PODS_TARGET_SRCROOT/../scripts/get-app-config-ios.sh\\"",\n';

  if (nextPodspec.includes(before)) {
    nextPodspec = nextPodspec.replace(before, after);
  }

  if (nextPodspec !== podspec) {
    fs.writeFileSync(podspecPath, nextPodspec);
    changes.push('expo-constants iOS podspec');
  }
}

function patchExpoConstantsAppConfigScript() {
  replaceAllInFile(
    path.join(
      projectRoot,
      'node_modules',
      'expo-constants',
      'scripts',
      'get-app-config-ios.sh',
    ),
    [
      [
        'PROJECT_DIR_BASENAME=$(basename $PROJECT_DIR)',
        'PROJECT_DIR_BASENAME=$(basename "$PROJECT_DIR")',
      ],
    ],
    'expo-constants app config script',
  );
}

function patchGeneratedXcodeProject() {
  replaceAllInFile(
    path.join(projectRoot, 'ios', 'Okkle.xcodeproj', 'project.pbxproj'),
    [
      [
        '`\\"$NODE_BINARY\\" --print \\"require(\'path\').dirname(require.resolve(\'react-native/package.json\')) + \'/scripts/react-native-xcode.sh\'\\"`',
        'REACT_NATIVE_XCODE_SCRIPT=\\"$(\\"$NODE_BINARY\\" --print \\"require(\'path\').dirname(require.resolve(\'react-native/package.json\')) + \'/scripts/react-native-xcode.sh\'\\")\\"\\n\\"$REACT_NATIVE_XCODE_SCRIPT\\"',
      ],
    ],
    'generated iOS React Native bundle phase',
  );
}

function patchGeneratedAppDelegate() {
  const appDelegatePath = path.join(
    projectRoot,
    'ios',
    'Okkle',
    'AppDelegate.swift',
  );

  if (!fs.existsSync(appDelegatePath)) {
    return;
  }

  const contents = fs.readFileSync(appDelegatePath, 'utf8');
  const nextContents = contents
    .replace(/^internal internal import Expo$/m, 'public import Expo')
    .replace(/^internal import Expo$/m, 'public import Expo')
    .replace(/^import Expo$/m, 'public import Expo')
    .replace(/^class AppDelegate:/m, 'public class AppDelegate:')
    .replace(/^  override func application/gm, '  public override func application')
    .replace(/^\s*bindReactNativeFactory\(factory\)\n/m, '');

  if (nextContents !== contents) {
    fs.writeFileSync(appDelegatePath, nextContents);
    changes.push('generated iOS AppDelegate Expo import');
  }
}

patchReactNativePodFileUrls();
patchReactNativeFindCommands();
patchExpoConstantsPodspec();
patchExpoConstantsAppConfigScript();
patchGeneratedXcodeProject();
patchGeneratedAppDelegate();

if (changes.length > 0) {
  console.log(
    `Patched ${changes.join(', ')} for workspace paths containing spaces.`,
  );
}
