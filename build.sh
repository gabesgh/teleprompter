#!/bin/zsh
# Builds dist/Teleprompter.app.
#   ./build.sh            build only
#   ./build.sh --open     build and launch
#   ./build.sh --install  build and copy to /Applications
set -euo pipefail
cd "$(dirname "$0")"

# Regenerate the Xcode project from project.yml when xcodegen is available;
# otherwise use the committed Teleprompter.xcodeproj as-is.
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --quiet
elif [[ ! -d Teleprompter.xcodeproj ]]; then
  echo "Teleprompter.xcodeproj is missing and xcodegen isn't installed (brew install xcodegen)" >&2
  exit 1
fi

xcodebuild -project Teleprompter.xcodeproj -scheme Teleprompter -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" -quiet build

rm -rf dist && mkdir -p dist
cp -R build/DerivedData/Build/Products/Release/Teleprompter.app dist/
echo "Built dist/Teleprompter.app"

case "${1:-}" in
  --open)    open dist/Teleprompter.app ;;
  --install) rm -rf /Applications/Teleprompter.app && cp -R dist/Teleprompter.app /Applications/ && echo "Installed to /Applications" ;;
esac
