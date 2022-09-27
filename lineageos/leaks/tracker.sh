#!/bin/bash

# procedure:
# 1. get github last pushed repositories
# 2. for each repository:
#   1. compare last pushed timestamp, to prevent double checks
#   2. fetch all change ids
#   3. compare if there are newer change ids than last time
#   4. for each new change, check if change is private

REMOTE_REPO_URL="https://github.com/%s"
REMOTE_GERRIT_CHANGE_URL="https://review.lineageos.org/changes/%s"
REMOTE_REPO_COMMIT_URL="$REMOTE_REPO_URL/commit/%s"

DATADIR="trackdata"
DATABRANCH="trackdata-lineage-leaks"
WORKDIR=$(dirname $(readlink -f "$0"))

CHAT_ID="-1001765152232"

GITHUB_CHECK_REPOSITORIES_AMOUNT=50 # how many repositorys to check, limit: 100

cd "$WORKDIR"
source ../../framework.sh

saveTrackDataFiles() {
    local PREVWD="$(pwd)"
    local COMMITMESSAGE="$1"
    shift
    cd "$DATADIR"
    local file
    for file in "$@"; do
        file="$(sed "s|^$DATADIR/||" <<< "$file")"
        git add "$file"
    done
    git commit -q -m "$COMMITMESSAGE" || true
    git push -q origin "$DATABRANCH"
    cd "$PREVWD"
}

filterNewChanges() {
    local old_change="$1"
    [ -z "$old_change" ] && old_change=0
    while read -r change; do
        [ $change -gt $old_change ] && echo "$change"
    done
    return 0
}

getCommit() {
    local REPO="$1"
    local COMMIT="$2"
    GitHubApiRequest "https://api.github.com/repos/$REPO/git/commits/$COMMIT"
}
getCommitTitle() {
    getCommit "$@"  | jq -r '.message' | head -n 1
}

IFS=$'\n'
for repojson in $(GitHubApiRequest "https://api.github.com/orgs/LineageOS/repos?&sort=pushed&per_page=$GITHUB_CHECK_REPOSITORIES_AMOUNT" | jq -c '.[]'); do
    reponame=$(jq -r '.name' <<< "$repojson")
    reponametag=$(sed 's/[^[:alpha:]]/_/g' <<< "$reponame")
    repofullname=$(jq -r '.full_name' <<< "$repojson")
    repofullname_sanitized="${repofullname//\//_}"
    saved_repo_path="$DATADIR"/"$repofullname_sanitized"
    [ ! -d "$saved_repo_path" ] && mkdir "$saved_repo_path"
    echo "Processing $repofullname"
    last_pushed=$(jq -r '.pushed_at' <<< "$repojson")
    echo "  last pushed: $last_pushed"
    [ ! -f "$saved_repo_path"/last_pushed ] && touch "$saved_repo_path"/last_pushed
    saved_last_pushed=$(cat "$saved_repo_path"/last_pushed)
    echo "  saved last pushed: $saved_last_pushed"
    [ "$last_pushed" = "$saved_last_pushed" ] && continue
    echo "  Repo has been updated since last check!"
    [ ! -f "$saved_repo_path"/last_change ] && touch "$saved_repo_path"/last_change
    saved_last_change=$(cat "$saved_repo_path"/last_change)
    echo "  saved last change: $saved_last_change"

    repo_folder="${repofullname_sanitized}_dummy"
    [ -d "$repo_folder" ] && rm -rf "$repo_folder"
    mkdir "$repo_folder"
    cd "$repo_folder"
    git init -q
    # repo_url=$(jq -r '.clone_url' <<< "$repojson")
    printf -v repo_url "$REMOTE_REPO_URL" "$repofullname"
    git remote add origin "$repo_url"
    refs="$(git ls-remote --refs -q)"
    cd "$WORKDIR"
    rm -rf "$repo_folder"
    
    changes="$(grep -i 'refs/changes' <<< "$refs" || true)"
    [ -z "$changes" ] && continue
    changeids="$(cut -f2 <<< "$changes" | cut -d'/' -f4 | sort -u -n)"
    newchangeids=$(filterNewChanges "$saved_last_change" <<< "$changeids")
    [ -n "$newchangeids" ] && echo "  Found $(wc -l <<< "$newchangeids") new changes"
    [ -z "$newchangeids" ] && echo "  Found no new changes"
    for change in $newchangeids; do
        [ -z "$change" ] && {
            echo "Got empty change!"
            echo "change list is \"$newchangeids\""
            continue
        }
        echo "    Processing change $change"
        echo "$change" > "$saved_repo_path"/last_change

        printf -v change_url "$REMOTE_GERRIT_CHANGE_URL" "$change"
	    [ -z "$(curl --silent --head "$change_url" | grep '404 Not Found')" ] && continue

        commit="$(grep -i "/${change}/" <<< "$changes" | grep -v -e '/meta$' | cut -f1 | tail -n 1)"
        commitpatchnumber="$(grep -i -e "^$commit" <<< "$changes" | cut -f2 | cut -d'/' -f5)"
        metacommit="$(grep -i "/${change}/" <<< "$changes" | grep -e '/meta$' | cut -f1)"
        
        changetitle="$(getCommitTitle "$repofullname" "$commit")"

        printf -v commit_url "$REMOTE_REPO_COMMIT_URL" "$repofullname" "$commit"
        printf -v commit_metadata_url "$REMOTE_REPO_COMMIT_URL" "$repofullname" "$metacommit"
        echo "  Found private change $change: "$commit_url" $changetitle"

        declare -x reponametag change repofullname commit_url changetitle commitpatchnumber
        MESSAGE="$(envsubst < message.html)"
        declare -x commit_url commit_metadata_url
        KEYBOARD="$(envsubst < message-keyboard.json)"

        [ ! -d "$saved_repo_path"/"$change" ] && mkdir "$saved_repo_path"/"$change"
        sendMessage "$MESSAGE" "$KEYBOARD" > "$saved_repo_path"/"$change"/message
        echo "$commitpatchnumber" > "$saved_repo_path"/"$change"/patch
        
        saveTrackDataFiles "Process change $change" "$saved_repo_path"/"$change"
    done

    echo "$last_pushed" > "$saved_repo_path"/last_pushed
    saveTrackDataFiles "Process $repofullname" "$saved_repo_path"/last_pushed "$saved_repo_path"/last_change
done
