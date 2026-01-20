#!/bin/bash

GSMARENA_BASE_URL="https://www.gsmarena.com"
GSMARENA_ALL_BRANDS_URL="$GSMARENA_BASE_URL/makers.php3"
GSMARENA_COMPARE_URL="$GSMARENA_BASE_URL/compare.php3?idPhone1=%s"
GOOGLE_SHOPPING_URL="https://www.google.com/search?q=%s&tbm=shop"

CURL_ARGS=()
CURL_ARGS+=('--fail-with-body')
CURL_ARGS+=('--silent')
CURL_ARGS+=('--user-agent' '')

CHAT_ID="-1001763351429"

DATADIR="trackdata"
DATABRANCH="trackdata-gsm-release"
WORKDIR=$(dirname "$(readlink -f "$0")")

GSMARENA_TIMEOUT=5

cd "$WORKDIR"
source ../../framework.sh

for cmd in curl pup envsubst; do
    [ -z "$(command -v "$cmd")" ] && echo "Missing command $cmd" && exit 1
done

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

[ ! -d "$DATADIR/latest" ] && mkdir "$DATADIR/latest"

# shellcheck disable=SC2154
processNewDevice() {
    devicelink="$1"
    
    devicepage="$(curl "${CURL_ARGS[@]}" "$GSMARENA_BASE_URL/$devicelink")"
    for spec in year status modelname weight chipset internalmemory displaytype displayresolution os price cam1modules cam2modules wlan bluetooth gps nfc usb batdescription1 cpu gpu dimensions memoryslot colors models; do
        declare -g "device$spec"="$(pup "[data-spec=$spec] text{}" <<< "$devicepage" | sed ':a;N;$!ba;s/\n\n/\n/g; s|\n| / |g;')"
    done
    deviceannounced="$deviceyear"
    devicereleased="$(sed -e 's/Available. //' -e 's/Released //' <<< "$devicestatus")"
    devicewikiurl="$GSMARENA_BASE_URL/$devicelink"
    printf -v devicebuyurl "$GOOGLE_SHOPPING_URL" "$(jq -rn --arg x "$devicemodelname" '$x|@uri')"
    deviceimageurl="$(pup '.specs-photo-main img attr{src}' <<< "$devicepage")"
    devicegsmarenaid="$(sed -e 's|.*-\([[:digit:]]*\).php$|\1|' <<< "$devicelink")"
    printf -v devicecompareurl "$GSMARENA_COMPARE_URL" "$devicegsmarenaid"

    MESSAGE="$(envsubstadvanced < message.html)"
    IMAGECAPTION="$(envsubstadvanced < imagecaption.html)"
    KEYBOARD="$(envsubstadvanced < message-keyboard.json)"

    sendImageMessage "$deviceimageurl" "$IMAGECAPTION"
    sendMessage "$MESSAGE" "$KEYBOARD"

}

allbrands="$(curl "${CURL_ARGS[@]}" "$GSMARENA_ALL_BRANDS_URL" | pup 'table td' | pup 'a attr{href}')"

for brandlink in $allbrands; do
    sleep $GSMARENA_TIMEOUT
    brandlink="$(sed 's|-\([[:digit:]]*\).php|-f-\1-2.php|' <<< "$brandlink")" # apply filter "available"
    brand="${brandlink%%-*}"
    echo "Processing brand $brand"
    brandpage=$(curl "${CURL_ARGS[@]}" "$GSMARENA_BASE_URL/$brandlink")
    devicelinks="$(pup '#review-body > div.makers > ul > li' 'a attr{href}' <<< "$brandpage")"
    [ -z "$devicelinks" ] && echo "$brand has no devices available" && continue
    addeddevicesdiff="$(diff --text --new-file --new-line-format="+%L" --old-line-format="" --unchanged-line-format="#%L" "$DATADIR/latest/$brand" <(echo "$devicelinks") || true)"
    [ -z "$(sed -e 's/^#.*//' <<<"$addeddevicesdiff")" ] && {
        echo "$brand is up to date."
        continue
    }
    for devicediff in $addeddevicesdiff; do 
        case "$devicediff" in 
            \+*)
                echo "Found new device $devicediff"
                device=$(sed -e 's/^+//' <<< "$devicediff")
                ;;
            \#*)
                echo "Device $devicediff is already known. Stopping diff evaluation of $brand."
                break
                ;;
            *)
                echo "diffing $brand devices failed on line $devicediff"
                echo "diff devices are: $addeddevicesdiff"
                echo "new devices are: $devicelinks"
                echo "old devices were:"
                cat "$DATADIR/latest/$brand"
                exit 1
        esac
        echo "Processing new device $device"
        processNewDevice "$device"
    done
    echo "$devicelinks" > "$DATADIR/latest/$brand"
    saveTrackDataFile "latest/$brand" "Process $brand"
done
