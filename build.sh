#!/bin/sh
set -eu

# Do pre-build clean up of build artifacts
for f in *.pas; do
  [ -e "$f" ] || continue
  base=${f%.pas}
  rm -f "$base.o" "$base.ppu"
done

if [ -f ./sparce ]; then
  rm -f ./sparce
fi

# pass -dDEBUG for some debug output
if [ "$#" -ge 1 ]; then
  fpc sparce.pas "$@"
else
  fpc sparce.pas
fi

# Do post-build clean up of build artifacts
for f in *.pas; do
  [ -e "$f" ] || continue
  base=${f%.pas}
  rm -f "$base.o" "$base.ppu"
done

