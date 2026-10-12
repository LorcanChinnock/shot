#!/bin/sh
# Syncs Resources/Localizable.xcstrings with the strings the last build extracted (see Package.swift): adds new ones
# and drops ones the source no longer uses. --check changes nothing and fails when the catalog is out of date, so a
# string can't ship without an entry to translate.
set -eu
cd "$(dirname "$0")/.."

check=false
[ "${1:-}" = --check ] && check=true
catalog=Resources/Localizable.xcstrings
if [ ! -d .build/stringsdata ]; then
    echo "No extracted strings in .build/stringsdata; run swift build first." >&2
    exit 1
fi

# A deleted or renamed source file leaves its old .stringsdata behind, so take only those whose source still exists.
set --
for data in .build/stringsdata/*/*.stringsdata; do
    if [ -f "$(plutil -extract source raw -o - "$data")" ]; then
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
if grep -q '"extractionState" : "stale"' "$catalog"; then
    echo "$catalog has strings the app no longer uses; delete the ones marked stale:"
    jq -r '.strings | to_entries[] | select(.value.extractionState == "stale") | .key' "$catalog"
    exit 1
fi
