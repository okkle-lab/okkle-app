#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo "Preparing Expo iOS workspace for Xcode Cloud..."

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js/npm not found. Installing Node.js with Homebrew..."
  brew install node
fi

if ! command -v pod >/dev/null 2>&1; then
  echo "CocoaPods not found. Installing CocoaPods with Homebrew..."
  brew install cocoapods
fi

export CI=1
export EXPO_NO_TELEMETRY=1

echo "Installing JavaScript dependencies..."
npm ci --include=dev

echo "Generating iOS native project..."
npx expo prebuild --platform ios --no-install

echo "Installing CocoaPods..."
cd ios
pod install

if [ ! -d "Okkle.xcworkspace" ]; then
  echo "Expected ios/Okkle.xcworkspace to exist after pod install, but it was not created."
  exit 1
fi

echo "Xcode workspace is ready at ios/Okkle.xcworkspace."
