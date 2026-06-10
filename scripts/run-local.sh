#!/bin/bash
set -euo pipefail

DEBUG=0
if [[ "${1:-}" == "--debug" ]]; then
    DEBUG=1
elif [[ $# -gt 0 ]]; then
    echo "Usage: $0 [--debug]" >&2
    exit 2
fi

for app_path in "$HOME/Applications/Scrawl.app" "/Applications/Scrawl.app"; do
    executable="$app_path/Contents/MacOS/Scrawl"
    pkill -f "^${executable}$" 2>/dev/null || true
done

for _ in {1..30}; do
    if ! pgrep -f '/Scrawl.app/Contents/MacOS/Scrawl$' >/dev/null; then
        break
    fi
    sleep 0.1
done

if pgrep -f '/Scrawl.app/Contents/MacOS/Scrawl$' >/dev/null; then
    echo "Could not stop the installed Scrawl app. Quit it and retry." >&2
    exit 1
fi

if [[ $DEBUG -eq 1 ]]; then
    exec env SCRAWL_DEBUG=1 swift run ScrawlApp
fi
exec env -u SCRAWL_DEBUG swift run ScrawlApp
