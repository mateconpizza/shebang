#!/usr/bin/env bash

set -euo pipefail

PROG="${0##*/}"
SEGMENT=${1:-}
NEW_VERSION=
LAST_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")

# colors
BOLD=$(tput bold)
BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
GRAY=$(tput setaf 8)
RESET="$(tput sgr0)"
READER=$(command -v glow 2>/dev/null || echo cat)

if [[ $LAST_VERSION =~ ^(v[0-9]+\.[0-9]+\.[0-9]+)(\.[a-z]+[0-9]+)?$ ]]; then
    base="${BASH_REMATCH[1]}"   # v0.1.0
    suffix="${BASH_REMATCH[2]}" # .dev0 (optional)
else
    echo "Invalid version ${LAST_VERSION}"
    exit 1
fi

function confirm {
    local question="${1:-continue?}"
    read -t 10 -n 1 -r -p "${question} ${GRAY}[y/N]:${RESET} "
    echo
    [[ -z "$REPLY" || "$REPLY" != "y" ]] && return 1
    return 0
}

function usage() {
    cat <<-EOF
Usage: ${PROG} <segment>

segments            new version
------------------------------
release             1.0.0
major 	            2.0.0
minor 	            1.1.0
micro,patch,fix     1.0.1
a,alpha             1.0.0a0
b,beta 	            1.0.0b0
c,rc,pre,preview    1.0.0rc0
r,rev,post          1.0.0.post0
dev 	            1.0.0.dev0

Current: ${BOLD}${LAST_VERSION}${RESET}
EOF
}

[[ -z "$SEGMENT" ]] && usage && exit 1

# extract major/minor/patch
IFS='.' read -r major minor patch <<<"${LAST_VERSION//[!0-9.]/}"
major=${major:-0}
minor=${minor:-0}
patch=${patch:-0}
echo "major: ${major}"
echo "minor: ${minor}"
echo "patch: ${patch}"

case "$SEGMENT" in
patch | micro | fix)
    if [[ -n $suffix ]]; then
        pre=${suffix%[0-9]*}
        num=${suffix##*[!0-9]}
        NEW_VERSION="${base}${pre}$((num + 1))"
    else
        IFS='.' read -r major minor patch <<<"${base#v}"
        NEW_VERSION="v${major}.${minor}.$((patch + 1))"
    fi
    ;;
release)
    NEW_VERSION="${base}" # remove suffix only
    ;;
minor)
    IFS='.' read -r major minor patch <<<"${base#v}"
    NEW_VERSION="v${major}.$((minor + 1)).0"
    ;;
major)
    IFS='.' read -r major minor patch <<<"${base#v}"
    NEW_VERSION="v$((major + 1)).0.0"
    ;;
a | alpha)
    NEW_VERSION="v${major}.${minor}.${patch}a0"
    ;;
b | beta)
    NEW_VERSION="v${major}.${minor}.${patch}b0"
    ;;
c | rc | pre | preview)
    NEW_VERSION="v${major}.${minor}.${patch}rc0"
    ;;
r | rev | post)
    NEW_VERSION="v${major}.${minor}.${patch}.post0"
    ;;
dev)
    NEW_VERSION="v${major}.${minor}.${patch}.dev0"
    ;;
*)
    echo "Invalid segment <${SEGMENT}>"
    exit 1
    ;;
esac

[[ -z "$NEW_VERSION" ]] && exit 1

# generate changelog
TEMPFILE=/tmp/$(basename "$PWD")-${NEW_VERSION}.md
trap '[[ -f "$TEMPFILE" ]] && rm -f "$TEMPFILE"' EXIT SIGTERM
git cliff --current --strip all >"${TEMPFILE}"

# show changelog
[[ -s "$TEMPFILE" ]] && "$READER" "$TEMPFILE" || echo "New version: ${NEW_VERSION}"

confirm "new ver: ${BLUE}${NEW_VERSION}${RESET} continue?" || exit 1

# create tag
confirm "- ${BLUE}tag${RESET} $NEW_VERSION, continue?" || exit 1
git tag -a "$NEW_VERSION" -m "release $NEW_VERSION"

# git push
if ! git remote get-url origin &>/dev/null; then
    echo
    echo "${RED}err:${RESET} No 'origin' remote found. Please run:"
    echo "git remote add origin <url>"
    exit 1
fi
git push origin "$NEW_VERSION"

# create release
if [[ "${SEGMENT}" == "release" ]]; then
    confirm "- ${RED}release${RESET} ${NEW_VERSION}?, continue?" || exit 1
    if ! command -v gh 2>/dev/null; then
        echo
        echo "${RED}err:${RESET} No 'gh' command found"
        exit 1
    fi
    [[ ! -s "${TEMPFILE}" ]] && echo "${RED}err:${RESET} changelog empty" && exit 1
    gh release create "${NEW_VERSION}" --title "${NEW_VERSION}" --notes-file "${TEMPFILE}"
fi
