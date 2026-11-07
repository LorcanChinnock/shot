#!/bin/sh
# Syncs Resources/Localizable.xcstrings with the strings the last Debug build extracted (SWIFT_EMIT_LOC_STRINGS in
# Config/Shared.xcconfig) from the Shot and ShotCore targets: adds new ones
# and drops ones the source no longer uses. --check changes nothing and fails when the catalog is out of date, so a
# string can't ship without an entry to translate.
set -eu
cd "$(dirname "$0")/.."

check=false
[ "${1:-}" = --check ] && check=true
catalog=Resources/Localizable.xcstrings
intermediates="${DERIVED_DATA:-build/DerivedData}/Build/Intermediates.noindex/Shot.build/Debug"
if ! ls "$intermediates"/Shot.build/Objects-normal/*/*.stringsdata >/dev/null 2>&1; then
    echo "No extracted strings in $intermediates; run make build first." >&2
    exit 1
fi

# A deleted or renamed source file leaves its old .stringsdata behind, so take only those whose source still exists.
# Each architecture built has its own copy, so take one per file.
set --
seen=" "
for data in "$intermediates"/Shot.build/Objects-normal/*/*.stringsdata "$intermediates"/ShotCore.build/Objects-normal/*/*.stringsdata; do
    source=$(plutil -extract source raw -o - "$data")
    case "$seen" in *" $source "*) continue ;; esac
    seen="$seen$source "
    if [ -f "$source" ]; then
        set -- "$@" --stringsdata "$data"
    fi
done

# sync only takes strings from the table named like the catalog, so the copy keeps its name.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$catalog" "$work/Localizable.xcstrings"
xcrun xcstringstool sync "$work/Localizable.xcstrings" "$@"

if ! $check; then
    cp "$work/Localizable.xcstrings" "$catalog"
    exit 0
fi

if ! cmp -s "$catalog" "$work/Localizable.xcstrings"; then
    echo "$catalog is out of date; run make strings and commit it. Strings added (>) and dropped (<):"
    xcrun xcstringstool print "$catalog" | sort > "$work/before"
    xcrun xcstringstool print "$work/Localizable.xcstrings" | sort > "$work/after"
    diff "$work/before" "$work/after" || true
    exit 1
fi

# sync keeps a string the source dropped when it has translations, marked stale.
stale=$(jq -r '.strings | to_entries[] | select(.value.extractionState == "stale") | .key' "$catalog")
if [ -n "$stale" ]; then
    echo "$catalog has strings the app no longer uses; delete these, which it marks stale:"
    echo "$stale"
    exit 1
fi
