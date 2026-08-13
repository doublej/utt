set shell := ["zsh", "-uo", "pipefail", "-c"]
set unstable := true

# Self-signed "utt Dev". Hardcoded on purpose — see the note in project.yml.

identity := "A4F985E255EAA49E09BCA155A81331F318CA59CB"
keychain := env_var('HOME') + "/Library/Keychains/utt-dev.keychain-db"
built := ".build/Build/Products/Debug/utt.app"
built_release := ".build/Build/Products/Release/utt.app"
archive_path := "release/utt.xcarchive"
export_dir := "release/export"
export_options := "release/ExportOptions.plist"

# -skipMacroValidation: TCA and friends ship swift-syntax macro plugins, and Xcode
# demands an interactive "trust" click per package whenever their fingerprint moves.
# The pins in project.yml are the actual trust decision.

xcflags := "-project Utt.xcodeproj -derivedDataPath .build -skipMacroValidation -skipPackagePluginValidation"

default:
    @just --list
    @echo ''
    @echo "branch: $(git branch --show-current 2>/dev/null || echo 'n/a')"

[group('setup')]
install:
    @command -v xcodegen >/dev/null || echo 'warn: brew install xcodegen'
    @command -v swiftlint >/dev/null || echo 'warn: brew install swiftlint'
    just generate

# Never fall back to ad-hoc signing: it changes the designated requirement on every

# build, which silently resets Accessibility / Input Monitoring / Microphone.
[group('setup')]
verify-identity:
    #!/usr/bin/env zsh
    if ! security find-identity -p codesigning "{{ keychain }}" 2>/dev/null | grep -q "{{ identity }}"; then
        echo "error: signing identity {{ identity }} not found in {{ keychain }}" >&2
        echo "       restore it from the utt-dev.p12 backup — rebuilding a new cert resets every TCC grant" >&2
        exit 1
    fi
    security unlock-keychain -p uttdev "{{ keychain }}"

[group('build')]
generate:
    xcodegen generate --quiet

[group('build')]
build config="Debug": verify-identity generate
    #!/usr/bin/env zsh
    set -o pipefail
    xcodebuild {{ xcflags }} -scheme Utt -configuration {{ config }} build 2>&1 \
        | { command -v xcbeautify >/dev/null && xcbeautify --quiet || cat }

[group('build')]
build-release: (build "Release")

[group('develop')]
run: build
    #!/usr/bin/env zsh
    set -euo pipefail
    pkill -x utt 2>/dev/null || true
    while pgrep -x utt >/dev/null; do sleep 0.2; done
    open "{{ built }}"

# Build, replace /Applications/utt.app, launch it from there.
[group('deploy')]
install-app: build
    #!/usr/bin/env zsh
    set -euo pipefail
    pkill -x utt 2>/dev/null || true
    # `open` fails with -600 if the old copy is still tearing down.
    while pgrep -x utt >/dev/null; do sleep 0.2; done
    rm -rf "/Applications/utt.app"
    # ditto, not cp: it keeps the bundle's metadata and signature intact.
    ditto "{{ built }}" "/Applications/utt.app"
    open "/Applications/utt.app"
    echo "→ Installed and launched /Applications/utt.app"

[group('develop')]
xcode: generate
    open Utt.xcodeproj

# Confirms the signature is the stable one, so TCC grants survive.
[group('develop')]
dr:
    codesign -d -r- "{{ built }}" 2>&1 | tail -1

[group('quality')]
test:
    cd UttCore && swift test

# Reducer tests. Separate from `test` because these need the built app as a test

# host, so they cost a full xcodebuild rather than a package build.
[group('quality')]
test-app:
    #!/usr/bin/env zsh
    set -o pipefail
    xcodebuild {{ xcflags }} -scheme Utt -configuration Debug test 2>&1 \
        | { command -v xcbeautify >/dev/null && xcbeautify --quiet || cat }

[group('quality')]
lint:
    swiftlint lint --strict

[group('quality')]
lint-fix:
    swiftlint --fix && swiftlint lint --strict

[group('quality')]
just-fmt-check:
    just --fmt --check

[group('quality')]
loc-check:
    #!/usr/bin/env zsh
    setopt null_glob
    eval "$(python3 -c "
    import json, shlex
    c = json.load(open('.quality.json'))
    print(f'WARN={c[\"loc\"][\"warn\"]}')
    print(f'ERROR={c[\"loc\"][\"error\"]}')
    g = c['globs']
    print(f'GLOBS=({shlex.join(g)})')
    ")"
    err=0
    for pattern in $GLOBS; do
        for f in ${~pattern}; do
            lines=$(wc -l < "$f")
            if (( lines > ERROR )); then echo "error: $f ($lines lines, max $ERROR)"; err=1
            elif (( lines > WARN )); then echo "warn: $f ($lines lines, target ≤$WARN — don't trim, split the file!)"; fi
        done
    done
    exit $err

[group('quality')]
dir-check:
    #!/usr/bin/env zsh
    setopt null_glob
    eval "$(python3 -c "
    import json, shlex
    c = json.load(open('.quality.json'))
    print(f'MAX={c[\"dir\"][\"max_files\"]}')
    g = c['globs']
    print(f'GLOBS=({shlex.join(g)})')
    ")"
    err=0
    typeset -A counts
    for pattern in $GLOBS; do
        for f in ${~pattern}; do
            dir=${f:h}
            counts[$dir]=$(( ${counts[$dir]:-0} + 1 ))
        done
    done
    for dir count in ${(kv)counts}; do
        if (( count > MAX )); then
            echo "error: $dir ($count files, max $MAX)"
            err=1
        fi
    done
    exit $err

[group('quality')]
check:
    @echo '→ Justfile format...'
    just just-fmt-check
    @echo '→ File lengths...'
    just loc-check
    @echo '→ Directory sizes...'
    just dir-check
    @echo '→ Lint...'
    just lint
    @echo '→ Build...'
    just build
    @echo '→ Tests...'
    just test
    just test-app

# Everything below ships builds to other people, and none of it works until a
# Developer ID certificate exists. The debug identity above is self-signed: it is
# enough to keep TCC grants stable on this Mac and not enough for anyone else's.
# Ships the self-signed Release build as a zip, skipping notarization entirely.

# Recipients pay for that with one `xattr -dr com.apple.quarantine` — docs/INSTALL.md.
[group('release')]
release-zip: build-release
    #!/usr/bin/env zsh
    set -euo pipefail
    mkdir -p release
    rm -f release/utt.zip
    # ditto, not zip: it preserves the bundle's symlinks and signature.
    ditto -c -k --keepParent "{{ built_release }}" release/utt.zip
    codesign --verify --strict "{{ built_release }}"
    echo "→ release/utt.zip  $(du -h release/utt.zip | cut -f1)"
    shasum -a 256 release/utt.zip

[group('release')]
archive: generate
    #!/usr/bin/env zsh
    set -o pipefail
    rm -rf "{{ archive_path }}"
    xcodebuild {{ xcflags }} -scheme Utt -configuration Release \
        -archivePath "{{ archive_path }}" archive 2>&1 \
        | { command -v xcbeautify >/dev/null && xcbeautify --quiet || cat }

# Sparkle explicitly discourages --deep; the export step signs nested code correctly.
[group('release')]
export-app: archive
    #!/usr/bin/env zsh
    set -o pipefail
    if [[ ! -f "{{ export_options }}" ]]; then
        echo "error: {{ export_options }} missing — copy docs/ExportOptions.plist.example and fill in the team id" >&2
        exit 1
    fi
    rm -rf "{{ export_dir }}"
    xcodebuild -exportArchive -archivePath "{{ archive_path }}" \
        -exportOptionsPlist "{{ export_options }}" -exportPath "{{ export_dir }}"

# Requires `xcrun notarytool store-credentials utt-notary` once, with an

# app-specific password from appleid.apple.com.
[group('release')]
notarize: export-app
    #!/usr/bin/env zsh
    set -o pipefail
    ditto -c -k --keepParent "{{ export_dir }}/utt.app" "{{ export_dir }}/utt.zip"
    xcrun notarytool submit "{{ export_dir }}/utt.zip" \
        --keychain-profile utt-notary --wait
    xcrun stapler staple "{{ export_dir }}/utt.app"
    xcrun stapler validate "{{ export_dir }}/utt.app"

# Writes the private key to the login keychain and prints the public one.

# BACK THE PRIVATE KEY UP. Lose it and every installed copy is unupdatable forever.
[group('release')]
sparkle-keys:
    #!/usr/bin/env zsh
    bin=$(find .build -name generate_keys -type f -perm -111 2>/dev/null | head -1)
    if [[ -z "$bin" ]]; then
        echo "error: generate_keys not built yet — run 'just build' first" >&2
        exit 1
    fi
    "$bin"
    echo ''
    echo 'Put the printed key in Utt/Resources/Info.plist as SUPublicEDKey.'

# Signs the notarized zip and updates the appcast. Needs SUFeedURL set first.
[group('release')]
appcast:
    #!/usr/bin/env zsh
    bin=$(find .build -name generate_appcast -type f -perm -111 2>/dev/null | head -1)
    if [[ -z "$bin" ]]; then
        echo "error: generate_appcast not built yet — run 'just build' first" >&2
        exit 1
    fi
    "$bin" "{{ export_dir }}"
    echo "appcast written to {{ export_dir }}/appcast.xml — upload it to SUFeedURL"

[group('cleanup')]
clean:
    rm -rf .build Utt.xcodeproj "{{ archive_path }}" "{{ export_dir }}"
    cd UttCore && swift package clean

[group('docs')]
claude-tree:
    atlas tree

# Regenerates docs/dot-matrix-preview.html from DotMatrix.patterns (then open it).
[group('docs')]
dot-matrix-preview:
    python3 tools/dot-matrix-preview.py
    open docs/dot-matrix-preview.html

# Redraw the app icon from DotMatrix.patterns[0] and Palette. Commit the pngs —

# the build reads the asset catalog, not this script.
[group('design')]
icon:
    python3 tools/make-app-icon.py

# Pin the recording overlay on screen and hot-reload overlay.json as you edit it.
# The app writes the file with its current defaults if it is missing, then re-reads

# it every 0.5s. Ctrl-C to stop. panelSize is the one value that needs a relaunch.
[group('design')]
overlay-preview: build
    #!/usr/bin/env zsh
    set -euo pipefail
    style="$HOME/Library/Application Support/dev.jurrejan.utt/overlay.json"
    pkill -x utt 2>/dev/null || true
    while pgrep -x utt >/dev/null; do sleep 0.2; done
    UTT_OVERLAY_DEBUG=1 "{{ built }}/Contents/MacOS/utt" &
    app=$!
    while [[ ! -f "$style" ]]; do sleep 0.2; done
    open -e "$style"
    echo "editing $style — the overlay follows every save"
    wait $app
