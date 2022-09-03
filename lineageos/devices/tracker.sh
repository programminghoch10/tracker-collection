#!/bin/bash

LINEAGEOS_BUILD_TARGETS="https://raw.githubusercontent.com/LineageOS/hudson/master/lineage-build-targets"
LINEAGEOS_DEVICES="https://raw.githubusercontent.com/LineageOS/hudson/master/updater/devices.json"
LINEAGEOS_BUILDCONFIG_GENERATOR="https://raw.githubusercontent.com/lineageos-infra/build-config/main/android/generator.py"
LINEAGEOS_BUILDCONFIG_PYTHON="python2.7"
LINEAGEOS_API_URL="https://download.lineageos.org/api/v1/%s/nightly/*"
LINEAGEOS_WIKI_URL="https://wiki.lineageos.org/devices/%s"

DATADIR="trackdata"
DATABRANCH="trackdata"
BUILDTARGETSFILE="buildtargets"
DEVICESFILE="devices.json"
BUILDCONFIGGENERATORFILE="$(basename $LINEAGEOS_BUILDCONFIG_GENERATOR)"

CHAT_ID="-1001161392252"

WORKDIR=$(dirname $(readlink -f "$0"))
cd "$WORKDIR"
source ../../framework.sh

for cmd in git curl jq numfmt sed cut $LINEAGEOS_BUILDCONFIG_PYTHON; do
    [ -z "$(command -v $cmd)" ] && echo "Missing command $cmd" && exit 1
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
    git push origin trackdata
    cd "$PREVWD"
}

# acquire latest device list
curl -s "$LINEAGEOS_BUILD_TARGETS" | sed '/^#/d' | sed '/^\s*$/d' > "$DATADIR"/"$BUILDTARGETSFILE"
saveTrackDataFile "$BUILDTARGETSFILE" "Update build targets"
curl -s "$LINEAGEOS_DEVICES" | jq '.' > "$DATADIR"/"$DEVICESFILE"
saveTrackDataFile "$DEVICESFILE" "Update devices"

BUILDTARGETSLIST=$(cat "$DATADIR"/"$BUILDTARGETSFILE" | cut -d' ' -f 1)

processDevice() {
    DEVICE="$1"
    FORCE="$2"
    echo "Processing $DEVICE"
    [ ! -d "$DATADIR"/devices ] && mkdir "$DATADIR"/devices
    [ ! -f "$DATADIR"/devices/"$DEVICE".json ] && echo "{\"datetime\": 0}" > "$DATADIR"/devices/"$DEVICE".json
    [ -z "$FORCE" ] && {
        LASTBUILDDATE=$(cat "$DATADIR"/devices/"$DEVICE".json | jq -r '."datetime"')
        TODAY=$(date -u +%s)
        LASTWEEK=$(($TODAY - (60 * 60 * 24 * 7) ))
        [ "$LASTBUILDDATE" -gt "$LASTWEEK" ] && echo "Already checked $DEVICE this week" && return
    }
    printf -v DEVICE_API_URL "$LINEAGEOS_API_URL" "$DEVICE"
    LATEST=$(curl -s "$DEVICE_API_URL" | jq '."response"[-1]')
    echo "$LATEST"
    LATESTTIME=$(echo "$LATEST" | jq '."datetime"')
    SAVEDTIME=$(cat "$DATADIR"/devices/"$DEVICE".json | jq '."datetime"')
    [ $LATESTTIME -le $SAVEDTIME ] && echo "No new update for $DEVICE found!" && return
    echo "New update for $DEVICE found!"
    echo "$LATEST" > "$DATADIR"/devices/"$DEVICE".json
    sendDeviceUpdateMessage "$DEVICE"
    saveTrackDataFile devices/"$DEVICE".json "Process update for $DEVICE"
}

sendDeviceUpdateMessage() {
    DEVICECODENAME="$1"
    JSON="$DATADIR"/devices/"$DEVICE".json
    VERSION=$(jq -r '."version"' "$JSON")
    DOWNLOADURL=$(jq -r '."url"' "$JSON")
    DOWNLOADSHA=$(curl -s "$DOWNLOADURL?sha256" | cut -d' ' -f 1)
    DEVICEOEM=$(jq -r '.[] | select(."model"=="'$DEVICECODENAME'") | .oem' "$DATADIR"/"$DEVICESFILE")
    DEVICENAME=$(jq -r '.[] | select(."model"=="'$DEVICECODENAME'") | .name' "$DATADIR"/"$DEVICESFILE")
    ROMTYPE=$(jq -r '."romtype"' "$JSON")
    SIZE=$(jq -r '."size"' "$JSON" | numfmt --to=si --suffix=B)
    DATE=$(date -u -d @$(jq -r '."datetime"' "$JSON") +%Y/%m/%d)
    printf -v WIKIURL "$LINEAGEOS_WIKI_URL" "$DEVICECODENAME"

    # if a device name starts with the manufacturer we omit it
    DEVICENAME=$(echo "$DEVICENAME" | sed "s|^$DEVICEOEM ||g")

    # escape sed replacement strings
    DEVICECODENAME=$(sed 's/[&/\]/\\&/g' <<< "$DEVICECODENAME")
    VERSION=$(sed 's/[&/\]/\\&/g' <<< "$VERSION")
    DOWNLOADURL=$(sed 's/[&/\]/\\&/g' <<< "$DOWNLOADURL")
    DOWNLOADSHA=$(sed 's/[&/\]/\\&/g' <<< "$DOWNLOADSHA")
    DEVICEOEM=$(sed 's/[&/\]/\\&/g' <<< "$DEVICEOEM")
    DEVICENAME=$(sed 's/[&/\]/\\&/g' <<< "$DEVICENAME")
    ROMTYPE=$(sed 's/[&/\]/\\&/g' <<< "$ROMTYPE")
    SIZE=$(sed 's/[&/\]/\\&/g' <<< "$SIZE")
    DATE=$(sed 's/[&/\]/\\&/g' <<< "$DATE")
    WIKIURL=$(sed 's/[&/\]/\\&/g' <<< "$WIKIURL")

    MSG=$(cat message.html)
    MSG=$(sed "s|\$DEVICECODENAME|$DEVICECODENAME|g" <<< "$MSG")
    MSG=$(sed "s|\$VERSION|$VERSION|g" <<< "$MSG")
    MSG=$(sed "s|\$DOWNLOADURL|$DOWNLOADURL|g" <<< "$MSG")
    MSG=$(sed "s|\$DOWNLOADSHA|$DOWNLOADSHA|g" <<< "$MSG")
    MSG=$(sed "s|\$DEVICEOEM|$DEVICEOEM|g" <<< "$MSG")
    MSG=$(sed "s|\$DEVICENAME|$DEVICENAME|g" <<< "$MSG")
    MSG=$(sed "s|\$ROMTYPE|$ROMTYPE|g" <<< "$MSG")
    MSG=$(sed "s|\$SIZE|$SIZE|g" <<< "$MSG")
    MSG=$(sed "s|\$DATE|$DATE|g" <<< "$MSG")
    MSG=$(sed "s|\$WIKIURL|$WIKIURL|g" <<< "$MSG")
    KEYBOARD=$(cat message-keyboard.json)
    KEYBOARD=$(sed "s|\$DEVICECODENAME|$DEVICECODENAME|g" <<< "$KEYBOARD")
    KEYBOARD=$(sed "s|\$VERSION|$VERSION|g" <<< "$KEYBOARD")
    KEYBOARD=$(sed "s|\$DOWNLOADURL|$DOWNLOADURL|g" <<< "$KEYBOARD")
    KEYBOARD=$(sed "s|\$DOWNLOADSHA|$DOWNLOADSHA|g" <<< "$KEYBOARD")
    KEYBOARD=$(sed "s|\$DEVICEOEM|$DEVICEOEM|g" <<< "$KEYBOARD")
    KEYBOARD=$(sed "s|\$DEVICENAME|$DEVICENAME|g" <<< "$KEYBOARD")
    KEYBOARD=$(sed "s|\$ROMTYPE|$ROMTYPE|g" <<< "$KEYBOARD")
    KEYBOARD=$(sed "s|\$SIZE|$SIZE|g" <<< "$KEYBOARD")
    KEYBOARD=$(sed "s|\$DATE|$DATE|g" <<< "$KEYBOARD")
    KEYBOARD=$(sed "s|\$WIKIURL|$WIKIURL|g" <<< "$KEYBOARD")
    sendMessage "$MSG" "$KEYBOARD" || return 1
}

case "$CHECKTYPE" in
    "full")
        echo "Start process all devices"
        for DEVICE in $BUILDTARGETSLIST; do
            processDevice "$DEVICE" y
        done
        ;;
    "nightly")
        curl "$LINEAGEOS_BUILDCONFIG_GENERATOR" | sed -e 's|^import yaml$||g' -e 's|yaml.dump(\(.*\))|\1|g' > "$DATADIR"/"$BUILDCONFIGGENERATORFILE"
        saveTrackDataFile "$BUILDCONFIGGENERATORFILE" "Update device generator"
        TARGETS_TODAY=$($LINEAGEOS_BUILDCONFIG_PYTHON "$DATADIR"/"$BUILDCONFIGGENERATORFILE" < "$DATADIR"/"$BUILDTARGETSFILE" | sed "s|'|\"|g" | jq -r '."steps" | map(."build"."env"."DEVICE") | .[]')
        for DEVICE in $TARGETS_TODAY; do
            processDevice "$DEVICE"
        done
        ;;
    *)
        echo "Unrecognized checktype $CHECKTYPE"
        exit 1
esac
