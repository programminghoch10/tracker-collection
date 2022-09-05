#!/bin/bash

GSMARENA_BASE_URL="https://www.gsmarena.com"
GSMARENA_ALL_BRANDS_URL="$GSMARENA_BASE_URL/makers.php3"

DATADIR="trackdata"
DATABRANCH="trackdata-gsm-release"
WORKDIR=$(dirname $(readlink -f "$0"))

cd "$WORKDIR"
source ../../framework.sh

for cmd in curl pup; do
    [ -z "$(command -v $cmd)" ] && echo "Missing command $cmd" && exit 1
done

#curl -s "$GSMARENA_ALL_BRANDS_URL" | pup 'table td' > allbrands.html
#pup 'a attr{href}' > allbrands-links.txt < allbrands.html
echo samsung-phones-9.php > allbrands-links.txt

for brandlink in $(cat allbrands-links.txt); do
    brandlink="$(sed 's|-\([[:digit:]]*\).php|-f-\1-2.php|' <<< "$brandlink")" # apply filter "available"
    brand="${brandlink%%-*}"
    echo "Processing brand $brand"
    curl -s "$GSMARENA_BASE_URL/$brandlink" > "$brand.html"
    pup '#review-body > div.makers > ul > li' < "$brand.html" > "$brand-phones.html"
    pup 'a attr{href}' < "$brand-phones.html" > "$brand-phones-links.txt"
    echo "$(head -n 1 < $brand-phones-links.txt) is the newest device"
    break
    for devicelink in $(cat "$brand-phones-links.txt"); do
        echo "checking device $devicelink"
        devicepage="$(curl -s "$GSMARENA_BASE_URL/$devicelink")"
        #devicestatus="$(pup 'td.nfo[data-spec=status] text{}' <<< "$devicepage")"
        echo "$devicelink is the newest device"
        break
    done
done
