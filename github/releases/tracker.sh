#!/bin/bash

GITHUB_LATEST_RELEASE_URL="https://api.github.com/repos/%s/%s/releases/latest"
GITHUB_REPOSITORY_URL="https://github.com/%s/%s"
GITHUB_RELEASE_URL="$GITHUB_REPOSITORY_URL/releases/tag/%s"

DATADIR="trackdata"
DATABRANCH="trackdata-github-releases"
CHAT_ID="--placeholder--"

WORKDIR=$(dirname "$(readlink -f "$0")")
cd "$WORKDIR"
source ../../framework.sh

export IFS=$'\n'

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

processRepo() {
    owner="$(getCSV 1 <<< "$config" | cut -d'/' -f1)"
    [ -z "$owner" ] && echo "missing owner" && return 1
    reponame="$(getCSV 1 <<< "$config" | cut -d'/' -f2)"
    [ -z "$reponame" ] && echo "missing reponame" && return 1
    chatid="$(getCSV 2 <<< "$config")"
    [ -z "$chatid" ] && echo "missing chatid" && return 1
    # shellcheck disable=SC2154
    [ -f "$GIT_ROOT"/channel.txt ] && chatid=$(cat "$GIT_ROOT"/channel.txt)
    local includeprereleases
    includeprereleases="$(getCSV 3 <<< "$config")"
    ! isBooleanValue "$includeprereleases" && echo "invalid input for includeprereleases" && return 1
    local includechangelog
    includechangelog="$(getCSV 4 <<< "$config")"
    ! isBooleanValue "$includechangelog" && echo "invalid input for includechangelog" && return 1
    
    echo "Processing $owner/$reponame"

    latest_release_url="$(printf "$GITHUB_LATEST_RELEASE_URL" "$owner" "$reponame")"
    latest_release="$(GitHubApiRequest "$latest_release_url")"
    [ -z "$latest_release" ] && echo "empty response from GitHub API!" && return 1
    echo "$latest_release"
    latest_release_tag="$(jq -r -e .tag_name <<< "$latest_release")"
    [ -z "$latest_release_tag" ] && echo "empty latest release tag!" && return 1
    echo "$latest_release_tag"

    local repodatadir="$DATADIR"/"$owner/$reponame"
    [ ! -d "$repodatadir" ] && mkdir -p "$repodatadir"
    [ ! -f "$repodatadir"/latest ] && touch "$repodatadir"/latest
    local latest_release_tag_saved
    latest_release_tag_saved=$(cat "$repodatadir"/latest)
    echo "saved = $latest_release_tag_saved"
    echo "latest = $latest_release_tag"
    [ "$latest_release_tag_saved" = "$latest_release_tag" ] && {
        echo "No new release found."
        return
    }
    echo "New release found."
    echo "$latest_release_tag" > "$repodatadir"/latest

    changelog=$(jq -r .body <<< "$latest_release")
    releaseuploader=$(jq -r .author.login <<< "$latest_release")
    releasename=$(jq -r .name <<< "$latest_release")
    releasecommitish=$(jq -r .target_commitish <<< "$latest_release")
    releasetag="$latest_release_tag"
    repositoryurl=$(printf "$GITHUB_REPOSITORY_URL" "$owner" "$reponame")
    releaseurl=$(printf "$GITHUB_RELEASE_URL" "$owner" "$reponame" "$releasetag")
    for chatid in $(stripCommentLines < config.csv | stripEmptyLines | trimLines | grep -F "$reponame" | cut -d, -f2); do
        # we need to ignore the return code here
        # because if a second message post fails, the first one will be repeated
        sendReleaseMessage || true
    done

    saveTrackDataFile "$owner"/"$reponame"/latest "Process $owner/$reponame"
}

sendReleaseMessage() {
    owner_tag=$(convertToTelegramTag <<< "$owner")
    reponame_tag=$(convertToTelegramTag <<< "$reponame")
    [ -z "$includechangelog" ] && includechangelog=false
    changelog_formatted=""
    $includechangelog && changelog_formatted="$(envsubstadvanced < changelog.html | stripEmptyLines)"
    MSG="$(envsubstadvanced < message.html | stripEmptyLines)"
    KEYBOARD="$(envsubstadvanced < message-keyboard.json)"
    export CHAT_ID="$chatid"
    sendMessage "$MSG" "$KEYBOARD"
}

CONFIG="$(stripCommentLines < config.csv | stripEmptyLines | trimLines | sort --key=1,1 --field-seperator=, --unique)"

for config in $CONFIG; do
    processRepo "$config"
done
