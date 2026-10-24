#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

echo "🔨 Building LLMTrack (Release arm64)..."
swift build -c release

APP_NAME="LLMTrack"
BUILD_DIR="$DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "📦 Packaging $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$DIR/.build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "✍️  Codesigning $APP_NAME.app with ad-hoc identity..."
codesign -s - --force --deep "$APP_BUNDLE" 2>/dev/null || true

echo "✅ Successfully built $APP_BUNDLE"
echo "🚀 To launch, run: open \"$APP_BUNDLE\""
