#!/bin/zsh
# يبني ميزان ويغلّفه في تطبيق: build/Mizan.app
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# المعماريات المطلوبة في الملف التنفيذي: افتراضياً Universal (Apple Silicon + Intel).
# MIZAN_ARCHS="x86_64" (مثلاً) لبناء شريحة واحدة صراحةً؛ لا يُنتَج ملف ناقص بصمت أبداً.
ARCHS=(${=MIZAN_ARCHS:-arm64 x86_64})

# كل معمارية تُبنى في مجلد عمل مستقل، ثم تُدمج الملفات التنفيذية بـ lipo.
BINS=()
for arch in $ARCHS; do
  swift build -c release --arch "$arch" --scratch-path ".build-$arch"
  bin_dir=$(swift build -c release --arch "$arch" --scratch-path ".build-$arch" --show-bin-path)
  [[ -f "$bin_dir/Mizan" ]] || { echo "خطأ: لم يُنتَج $bin_dir/Mizan للمعمارية $arch" >&2; exit 1 }
  BINS+=("$bin_dir/Mizan")
done

# يتحقق أن الملف يحوي المعماريات المطلوبة بالضبط (دون الاعتماد على ترتيبها).
verify_archs() {
  local actual=(${=$(lipo -archs "$1")}) want have found
  for want in $ARCHS; do
    found=0
    for have in $actual; do [[ "$have" == "$want" ]] && found=1; done
    (( found )) || { echo "خطأ: المعمارية $want غائبة عن $1 (الموجود: ${actual[*]})" >&2; exit 1 }
  done
  (( ${#actual} == ${#ARCHS} )) || { echo "خطأ: معماريات غير متوقعة في $1: ${actual[*]}" >&2; exit 1 }
}

APP=build/Mizan.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/Mizan"
verify_archs "$APP/Contents/MacOS/Mizan"
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
  <key>CFBundleShortVersionString</key><string>1.0.1</string>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>CFBundleVersion</key><string>2</string>
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
# بعد التوقيع: الملف التنفيذي ما زال يحمل المعماريات المطلوبة والتوقيع سليم.
verify_archs "$APP/Contents/MacOS/Mizan"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "تم البناء: $PWD/$APP ($(lipo -archs "$APP/Contents/MacOS/Mizan"))"

# ./scripts/build-app.sh --install ← ينسخه إلى مجلد التطبيقات ويشغّله
if [[ "${1:-}" == "--install" ]]; then
  pkill -x Mizan || true
  sleep 1
  rm -rf /Applications/Mizan.app
  ditto "$APP" /Applications/Mizan.app
  open /Applications/Mizan.app --args ${2:+--open "$2"}
  echo "ثُبّت في: /Applications/Mizan.app"
fi
