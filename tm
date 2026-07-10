#!/usr/bin/env bash

# Simple script for adding torrents to `transmission` via magnet links and
# torrent files.
#
# The `transmission-add` script is an external Python tool that can be used to
# add magnet links, assign labels to torrents, and move torrent files to
# different locations.

set -eou pipefail

PROG=$(basename "$0")
CMD="transmission-daemon"
declare -a DEPS=(tm-add tremc)

function _usage {
    cat <<-_EOF
usage: $PROG [options]

options:
    -a, add         Add torrent by magnet link
    -s, start       Start daemon
    -k, kill        Stop daemon
    -x, tremc       Run tremc
_EOF
    exit
}

function _logme {
    printf "%s: %s\n" "$PROG" "$*"
}

for dep in "${DEPS[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
        _logme "'$dep' not found"
        exit 1
    fi
done

function _notify {
    local notify_args
    local mesg="<b>$1</b>"
    declare -a notify_args=(--replace-id="888" --icon="transmission" "${PROG:-"no-name"}")
    notify-send "${notify_args[@]}" "$mesg"
}

function is_running {
    if ! pgrep -f "$CMD" &>/dev/null; then
        return 1
    fi

    return 0
}

function _add_magnet {
    local magnet="$1"
    local msg="torrent added"

    if [[ -z "$magnet" ]]; then
        _logme "you must provide a magnet link"
        exit 1
    fi

    tm-add "$magnet" && notify-send "$msg"
    _logme "$msg"
}

function _add_torrent {
    local torrent="$1"
    if ! is_running; then
        _logme "$CMD not running"
        _usage
    fi

    if [[ "$torrent" =~ ^magnet: ]]; then
        _add_magnet "$torrent"
        return
    fi

    if [[ ! -e "$torrent" ]]; then
        return
    fi

    local mesg
    if tremc "$torrent"; then
        mesg="torrent <i>$(basename "$torrent")</i> added"
    else
        mesg="torrent not added"
    fi

    _notify "$mesg"
    return
}

function _stop {
    pkill -f "$CMD"
    pkill -RTMIN+12 dwmblocks
}

function _start {
    setsid -f "$CMD"
}

function main {
    local subcommand="${1:-}"
    local magnet="${2:-$subcommand}"

    case "$subcommand" in
    -s | start) _start && echo "$PROG: $CMD started" ;;
    -k | kill) _stop && echo "$PROG: stopped" ;;
    -a | add) _add_torrent "$magnet" ;;
    -r | restart) _stop && _start && _notify "$CMD restarted" ;;
    -h | help) shift && _usage ;;
    -x | tremc) tremc -X ;;
    *) tremc -X ;;
    esac

    pkill -RTMIN+12 dwmblocks
}

main "$@"
