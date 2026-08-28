set shell := ["zsh", "-uo", "pipefail", "-c"]
set unstable := true

# Developer ID Application. Hardcoded on purpose — see the note in project.yml.

identity := "72B6E55BE646D0664EF83C986B55B8F6D58BC2B6"
team := "KA6433FU8U"
built := ".build/Build/Products/Debug/utt.app"
built_release := ".build/Build/Products/Release/utt.app"
archive_path := "release/utt.xcarchive"
export_dir := "release/export"
export_options := "release/ExportOptions.plist"

# project.yml is the one place the version is written; everything downstream —
# the disk image's name, the appcast, the download link — reads it from here, so
# a shipped file can always be traced back to a build.

version := `sed -n 's/.*MARKETING_VERSION: *"\(.*\)".*/\1/p' project.yml | head -1`
dmg_path := "release/utt-" + version + ".dmg"

# Sparkle's appcast keeps every version it can still see, so the zip is named per
# version too — an overwritten utt.zip would silently rewrite an old update.

zip_path := export_dir + "/utt-" + version + ".zip"

# Kept across releases, unlike export_dir: the appcast generator needs the previous
# feed and its archives next to each other to carry old entries forward.

appcast_dir := "release/appcast"
repo_url := "https://github.com/doublej/utt"
releases_url := repo_url + "/releases"

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
    if ! security find-identity -p codesigning 2>/dev/null | grep -q "{{ identity }}"; then
        echo "error: signing identity {{ identity }} not found in the login keychain" >&2
        echo "       restore it from the Developer ID .p12 backup — a reissued cert resets every TCC grant" >&2
        exit 1
    fi

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
    @echo '→ Raycast extension...'
    just raycast-check

# The Raycast extension is plain TypeScript against the same JSON files the app
# reads, so it needs no Xcode and nothing from the build above.

[group('raycast')]
raycast-check:
    #!/usr/bin/env zsh
    set -o pipefail
    cd raycast
    [[ -d node_modules ]] || bun install
    bunx tsc --noEmit -p tsconfig.json
    bun test

# Loads the extension into Raycast and reloads it on every save. Leave it running.

[group('raycast')]
raycast-dev:
    cd raycast && bunx ray develop

# Everything below ships builds to other people. `just dmg` is the whole chain;
# the recipes it depends on are listed separately because each one is worth
# running alone when something in it fails.

[group('release')]
archive: generate
    #!/usr/bin/env zsh
    set -o pipefail
    rm -rf "{{ archive_path }}"
    xcodebuild {{ xcflags }} -scheme Utt -configuration Release \
        -archivePath "{{ archive_path }}" archive 2>&1 \
        | { command -v xcbeautify >/dev/null && xcbeautify --quiet || cat }

# The version moves here and nowhere else: MARKETING_VERSION, the build number
# Sparkle orders updates by, and the vX.Y.Z tag, in one commit behind the gate.
# The part is read off the commits since the last tag — pass major|minor|patch
# to overrule it.

# Bump, commit and tag the version behind the quality gate.
[group('release')]
bump part="": check
    python3 tools/bump-version.py {{ part }}

# What `just bump` would decide, without deciding it.
[group('release')]
next part="":
    @python3 tools/bump-version.py {{ part }} --dry-run

# Sparkle explicitly discourages --deep; the export step signs nested code correctly.
[group('release')]
export-app: archive
    #!/usr/bin/env zsh
    set -o pipefail
    # Written here rather than committed: release/ is gitignored, and the only
    # variable in it is the team id, which the identity above already pins.
    mkdir -p "$(dirname "{{ export_options }}")"
    rm -f "{{ export_options }}"
    plutil -create xml1 "{{ export_options }}"
    plutil -insert method -string developer-id "{{ export_options }}"
    plutil -insert teamID -string {{ team }} "{{ export_options }}"
    plutil -insert signingStyle -string manual "{{ export_options }}"
    plutil -insert signingCertificate -string 'Developer ID Application' "{{ export_options }}"
    rm -rf "{{ export_dir }}"
    xcodebuild -exportArchive -archivePath "{{ archive_path }}" \
        -exportOptionsPlist "{{ export_options }}" -exportPath "{{ export_dir }}"

# Requires `xcrun notarytool store-credentials utt-notary` once, with an

# app-specific password from appleid.apple.com.
[group('release')]
notarize: export-app
    #!/usr/bin/env zsh
    set -o pipefail
    ditto -c -k --keepParent "{{ export_dir }}/utt.app" "{{ zip_path }}"
    xcrun notarytool submit "{{ zip_path }}" \
        --keychain-profile utt-notary --wait
    xcrun stapler staple "{{ export_dir }}/utt.app"
    xcrun stapler validate "{{ export_dir }}/utt.app"

# The image is signed and notarized in its own right: Gatekeeper checks the
# container before anything is copied out of it, so an unsigned .dmg around a
# notarized app still warns on open.

# Drag-to-Applications disk image — the artifact to publish.
[group('release')]
dmg: notarize
    #!/usr/bin/env zsh
    set -euo pipefail
    staging=$(mktemp -d)
    trap 'rm -rf "$staging"' EXIT
    # ditto, not cp: it keeps the bundle's signature and stapled ticket intact.
    ditto "{{ export_dir }}/utt.app" "$staging/utt.app"
    ln -s /Applications "$staging/Applications"
    rm -f "{{ dmg_path }}"
    hdiutil create -volname utt -srcfolder "$staging" -ov -format UDZO -quiet "{{ dmg_path }}"
    codesign --force --sign {{ identity }} --timestamp "{{ dmg_path }}"
    xcrun notarytool submit "{{ dmg_path }}" --keychain-profile utt-notary --wait
    xcrun stapler staple "{{ dmg_path }}"
    xcrun stapler validate "{{ dmg_path }}"
    echo "→ {{ dmg_path }}  $(du -h "{{ dmg_path }}" | cut -f1)"

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

# Signs the notarized zip and rewrites the committed appcast.
#
# The archives live in their own directory rather than in `release/export`, which
# `export-app` wipes: generate_appcast carries the *previous* entries across from the
# appcast it finds next to the archives, and a wiped directory would silently publish
# a feed with only the newest version in it. --download-url-prefix applies to new
# items only, so each entry keeps the release tag it was actually uploaded under.

[group('release')]
appcast:
    #!/usr/bin/env zsh
    set -euo pipefail
    bin=$(find .build -name generate_appcast -type f -perm -111 2>/dev/null | head -1)
    if [[ -z "$bin" ]]; then
        echo "error: generate_appcast not built yet — run 'just build' first" >&2
        exit 1
    fi
    mkdir -p "{{ appcast_dir }}"
    cp "{{ zip_path }}" "{{ appcast_dir }}/"
    # Same basename as the archive: that is how generate_appcast finds the release
    # notes for an item.
    if [[ -f "docs/RELEASE-{{ version }}.md" ]]; then
        cp "docs/RELEASE-{{ version }}.md" "{{ appcast_dir }}/utt-{{ version }}.md"
    else
        echo "warn: no docs/RELEASE-{{ version }}.md — the update will show no notes" >&2
    fi
    # --embed-release-notes: without it the notes become a *link*, and the URL is
    # derived from SUFeedURL's directory — so Sparkle would fetch the notes from
    # the repo root, where they are not committed, and show an empty pane.
    # --maximum-deltas 0: a delta is a separate file that would have to be uploaded
    # alongside the zip, and an advertised delta that 404s fails the update outright.
    # --maximum-versions 1: every zip lives on its own release, so its download URL
    # carries its own tag — but generate_appcast rewrites *every* item's enclosure
    # with the prefix of the run that touched it, which pointed 0.5.0 at v0.5.1's
    # release. One item cannot go stale. Sparkle only ever offers the newest anyway.
    # ponytail: raise this the day a release lifts LSMinimumSystemVersion — an older
    # branch point has to stay in the feed, and its URL then has to be pinned by hand.
    "$bin" --download-url-prefix "{{ releases_url }}/download/v{{ version }}/" \
        --link "{{ repo_url }}" \
        --full-release-notes-url "{{ releases_url }}" \
        --embed-release-notes \
        --maximum-deltas 0 \
        --maximum-versions 1 \
        "{{ appcast_dir }}"
    cp "{{ appcast_dir }}/appcast.xml" appcast.xml
    echo "→ appcast.xml rewritten — commit and push it, it *is* the feed"

# Ship it: push the tag, publish the GitHub release, then the feed that points at it.
#
# The appcast is committed last on purpose. It is the only thing installed copies
# read, so it must never name a download that is not on the release yet.

[group('release')]
publish: dmg
    #!/usr/bin/env zsh
    set -euo pipefail
    tag="v{{ version }}"
    git rev-parse "$tag" >/dev/null 2>&1 \
        || { echo "error: no tag $tag — run 'just bump' first" >&2; exit 1; }
    notes="docs/RELEASE-{{ version }}.md"
    [[ -f "$notes" ]] || { echo "error: $notes is missing" >&2; exit 1; }
    git push --follow-tags
    gh release create "$tag" --title "utt {{ version }}" --notes-file "$notes" \
        "{{ dmg_path }}" "{{ zip_path }}"
    just appcast
    git add appcast.xml
    git commit -m "release: appcast for {{ version }}"
    git push
    echo "→ utt {{ version }} published; the feed now offers it"

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

# Redraw the app icon from DotMatrix.patterns[0] and Palette. Commit the result —

# the build reads Utt/Resources/AppIcon.icon, not this script.
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

# Pull upstream cookiecutter-template updates. Report-only without flags; --diffs / --apply.
[group('setup')]
update-scaffold *ARGS:
    #!/usr/bin/env zsh
    set -euo pipefail
    repo="${COOKIECUTTER_TEMPLATES:-}"
    if [[ -z "$repo" && -f .template-meta.json ]]; then
        repo=$(python3 -c "import json; print(json.load(open('.template-meta.json'))['template_source']['path'])" 2>/dev/null || true)
    fi
    if [[ -z "$repo" || ! -d "$repo" ]]; then
        echo "error: cookiecutter-templates repo not found — set \$COOKIECUTTER_TEMPLATES or fix template_source.path in .template-meta.json" >&2
        exit 1
    fi
    python3 "$repo/tools/update_scaffold.py" {{ ARGS }}
