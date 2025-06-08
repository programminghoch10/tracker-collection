#!/bin/bash

DATADIR="trackdata"
DATABRANCH="trackdata-magisk-modules"

CHAT_ID="-1002625279703"

WORKDIR=$(dirname "$(readlink -f "$0")")
cd "$WORKDIR"
source ../../framework.sh

[ -z "$(command -v unzip)" ] && echo "Missing command unzip" && exit 1

# shellcheck disable=SC2154
[ -f "$GIT_ROOT"/channel.txt ] && CHAT_ID=$(cat "$GIT_ROOT"/channel.txt)

mcurl() {
    curl \
        --silent \
        --fail \
        --location \
        "$@"
}

mecurl() {
    local url="$1"
    local file="$2"
    mcurl \
        --etag-compare "$file".etag \
        --etag-save "$file".etag \
        --output "$file" \
        "$url"
}

getprop() {
    local name="$1"
    grep "^$name=" | cut -d'=' -f2 | firstline
}

saveTrackDataFiles() {
    local COMMITMESSAGE="$1"
    shift
    pushd "$DATADIR"
    git add "$@"
    git commit -m "$COMMITMESSAGE" || true
    git push origin "$DATABRANCH"
    popd
}

processModule() {
    local config="$1"
    [ -z "$config" ] && echo missing config >&2 && return 1
    id=$(getCSV 1 <<< "$config")
    [ -z "$id" ] && echo missing id >&2 && return 1
    [ "$id" != "$(convertToTelegramTag <<< "$id")" ] && echo id is not in supported format >&2 && return 1
    updatejsonurl=$(getCSV 2 <<< "$config")
    [ -z "$updatejsonurl" ] && echo missing update json url >&2 && return 1
    repourl=$(getCSV 3 <<< "$config")
    [ -z "$repourl" ] && echo missing repo url >&2 && return 1
    local includechangelog
    includechangelog="$(getCSV 4 <<< "$config")"
    ! isBooleanValue "$includechangelog" && echo invalid input for includechangelog >&2 && return 1

    mkdir -p "$DATADIR"/"$id"
    [ ! -f "$DATADIR"/"$id"/update.json ] && echo '{"versionCode":0}' > "$DATADIR"/"$id"/update.json

    prevversioncode=$(jq -r '.versionCode' "$DATADIR"/"$id"/update.json)
    mecurl "$updatejsonurl" "$DATADIR"/"$id"/update.json || return 0
    newversioncode=$(jq -r '.versionCode' "$DATADIR"/"$id"/update.json)

    if [ "$newversioncode" -gt "$prevversioncode" ]; then
        zipurl=$(jq -r '.zipUrl' "$DATADIR"/"$id"/update.json)
        changelogurl=$(jq -r '.changelog' "$DATADIR"/"$id"/update.json)

        mcurl --output "$DATADIR"/"$id"/module.zip "$zipurl" || return 0
        unzip "$DATADIR"/"$id"/module.zip module.prop
        rm "$DATADIR"/"$id"/module.zip
        mv module.prop "$DATADIR"/"$id"/module.prop

        for prop in id name description version versionCode author updateJson; do
            declare -g "module$prop"="$(getprop "$prop" < "$DATADIR"/"$id"/module.prop)"
        done

        changelog_formatted=""
        if $includechangelog; then
            changelog=$(mcurl "$changelogurl") || true
            [ -n "$changelog" ] && changelog_formatted=$(envsubstadvanced < changelog.html | stripEmptyLines)
        fi

        MSG="$(envsubstadvanced < message.html | stripEmptyLines)"
        KEYBOARD="$(envsubstadvanced < message-keyboard.json)"
        sendMessage "$MSG" "$KEYBOARD"
    fi

    saveTrackDataFiles "Update $id" "$id"
}

CONFIG="$(stripCommentLines < config.csv | stripEmptyLines)"
for config in $CONFIG; do
    processModule "$config"
done
