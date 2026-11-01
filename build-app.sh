#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

bin="$(find .build -type f -name volume-bordo -perm +111 | grep -i '/[Rr]elease/' | head -1)"
if [[ -z "$bin" ]]; then
  echo "binario di release non trovato" >&2
  exit 1
fi

rm -rf Bordi.app
mkdir -p Bordi.app/Contents/MacOS
cp "$bin" Bordi.app/Contents/MacOS/Bordi
cp Support/Info.plist Bordi.app/Contents/Info.plist
codesign --force --sign - Bordi.app
echo "Pronto: $(pwd)/Bordi.app"
