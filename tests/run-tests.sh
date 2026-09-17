#!/bin/sh
# Exercises contents/code/usage.js against captured and synthetic API responses.
# Uses gjs; the file is plain JS with no QML dependencies by design.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -t claudeusage-tests-XXXXXX.js)
trap 'rm -f "$out"' EXIT
cat "$here/../package/contents/code/usage.js" "$here/test-usage.js" > "$out"
# Day boundaries in the trend are local midnights; pin them.
TZ=UTC exec gjs "$out" "$here"
