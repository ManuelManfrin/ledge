#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

bin="$(find .build -type f -name Ledge -perm +111 | grep -i '/[Rr]elease/' | head -1)"
if [[ -z "$bin" ]]; then
  echo "binario di release non trovato" >&2
  exit 1
fi

rm -rf Ledge.app
mkdir -p Ledge.app/Contents/MacOS
cp "$bin" Ledge.app/Contents/MacOS/Ledge
cp Support/Info.plist Ledge.app/Contents/Info.plist
codesign --force --sign - Ledge.app
echo "Pronto: $(pwd)/Ledge.app"
