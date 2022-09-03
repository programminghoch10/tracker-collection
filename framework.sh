#!/bin/bash

# global variables
GIT_USERNAME="github-actions[bot]"
GIT_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
TELEGRAM_TIMEOUT=5

set -e # exit if any command fails
#set -x # explain steps

GIT_ROOT="$(git rev-parse --show-toplevel)"

# telegram bot checks
[ -z "$BOT_TOKEN" ] && [ -f "$GIT_ROOT/token.txt" ] && BOT_TOKEN=$(cat $GIT_ROOT/token.txt)
[ -f "$GIT_ROOT/channel.txt" ] && CHAT_ID=$(cat $GIT_ROOT/channel.txt)
[ -z "$BOT_TOKEN" ] && echo "Missing Telegram Bot token!" && exit 1
[ -z "$CHAT_ID" ] && echo "Missing target telegram channel id!" && exit 1

# infrastructure checks
[ -z "$DATABRANCH" ] && echo "Missing Data Branch!" && exit 1
[ -z "$DATADIR" ] && echo "Missing Data Directory!" && exit 1
[ -z "$WORKDIR" ] && WORKDIR="$(pwd)"

# host system checks
for cmd in git curl jq; do
    [ -z "$(command -v $cmd)" ] && echo "Missing command $cmd" && exit 1
done

# push to github on script exit to not send duplicate messages
function cleanup() {
    echo "Pushing $DATABRANCH"
    cd "$WORKDIR"
    git push origin $DATABRANCH
}
trap cleanup EXIT

# prepare DATABRANCH in DATADIR for saving data
[ -z "$(git branch | grep "$DATABRANCH")" ] && git fetch origin $DATABRANCH:$DATABRANCH
[ -d "$DATADIR" ] && rm -rf "$DATADIR"
mkdir "$DATADIR"
git clone "$GIT_ROOT" "$DATADIR"
cd "$DATADIR"
git fetch origin $DATABRANCH:$DATABRANCH
git checkout $DATABRANCH
git config --local user.name "$GIT_USERNAME"
git config --local user.email "$GIT_EMAIL"
cd "$WORKDIR"

sendMessage() {
    MSG="$1"
    KEYBOARD="$2"
    echo "Sending message:"
    echo "$MSG"
    [ -n "$KEYBOARD" ] && echo "(with keyboard)"
    [ -n "$KEYBOARD" ] && KEYBOARDARGS=(--data "reply_markup=$(echo "$KEYBOARD" | jq -r tostring)")
    RES=$(curl --data-urlencode "text=$MSG" --data "chat_id=$CHAT_ID" --data "parse_mode=HTML" ${KEYBOARDARGS[@]} 'https://api.telegram.org/bot'$BOT_TOKEN'/sendMessage')
    echo $RES
    echo
    [ "$(echo "$RES" | jq .'ok')" != "true" ] && return 1
    sleep $TELEGRAM_TIMEOUT
}
