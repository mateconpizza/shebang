#!/usr/bin/env bash

PROG="${0##*/}"
TITLE="📱 Find my phone..."
MESG="You found me!!!"
RETRY_SEG=30
EXPIRE_SEG=900

# shellcheck source=/dev/null
[[ -f "${PRIVATE_ROOT:-}/pushover.sh" ]] && . "$PRIVATE_ROOT/pushover.sh"

function _notify {
    local mesg="<b>$1</b>"
    notify-send -i "preferences-system-notifications" "${PROG^^}" "$mesg"
}

function _logerr {
    local msg="$1"
    _notify "$msg"
    printf "%s: %s\n" "$PROG" "$msg" >&2
    exit 1
}

[[ -z "$PUSHOVER_TOKEN" ]] && _logerr "push <i>token</i> can not be empty"
[[ -z "$PUSHOVER_USER" ]] && _logerr "push <i>user</i> can not be empty"
[[ -z "$PUSHOVER_API" ]] && _logerr "push <i>api URL</i> can not be empty"
[[ -z "$PUSHOVER_DEVICE" ]] && _logerr "push <i>device</i> can not be empty"

# The `retry` parameter specifies how often (in seconds) the Pushover servers
# will send the same notification to the user. In a situation where your user
# might be in a noisy environment or sleeping, retrying the notification (with
# sound and vibration) will help get his or her attention. This parameter must
# have a value of at least 30 seconds between retries.

# The `expire` parameter specifies how many seconds your notification will
# continue to be retried for (every retry seconds). If the notification has not
# been acknowledged in expire seconds, it will be marked as expired and will
# stop being sent to the user. Note that the notification is still shown to the
# user after it is expired, but it will not prompt the user for
# acknowledgement. This parameter must have a maximum value of at most 10800
# seconds (3 hours), though the total number of retries will be capped at 50
# regardless of the expire parameter.

curl -s \
    -F "token=${PUSHOVER_TOKEN}" \
    -F "user=${PUSHOVER_USER}" \
    -F "title=${TITLE}" \
    -F "device=${PUSHOVER_DEVICE}" \
    -F "priority=2" \
    -F "retry=$RETRY_SEG" \
    -F "expire=${EXPIRE_SEG}" \
    -F "message=${MESG}" \
    "${PUSHOVER_API}" >/dev/null

retcode=$?
if [[ "$retcode" -ne 0 ]]; then
    _logerr "failed to send notification: $retcode"
else
    _notify "Pushover notification sent"
fi
