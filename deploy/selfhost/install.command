#!/usr/bin/env sh
# macOS Finder launcher. If macOS asks, open Terminal and run install.sh.
exec "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/install.sh"
