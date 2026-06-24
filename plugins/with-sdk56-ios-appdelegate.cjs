const fs = require('fs');
const { IOSConfig, withDangerousMod } = require('@expo/config-plugins');

function updateAppDelegate(contents) {
  return contents
    .replace(/^internal internal import Expo$/m, 'public import Expo')
    .replace(/^internal import Expo$/m, 'public import Expo')
    .replace(/^import Expo$/m, 'public import Expo')
    .replace(/^class AppDelegate:/m, 'public class AppDelegate:')
    .replace(/^  override func application/gm, '  public override func application')
    .replace(/^\s*bindReactNativeFactory\(factory\)\n/m, '');
}

module.exports = function withSdk56IosAppDelegate(config) {
  return withDangerousMod(config, [
    'ios',
    async (config) => {
      const appDelegatePath = IOSConfig.Paths.getAppDelegateFilePath(
        config.modRequest.projectRoot,
      );

      if (!fs.existsSync(appDelegatePath)) {
        return config;
      }

      const contents = fs.readFileSync(appDelegatePath, 'utf8');
      const nextContents = updateAppDelegate(contents);

      if (nextContents !== contents) {
        fs.writeFileSync(appDelegatePath, nextContents);
      }

      return config;
    },
  ]);
};
