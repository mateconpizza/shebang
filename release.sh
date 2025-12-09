#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PROG="${0##*/}"
DRY_RUN=0
READER=$(command -v glow 2>/dev/null || echo cat)
NEW_VERSION=
LAST_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")

# colors
BOLD=$(tput bold)
BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
GRAY=$(tput setaf 8)
YELLOW=$(tput setaf 3)
RESET="$(tput sgr0)"

function _usage() {
    cat <<-EOF
${BOLD}${PROG}${RESET} - Semantic version bumping and release tool

${BOLD}USAGE:${RESET}
    ${PROG} [OPTIONS] <SEGMENT>

${BOLD}OPTIONS:${RESET}
    -d, --dry-run    perform a trial run with no changes made

${BOLD}SEGMENTS:${RESET}
    release          bump to next release version (1.0.0)
    major            bump major version (2.0.0)
    minor            bump minor version (1.1.0)
    micro            bump micro/patch version (1.0.1)
    patch, fix       aliases for micro

    ${BOLD}Pre-release identifiers:${RESET}
    a, alpha         alpha pre-release (1.0.0a0)
    b, beta          beta pre-release (1.0.0b0)
    c, rc            release candidate (1.0.0rc0)
    pre, preview     aliases for rc

    ${BOLD}Post-release identifiers:${RESET}
    r, rev, post     post-release revision (1.0.0.post0)
    dev              development release (1.0.0.dev0)

${BOLD}CURRENT VERSION:${RESET}
    ${LAST_VERSION}

${BOLD}EXAMPLES:${RESET}
    ${PROG} minor              # 1.0.0 → 1.1.0
    ${PROG} patch              # 1.0.0 → 1.0.1
    ${PROG} -d major           # dry run: show what 2.0.0 would be
    ${PROG} beta               # 1.0.0 → 1.0.0b0
EOF
}

while getopts "dh" flag; do
    case "$flag" in
    d)
        shift $((OPTIND - 1))
        DRY_RUN=1
        printf -- '%s\n' "${BOLD}${YELLOW}[DRY RUN MODE ON]${RESET}"
        ;;
    h)
        _usage
        exit 1
        ;;
    *)
        echo "Usage: $0 [-d|--dry-run]" >&2
        exit 1
        ;;
    esac
done

SEGMENT=${1:-}

function run {
    if ((DRY_RUN)); then
        printf "${BOLD}${YELLOW}[DRY RUN]${RESET} %s\n" "$*" >&2
        return 0
    fi

    "$@"
}

[[ "$SEGMENT" == '-h' ]] && _usage && exit

if [[ $LAST_VERSION =~ ^(v)?([0-9]+\.[0-9]+\.[0-9]+)(\.[a-z]+[0-9]+)?$ ]]; then
    prefix="${BASH_REMATCH[1]:-v}" # 'v' or empty
    base="${BASH_REMATCH[2]}"      # 0.1.0
    suffix="${BASH_REMATCH[3]}"    # .dev0 (optional)
else
    echo "invalid version ${LAST_VERSION}"
    exit 1
fi

function confirm {
    local question="${1:-continue?}"
    read -n 1 -r -p "${BOLD}${YELLOW}>${RESET} ${question} ${GRAY}[y/N]:${RESET} "
    echo
    [[ -z "$REPLY" || "$REPLY" != "y" ]] && return 1
    return 0
}

[[ -z "$SEGMENT" ]] && {
    _usage
    exit 1
}

# extract major/minor/patch
IFS='.' read -r major minor patch <<<"${LAST_VERSION//[!0-9.]/}"
major=${major:-0}
minor=${minor:-0}
patch=${patch:-0}
# echo "major: ${major}"
# echo "minor: ${minor}"
# echo "patch: ${patch}"

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
    NEW_VERSION="${prefix}${major}.$((minor + 1)).0"
    ;;
major)
    IFS='.' read -r major minor patch <<<"${base#v}"
    NEW_VERSION="${prefix}$((major + 1)).0.0"
    ;;
a | alpha)
    NEW_VERSION="${prefix}${major}.${minor}.${patch}a0"
    ;;
b | beta)
    NEW_VERSION="${prefix}${major}.${minor}.${patch}b0"
    ;;
c | rc | pre | preview)
    NEW_VERSION="${prefix}${major}.${minor}.${patch}rc0"
    ;;
r | rev | post)
    NEW_VERSION="${prefix}${major}.${minor}.${patch}.post0"
    ;;
dev)
    NEW_VERSION="${prefix}${major}.${minor}.${patch}.dev0"
    ;;
*)
    echo "invalid segment <${SEGMENT}>"
    echo
    _usage
    exit 1
    ;;
esac

[[ -z "$NEW_VERSION" ]] && exit 1

# create tag
## generate unreleased changelog
TEMPFILE=/tmp/$(basename "$PWD")-${NEW_VERSION}.md
trap '[[ -f "$TEMPFILE" ]] && rm -f "$TEMPFILE"' EXIT SIGTERM
git cliff --unreleased --strip all | sed '1d' >"${TEMPFILE}"
[[ -s "$TEMPFILE" ]] && "$READER" "$TEMPFILE" || echo "New version: ${NEW_VERSION}"

confirm "New ${BLUE}tag${RESET} $NEW_VERSION, continue?" || exit 1
# TODO: check if tag already exists
run git tag -a "${NEW_VERSION}" -F "${TEMPFILE}"

# generate and show tag changelog
git cliff --tag "${NEW_VERSION}" --strip all >"${TEMPFILE}"
[[ -s "$TEMPFILE" ]] && "$READER" "$TEMPFILE" || echo "New version: ${NEW_VERSION}"

confirm "New version: ${BLUE}${NEW_VERSION}${RESET} continue?" || exit 1

# git push
if ! git remote get-url origin &>/dev/null; then
    echo
    echo "${RED}err:${RESET} No 'origin' remote found. Please run:"
    echo "git remote add origin <url>"
    exit 1
fi
run git push origin "$NEW_VERSION"

# create release
confirm "${RED}Release${RESET} ${NEW_VERSION}?, continue?" || exit 1
if ! command -v gh >/dev/null; then
    echo
    echo "${RED}err:${RESET} No 'gh' command found"
    exit 1
fi

# file exists check
[[ ! -e "${TEMPFILE}" ]] && echo "${RED}err:${RESET} changelog file not found" && exit 1
# empty check
[[ ! -s "${TEMPFILE}" ]] && echo "${RED}err:${RESET} changelog empty" && exit 1

run gh release create "${NEW_VERSION}" --title "${NEW_VERSION}" --notes-file "${TEMPFILE}"
