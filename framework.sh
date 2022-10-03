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

# github api checks
[ -z "$GITHUB_TOKEN" ] && [ -f "$GIT_ROOT/githubapitoken.txt" ] && GITHUB_TOKEN="$(cat $GIT_ROOT/githubapitoken.txt)"
GITHUB_TIMEOUT=10 # 60 requests per hour => 10s per request
[ -n "$GITHUB_TOKEN" ] && GITHUB_TIMEOUT=1 # 5000 requests per hour => ~0.8s per request

# host system checks
for cmd in git curl jq envsubst; do
    [ -z "$(command -v $cmd)" ] && echo "Missing command $cmd" && exit 1
done

# push to github on script exit to not send duplicate messages
function cleanup() {
    echo "Executing EXIT handler"
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
    local MSG="$1"
    local KEYBOARD="$2"
    echo "Sending message:" >&2
    echo "$MSG" >&2
    [ -n "$KEYBOARD" ] && echo "(with keyboard)" >&2
    [ -n "$KEYBOARD" ] && local KEYBOARDARGS=(--data-urlencode "reply_markup=$(echo "$KEYBOARD" | jq -r tostring)")
    local RES=$(curl -s --data-urlencode "text=$MSG" --data "chat_id=$CHAT_ID" --data "parse_mode=HTML" ${KEYBOARDARGS[@]} 'https://api.telegram.org/bot'$BOT_TOKEN'/sendMessage')
    echo $RES
    [ "$(echo "$RES" | jq .'ok')" != "true" ] && return 1
    TELEGRAM_MESSAGE_ID="$(jq .'result'.'message_id' <<< "$RES")"
    sleep $TELEGRAM_TIMEOUT
}

sendImageMessage() {
    local IMGURL="$1"
    local MSG="$2"
    local KEYBOARD="$3"
    local KEYBOARDARGS
    echo "Sending message:" >&2
    echo "$MSG" >&2
    [ -n "$KEYBOARD" ] && echo "(with keyboard)" >&2
    [ -n "$KEYBOARD" ] && local KEYBOARDARGS=(--data-urlencode "reply_markup=$(echo "$KEYBOARD" | jq -r tostring)")
    local RES=$(curl -s --data-urlencode "photo=$IMGURL" --data-urlencode "caption=$MSG" --data "chat_id=$CHAT_ID" --data "parse_mode=HTML" ${KEYBOARDARGS[@]} 'https://api.telegram.org/bot'$BOT_TOKEN'/sendPhoto')
    echo $RES
    [ "$(echo "$RES" | jq .'ok')" != "true" ] && return 1
    TELEGRAM_MESSAGE_ID="$(jq .'result'.'message_id' <<< "$RES")"
    sleep $TELEGRAM_TIMEOUT
}

GitHubApiRequest() {
    local URL="$1"
    local CURL_ARGS=()
    [ -n "$GITHUB_TOKEN" ] && CURL_ARGS+=("-H" "Authorization: Bearer $GITHUB_TOKEN")
    curl -s -f "${CURL_ARGS[@]}" "$URL"
    sleep $GITHUB_TIMEOUT
}

envsubstadvanced() {
    local MSG="$(cat -)"
    declare -g -x $(grep -E '\$\w+' -o <<< "$MSG" | sed 's/^\$//')
    envsubst <<< "$MSG"
}
