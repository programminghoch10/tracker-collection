#!/bin/bash

LINEAGEOS_BUILD_TARGETS="https://raw.githubusercontent.com/LineageOS/hudson/main/lineage-build-targets"
LINEAGEOS_DEVICES="https://raw.githubusercontent.com/LineageOS/hudson/main/updater/devices.json"
LINEAGEOS_BUILDCONFIG_GENERATOR="https://raw.githubusercontent.com/lineageos-infra/build-config/main/android/generator.py"
LINEAGEOS_API_URL="https://download.lineageos.org/api/v2/devices/%s/builds"
LINEAGEOS_WIKI_URL="https://wiki.lineageos.org/devices/%s"

DATADIR="trackdata"
DATABRANCH="trackdata-lineageos-devices"
BUILDTARGETSFILE="buildtargets"
DEVICESFILE="devices.json"
BUILDCONFIGGENERATORFILE="$(basename $LINEAGEOS_BUILDCONFIG_GENERATOR)"

CHAT_ID="-1001161392252"

WORKDIR=$(dirname "$(readlink -f "$0")")
cd "$WORKDIR"
source ../../framework.sh

for cmd in git curl jq numfmt sed cut python; do
    [ -z "$(command -v "$cmd")" ] && echo "Missing command $cmd" && exit 1
done

# full - check all devices
# nightly - check only devices queued to build today
CHECKTYPE="$1"
[ -z "$CHECKTYPE" ] && CHECKTYPE="full"

saveTrackDataFile() {
    PREVWD="$(pwd)"
    FILE="$1"
    COMMITMESSAGE="$2"
    cd "$DATADIR"
    git add "$FILE"
    git commit -m "$COMMITMESSAGE" || true
    git push origin "$DATABRANCH"
    cd "$PREVWD"
}

# acquire latest device list
curl --fail --silent "$LINEAGEOS_BUILD_TARGETS" | sed '/^#/d' | sed '/^\s*$/d' > "$DATADIR"/"$BUILDTARGETSFILE"
saveTrackDataFile "$BUILDTARGETSFILE" "Update build targets"
curl --fail --silent "$LINEAGEOS_DEVICES" | jq '.' > "$DATADIR"/"$DEVICESFILE"
saveTrackDataFile "$DEVICESFILE" "Update devices"

BUILDTARGETSLIST=$(cut -d' ' -f 1 < "$DATADIR"/"$BUILDTARGETSFILE")

processDevice() {
    DEVICE="$1"
    FORCE="$2"
    echo "Processing $DEVICE"
    [ ! -d "$DATADIR"/devices ] && mkdir "$DATADIR"/devices
    [ ! -f "$DATADIR"/devices/"$DEVICE".json ] && echo "{\"datetime\": 0}" > "$DATADIR"/devices/"$DEVICE".json
    [ -z "$FORCE" ] && {
        LASTBUILDDATE=$(jq -r '."datetime"' < "$DATADIR"/devices/"$DEVICE".json)
        TODAY=$(date -u +%s)
        LASTWEEK=$(($TODAY - (60 * 60 * 24 * 1) ))
        [ "$LASTBUILDDATE" -gt "$LASTWEEK" ] && echo "Already checked $DEVICE today" && return
    }
    printf -v DEVICE_API_URL "$LINEAGEOS_API_URL" "$DEVICE"
    LATEST="$(curl --fail --silent "$DEVICE_API_URL" | jq 'sort_by(.datetime) | .[-1]')"
    echo "$LATEST"
    [ -z "$LATEST" ] && echo "Failed to fetch latest builds for $DEVICE" && return
    [ "$LATEST" = "null" ] && echo "No builds for $DEVICE found!" && return
    LATESTTIME=$(echo "$LATEST" | jq '."datetime"')
    SAVEDTIME=$(jq '."datetime"' < "$DATADIR"/devices/"$DEVICE".json)
    [ "$LATESTTIME" -le "$SAVEDTIME" ] && echo "No new update for $DEVICE found!" && return
    echo "New update for $DEVICE found!"
    echo "$LATEST" > "$DATADIR"/devices/"$DEVICE".json
    sendDeviceUpdateMessage "$DEVICE"
    saveTrackDataFile devices/"$DEVICE".json "Process update for $DEVICE"
}

sendDeviceUpdateMessage() {
    DEVICECODENAME="$1"
    JSON="$(cat "$DATADIR"/devices/"$DEVICE".json)"
    VERSION=$(jq -r '."version"' <<< "$JSON")
    ZIPFILE="$(jq -r '."files"[0]' <<< "$JSON")"
    DOWNLOADFILENAME=$(jq -r '."filename"' <<< "$ZIPFILE")
    DOWNLOADURL=$(jq -r '."url"' <<< "$ZIPFILE")
    DOWNLOADSHA=$(jq -r '."sha256"' <<< "$ZIPFILE")
    DEVICEOEM=$(jq -r '.[] | select(."model"=="'"$DEVICECODENAME"'") | .oem' "$DATADIR"/"$DEVICESFILE")
    DEVICENAME=$(jq -r '.[] | select(."model"=="'"$DEVICECODENAME"'") | .name' "$DATADIR"/"$DEVICESFILE")
    ROMTYPE=$(jq -r '."type"' <<< "$ZIPFILE")
    SIZE=$(jq -r '."size"' <<< "$ZIPFILE" | numfmt --to=si --suffix=B)
    DATE=$(date -u -d @"$(jq -r '."datetime"' <<< "$ZIPFILE")" +%Y/%m/%d)
    printf -v WIKIURL "$LINEAGEOS_WIKI_URL" "$DEVICECODENAME"

    # if a device name starts with the manufacturer we omit it
    DEVICENAME=$(echo "$DEVICENAME" | sed "s|^$DEVICEOEM ||g")

    ADDITIONALFILES=""
    for addfilejson in $(jq --compact-output ".[\"files\"][] | select(.\"filename\" != \"$DOWNLOADFILENAME\")" <<< "$JSON"); do
        ADDFILEURL=$(jq -r '.url' <<< "$addfilejson")
        ADDFILENAME=$(jq -r '.filename' <<< "$addfilejson")
        ADDFILESIZE=$(jq -r '.size' <<< "$addfilejson" | numfmt --to=si --suffix=B)
        ADDITIONALFILES="$ADDITIONALFILES"$'\n'"$(envsubstadvanced < message-additional-file.html)"
    done
    ADDITIONALFILES="$(stripEmptyLines <<< "$ADDITIONALFILES")"

    MSG="$(envsubstadvanced < message.html | stripEmptyLines)"
    KEYBOARD="$(envsubstadvanced < message-keyboard.json)"

    sendMessage "$MSG" "$KEYBOARD" || return 1
}

case "$CHECKTYPE" in
    "full")
        echo "Start process all devices"
        for DEVICE in $BUILDTARGETSLIST; do
            processDevice "$DEVICE"
        done
        ;;
    "nightly")
        curl --silent --fail "$LINEAGEOS_BUILDCONFIG_GENERATOR" | sed -e 's|^import yaml$||g' -e 's|yaml.dump(\(.*\))|\1|g' > "$DATADIR"/"$BUILDCONFIGGENERATORFILE"
        saveTrackDataFile "$BUILDCONFIGGENERATORFILE" "Update device generator"
        TARGETS_TODAY=$(python "$DATADIR"/"$BUILDCONFIGGENERATORFILE" < "$DATADIR"/"$BUILDTARGETSFILE" | sed "s|'|\"|g" | jq -r '."steps" | map(."build"."env"."DEVICE") | .[]')
        for DEVICE in $TARGETS_TODAY; do
            processDevice "$DEVICE"
        done
        ;;
    *)
        echo "Unrecognized checktype $CHECKTYPE"
        exit 1
esac
