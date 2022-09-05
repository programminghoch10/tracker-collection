#!/bin/bash

GSMARENA_BASE_URL="https://www.gsmarena.com"
GSMARENA_ALL_BRANDS_URL="$GSMARENA_BASE_URL/makers.php3"
GSMARENA_COMPARE_URL="$GSMARENA_BASE_URL/compare.php3?idPhone1=%s"
GOOGLE_SHOPPING_URL="https://www.google.com/search?q=%s&tbm=shop"

CHAT_ID="-1001763351429"

DATADIR="trackdata"
DATABRANCH="trackdata-gsm-release"
WORKDIR=$(dirname $(readlink -f "$0"))

GSMARENA_TIMEOUT=5

cd "$WORKDIR"
source ../../framework.sh

for cmd in curl pup envsubst; do
    [ -z "$(command -v $cmd)" ] && echo "Missing command $cmd" && exit 1
done

saveTrackDataFile() {
    PREVWD="$(pwd)"
    FILE="$1"
    COMMITMESSAGE="$2"
    cd "$DATADIR"
    git add "$FILE"
    git commit -m "$COMMITMESSAGE"
    git push origin "$DATABRANCH"
    cd "$PREVWD"
}

[ ! -d "$DATADIR/latest" ] && mkdir "$DATADIR/latest"

allbrands="$(curl -s -f "$GSMARENA_ALL_BRANDS_URL" | pup 'table td' | pup 'a attr{href}')"

set -a #automatically export new variables, needed for envsubst later
for brandlink in $allbrands; do
    sleep $GSMARENA_TIMEOUT
    brandlink="$(sed 's|-\([[:digit:]]*\).php|-f-\1-2.php|' <<< "$brandlink")" # apply filter "available"
    brand="${brandlink%%-*}"
    echo "Processing brand $brand"
    brandpage=$(curl -f -s "$GSMARENA_BASE_URL/$brandlink")
    devicelink="$(pup '#review-body > div.makers > ul > li' <<< "$brandpage" | pup 'a attr{href}' | head -n 1)"
    [ -z "$devicelink" ] && echo "$brand has no devices available" && continue
    echo "\"$devicelink\" is the newest device"
    [ ! -f "$DATADIR/latest/$brand" ] && touch "$DATADIR/latest/$brand"
    [ "$(cat "$DATADIR/latest/$brand")" = "$devicelink" ] && {
        echo "$brand latest device is up to date."
        continue
    }
    echo "$devicelink" > "$DATADIR/latest/$brand"
    devicepage="$(curl -f -s "$GSMARENA_BASE_URL/$devicelink")"
    for spec in year status modelname weight chipset internalmemory displaytype displayresolution os price cam1modules cam2modules wlan bluetooth gps nfc usb batdescription1 cpu gpu dimensions memoryslot colors models; do
        declare "device$spec"="$(pup "[data-spec=$spec] text{}" <<< "$devicepage" | sed ':a;N;$!ba;s/\n\n/\n/g; s|\n| / |g;')"
    done
    deviceannounced="$deviceyear"
    devicereleased="$(sed -e 's/Available. //' -e 's/Released //' <<< "$devicestatus")"
    devicewikiurl="$GSMARENA_BASE_URL/$devicelink"
    printf -v devicebuyurl "$GOOGLE_SHOPPING_URL" "$(jq -rn --arg x "$devicemodelname" '$x|@uri')"
    deviceimageurl="$(pup '.specs-photo-main img attr{src}' <<< "$devicepage")"
    devicegsmarenaid="$(sed -e 's|.*-\([[:digit:]]*\).php$|\1|' <<< "$devicelink")"
    printf -v devicecompareurl "$GSMARENA_COMPARE_URL" "$devicegsmarenaid"

    MESSAGE="$(envsubst < message.html)"
    IMAGECAPTION="$(envsubst < imagecaption.html)"
    KEYBOARD="$(envsubst < message-keyboard.json)"

    sendImageMessage "$deviceimageurl" "$IMAGECAPTION"
    sendMessage "$MESSAGE" "$KEYBOARD"
    saveTrackDataFile "latest/$brand" "Process $devicemodelname"

done
