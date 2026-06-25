module.exports = function (api) {
  api.cache(true);
  // babel-preset-expo (SDK 56) automatically applies the react-native-worklets /
  // Reanimated 4 plugin when reanimated is installed, so no extra plugin is needed.
  return {
    presets: ['babel-preset-expo'],
  };
};
