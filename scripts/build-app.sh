#!/bin/zsh
# يبني ميزان ويغلّفه في تطبيق: build/Mizan.app
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release
APP=build/Mizan.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Mizan "$APP/Contents/MacOS/Mizan"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# خط ثمانية مضمّن في التطبيق، فيظهر كما صُمّم حتى على جهاز لا يملك الخط (مجاني للتطبيقات: font.thmanyah.com)
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/Fonts/*.otf "$APP/Contents/Resources/Fonts/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.mizan.app</string>
  <key>CFBundleName</key><string>Mizan</string>
  <key>CFBundleDisplayName</key><string>ميزان</string>
  <key>CFBundleExecutable</key><string>Mizan</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>ar</string>
  <key>NSHumanReadableCopyright</key><string>بيانات محلية فقط — لا اتصال بالإنترنت</string>
</dict></plist>
PLIST
# توقيع محلي بمتطلّب ثابت (المعرّف فقط) حتى لا تسقط صلاحية Accessibility مع كل إعادة بناء.
# قبل النشر العام: يُستبدل بتوقيع Developer ID من Apple.
codesign --force --sign - -r='designated => identifier "local.mizan.app"' "$APP"
echo "تم البناء: $PWD/$APP"

# ./scripts/build-app.sh --install ← ينسخه إلى مجلد التطبيقات ويشغّله
if [[ "${1:-}" == "--install" ]]; then
  pkill -x Mizan || true
  sleep 1
  rm -rf /Applications/Mizan.app
  ditto "$APP" /Applications/Mizan.app
  open /Applications/Mizan.app --args ${2:+--open "$2"}
  echo "ثُبّت في: /Applications/Mizan.app"
fi
