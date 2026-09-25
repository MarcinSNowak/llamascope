#!/bin/bash
#
# Build a release: Developer ID signature, notarization, .dmg.
#
# This is a one-line wrapper around `wydanie.sh` ("wydanie" is Polish for
# "release"), and that is deliberate, not laziness. The eight steps in that
# script are what stops a half-signed package from reaching somebody else's
# Mac. A second, translated copy of them would drift from the first the
# moment a check is added to only one file — quietly, and in the direction
# that lets a bad release through. So there is exactly one copy of the
# checks and two sets of sentences; this file selects the English ones.
#
# Every message you will see is in English. The comments in `wydanie.sh`
# are given twice — Polish first, then the same thing after an `# EN:`
# marker — so the reasoning behind each check is readable either way. That
# file is worth reading before changing anything here: most of those checks
# were added after something got through.
#
# Usage:
#   ./release.sh                    — build, sign, notarize, make the .dmg
#   ./release.sh --no-notarization  — everything except notarization (fast)
#
# Required once, before the first run:
#   xcrun notarytool store-credentials llamascope \
#       --apple-id <your-apple-id> --team-id 83L8M7P67X
# (it asks for an app-specific password from appleid.apple.com — the
# password goes straight into the keychain and is left in no file)

exec env LLAMASCOPE_LANG=en "$(cd "$(dirname "$0")" && pwd)/wydanie.sh" "$@"
