const fs = require('fs');
const path = require('path');
const {
  IOSConfig,
  withDangerousMod,
  withInfoPlist,
  withXcodeProject,
} = require('@expo/config-plugins');

const nativeSwiftTemplatePath = path.join(__dirname, 'ios', 'OkkleNativeApp.swift');

function swiftUIAppDelegateContents() {
  return `import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    window = UIWindow(frame: UIScreen.main.bounds)
    window?.rootViewController = UIHostingController(rootView: OkkleNativeRootView())
    window?.makeKeyAndVisible()
    return true
  }
}
`;
}

function writeNativeSwiftFiles(projectRoot) {
  const appDelegatePath = IOSConfig.Paths.getAppDelegateFilePath(projectRoot);
  const appSourceDir = path.dirname(appDelegatePath);
  const nativeDir = path.join(appSourceDir, 'Native');
  const nativeSwiftPath = path.join(nativeDir, 'OkkleNativeApp.swift');

  fs.mkdirSync(nativeDir, { recursive: true });
  fs.writeFileSync(appDelegatePath, swiftUIAppDelegateContents());
  fs.copyFileSync(nativeSwiftTemplatePath, nativeSwiftPath);
}

function addNativeSwiftFileToXcodeProject(config) {
  const project = config.modResults;
  const projectName = IOSConfig.XcodeUtils.getProjectName(config.modRequest.projectRoot);
  const groupName = `${projectName}/Native`;
  const sourcePath = 'OkkleNativeApp.swift';
  const target = IOSConfig.XcodeUtils.getApplicationNativeTarget({ project, projectName });

  const nativeGroup = IOSConfig.XcodeUtils.ensureGroupRecursively(project, groupName);
  if (nativeGroup) {
    nativeGroup.path = groupName;
    nativeGroup.sourceTree = '"<group>"';
  }

  if (!project.hasFile(sourcePath)) {
    config.modResults = IOSConfig.XcodeUtils.addBuildSourceFileToGroup({
      filepath: sourcePath,
      groupName,
      project,
      targetUuid: target.uuid,
    });
  }

  const appVersion = config.version || '0.4';
  for (const [, buildConfig] of IOSConfig.XcodeUtils.getBuildConfigurationsForListId(project, target.target.buildConfigurationList)) {
    buildConfig.buildSettings.MARKETING_VERSION = appVersion;
  }

  return config;
}

module.exports = function withSdk56IosAppDelegate(config) {
  config = withInfoPlist(config, (config) => {
    config.modResults.CFBundleShortVersionString = '$(MARKETING_VERSION)';
    return config;
  });

  config = withDangerousMod(config, [
    'ios',
    async (config) => {
      writeNativeSwiftFiles(config.modRequest.projectRoot);
      return config;
    },
  ]);

  config = withXcodeProject(config, addNativeSwiftFileToXcodeProject);

  return config;
};
