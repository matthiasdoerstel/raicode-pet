#!/bin/bash
# Installs or updates Raicode Pet: fetches the source, builds the app locally and installs it
# to /Applications. Building on the Mac itself means no signing or Gatekeeper warnings.
#
#   curl -fsSL https://raw.githubusercontent.com/matthiasdoerstel/raicode-pet/main/install.sh | bash
#
# Run the same line again to update.
set -euo pipefail

REPO=https://github.com/matthiasdoerstel/raicode-pet.git
DIR="${RAICODE_PET_DIR:-$HOME/.raicode-pet/source}"

fail() { echo "✗ $*" >&2; exit 1; }

# Everything runs from main, so a half-downloaded script does nothing.
main() {
    [ "$(uname)" = Darwin ] || fail "Raicode Pet is a macOS app."
    local os
    os=$(sw_vers -productVersion | cut -d. -f1)
    [ "$os" -ge 26 ] || fail "Raicode Pet needs macOS 26 or later (you have $(sw_vers -productVersion))."

    xcrun --find swift >/dev/null 2>&1 \
        || fail "Swift isn't installed. Run: xcode-select --install — then run this again."
    local sdk
    sdk=$(xcrun --show-sdk-version | cut -d. -f1)
    [ "$sdk" -ge 26 ] || fail "Needs the macOS 26 SDK (Xcode 26 or its Command Line Tools); found SDK $(xcrun --show-sdk-version)."

    if [ -d "$DIR/.git" ]; then
        echo "→ Updating source in $DIR"
        git -C "$DIR" pull --ff-only --quiet
    else
        echo "→ Downloading source to $DIR"
        mkdir -p "$(dirname "$DIR")"
        git clone --depth 1 --quiet "$REPO" "$DIR"
    fi

    echo "→ Building (takes a minute the first time)"
    cd "$DIR"
    ./build_app.sh >/dev/null

    # Restart a running copy so the new version takes over.
    pkill -x RaicodePet 2>/dev/null && sleep 1 || true
    open /Applications/RaicodePet.app

    echo "✓ Raicode Pet is installed. On first launch it offers to connect to Raicode — accept,"
    echo "  then restart any running Raicode sessions."
}

main "$@"
