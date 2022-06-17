#!/bin/bash
set -e

LINEAGEOS_BUILD_TARGETS="https://raw.githubusercontent.com/LineageOS/hudson/master/lineage-build-targets"
LINEAGEOS_DEVICES="https://raw.githubusercontent.com/LineageOS/hudson/master/updater/devices.json"
LINEAGEOS_API_URL="https://download.lineageos.org/api/v1/%s/nightly/*"
LINEAGEOS_WIKI_URL="https://wiki.lineageos.org/devices/%s"

DATADIR="trackdata"
DATABRANCH="trackdata"
WORKDIR="$(pwd)"
BUILDTARGETSFILE="buildtargets"
DEVICESFILE="devices.json"

CHAT_ID="-1001161392252"
TIMEOUT=5
GIT_USERNAME="github-actions[bot]"
GIT_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"

for cmd in git curl jq numfmt sed cut; do
    [ -z "$(command -v $cmd)" ] && echo "Missing command $cmd" && exit 1
done

# prepare DATABRANCH in DATADIR for saving data
[ -z "$(git branch | grep "$DATABRANCH")" ] && git fetch origin $DATABRANCH:$DATABRANCH
[ -d "$DATADIR" ] && rm -rf "$DATADIR"
mkdir "$DATADIR"
git clone . "$DATADIR"
cd "$DATADIR"
git fetch origin $DATABRANCH:$DATABRANCH
git checkout $DATABRANCH
git config --local user.name "$GIT_USERNAME"
git config --local user.email "$GIT_EMAIL"
cd "$WORKDIR"

# acquire latest device list
cd "$DATADIR"
curl -s "$LINEAGEOS_BUILD_TARGETS" | sed '/^#/d' | sed '/^\s*$/d' | cut -d' ' -f 1 > "$BUILDTARGETSFILE"
git add "$BUILDTARGETSFILE"
git commit -m "Update build targets" || true
curl -s "$LINEAGEOS_DEVICES" | jq '.' > "$DEVICESFILE"
git add "$DEVICESFILE"
git commit -m "Update devices" || true
cd "$WORKDIR"

processDevice() {
    DEVICE="$1"
    echo "Processing $DEVICE"
    printf -v DEVICE_API_URL "$LINEAGEOS_API_URL" "$DEVICE"
    LATEST=$(curl -s "$DEVICE_API_URL" | jq '."response"[-1]')
    [ ! -f "$DATADIR"/devices/"$DEVICE".json ] && echo "{\"datetime\": 0}" > "$DATADIR"/devices/"$DEVICE".json
    echo "$LATEST"
    LATESTTIME=$(echo "$LATEST" | jq '."datetime"')
    SAVEDTIME=$(cat "$DATADIR"/devices/"$DEVICE".json | jq '."datetime"')
    [ $LATESTTIME -le $SAVEDTIME ] && echo "No new update for $DEVICE found!" && return
    echo "New update for $DEVICE found!"
    echo "$LATEST" > "$DATADIR"/devices/"$DEVICE".json
    cd "$DATADIR"
    git add devices/"$DEVICE".json
    git commit -m "Process update for $DEVICE"
    git push origin trackdata
    cd "$WORKDIR"
    sendDeviceUpdateMessage "$DEVICE"
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

    MSG=$(cat message.html)
    MSG=$(echo "$MSG" | sed "s|\$DEVICECODENAME|$DEVICECODENAME|g")
    MSG=$(echo "$MSG" | sed "s|\$VERSION|$VERSION|g")
    MSG=$(echo "$MSG" | sed "s|\$DOWNLOADURL|$DOWNLOADURL|g")
    MSG=$(echo "$MSG" | sed "s|\$DOWNLOADSHA|$DOWNLOADSHA|g")
    MSG=$(echo "$MSG" | sed "s|\$DEVICEOEM|$DEVICEOEM|g")
    MSG=$(echo "$MSG" | sed "s|\$DEVICENAME|$DEVICENAME|g")
    MSG=$(echo "$MSG" | sed "s|\$ROMTYPE|$ROMTYPE|g")
    MSG=$(echo "$MSG" | sed "s|\$SIZE|$SIZE|g")
    MSG=$(echo "$MSG" | sed "s|\$DATE|$DATE|g")
    MSG=$(echo "$MSG" | sed "s|\$WIKIURL|$WIKIURL|g")
    KEYBOARD=$(cat message-keyboard.json)
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$DEVICECODENAME|$DEVICECODENAME|g")
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$VERSION|$VERSION|g")
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$DOWNLOADURL|$DOWNLOADURL|g")
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$DOWNLOADSHA|$DOWNLOADSHA|g")
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$DEVICEOEM|$DEVICEOEM|g")
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$DEVICENAME|$DEVICENAME|g")
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$ROMTYPE|$ROMTYPE|g")
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$SIZE|$SIZE|g")
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$DATE|$DATE|g")
    KEYBOARD=$(echo "$KEYBOARD" | sed "s|\$WIKIURL|$WIKIURL|g")
    sendMessage "$MSG" "$KEYBOARD"
}

sendMessage() {
    MSG="$1"
    KEYBOARD="$2"
    echo "Sending message:"
    echo "$MSG"
    [ -n "$KEYBOARD" ] && echo "(with keyboard)"
    [ -n "$KEYBOARD" ] && KEYBOARDARGS=(--data "reply_markup=$(echo "$KEYBOARD" | jq -r tostring)")
    curl --data-urlencode "text=$MSG" --data "chat_id=$CHAT_ID" --data "parse_mode=HTML" ${KEYBOARDARGS[@]} 'https://api.telegram.org/bot'$BOT_TOKEN'/sendMessage'
    echo
    echo
    sleep $TIMEOUT
}

echo "Start process devices"
for DEVICE in $(cat "$DATADIR"/"$BUILDTARGETSFILE"); do
    processDevice "$DEVICE"
done

git push origin trackdata
