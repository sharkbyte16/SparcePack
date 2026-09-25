#!/bin/sh
set -eu

# Do pre-build clean up of build artifacts
if [ -f ./sparce ]; then
  rm -f ./sparce
fi

odin build . -o:speed -no-bounds-check -out:sparce

