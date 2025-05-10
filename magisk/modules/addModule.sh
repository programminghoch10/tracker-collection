#!/bin/bash

set -e
shopt -s inherit_errexit

cd "$(dirname "$(readlink -f "$0")")"

module="$1"
[ -z "$module" ] && echo no module provided >&2 && exit 1

for cmd in unzip jq curl; do
    [ -z "$(command -v "$cmd")" ] && echo "Missing command $cmd" && exit 1
done

mode=unknown
[ -f "$module" ] && mode=zip
grep -q -F '.json' <<< "$module" && mode=json

getpropfromzip() {
    local name="$1"
    unzip -p module.zip module.prop | grep "^$name=" | cut -d'=' -f2 | head -n 1
}

case $mode in
    zip)
        cp -v "$module" module.zip
        ;;
    json)
        zipUrl=$(curl --fail --location "$module" | jq -r '.zipUrl')
        echo zipurl = "$zipUrl" >&2
        curl --silent --fail --location --output module.zip "$zipUrl"
        ;;
    *)
        echo unknown mode $mode >&2
        exit 1
esac

id=$(getpropfromzip id)
updatejson=$(getpropfromzip updateJson)
sourceurl=""
grep -q -F 'https://raw.githubusercontent.com/' <<< "$updatejson" \
    && sourceurl=$(sed -e 's|^https://raw\.githubusercontent\.com/|https://github.com/|' -e 's|^\(https://github.com/[[:alnum:]._-]*/[[:alnum:]._-]*\)/.*$|\1|' <<< "$updatejson")
echo "$id,$updatejson,$sourceurl,false" >> config.csv
rm module.zip
