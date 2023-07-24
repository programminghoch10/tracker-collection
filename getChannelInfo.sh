#!/bin/bash

set -e

[ -f "token.txt" ] && BOT_TOKEN="$(cat token.txt)"
[ -z "$BOT_TOKEN" ] && echo "Missing bot token!" && exit 1
CHAT_ID="$1"
[ -z "$CHAT_ID" ] && echo "Missing chat id!" && exit 1
FORMAT=cat
[ -n "$(command -v jq)" ] && FORMAT="jq ."

curl -s --data "chat_id=$CHAT_ID" 'https://api.telegram.org/bot'$BOT_TOKEN'/getChat' | $FORMAT
echo
