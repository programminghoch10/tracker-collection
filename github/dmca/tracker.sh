#!/bin/bash
git config core.pager cat

CHAT_ID="-1001732693737"
[ -z "$BOT_TOKEN" ] && exit 1
TIMEOUT=5

GITHUBDMCAREPO="https://github.com/github/dmca"
GITHUBDMCABRANCH="master"
GITHUBDMCACOMMITTITLE="Process DMCA request"
GITHUBDMCACOMMITAUTHOR="dmca-sync-bot@github.com"
LOCALDMCABRANCH="trackdata-github-dmca"

processCommit() {
    COMMIT="$1"
    echo "process $COMMIT"
    TITLE="$(git log --pretty='%s' "$COMMIT~1".."$COMMIT")"
    AUTHOR="$(git log --pretty='%ae' "$COMMIT~1".."$COMMIT")"
    [ "$TITLE" != "$GITHUBDMCACOMMITTITLE" ] || [ "$AUTHOR" != "$GITHUBDMCACOMMITAUTHOR" ] && {
        echo "Ignoring commit $COMMIT"
        git log "$COMMIT~1".."$COMMIT"
        echo
        return
    }
    #git log "$COMMIT~1".."$COMMIT"
    FILE=$(git diff --diff-filter=A --name-only "$COMMIT~1".."$COMMIT" | head -n 1)
    LINK="$GITHUBDMCAREPO/blob/master/$FILE"
    MSG="<a href=\"$LINK\">$(basename $FILE)</a>"
    sendMessage "$MSG"
}

sendMessage() {
    MSG="$1"
    echo "Sending message:"
    echo "$MSG"
    curl -s --data "text=$MSG" --data "chat_id=$CHAT_ID" --data "parse_mode=HTML" 'https://api.telegram.org/bot'$BOT_TOKEN'/sendMessage'
    echo
    echo
}

[ -z $(git remote | grep dmca) ] && git remote add dmca "$GITHUBDMCAREPO"
git fetch dmca $GITHUBDMCABRANCH
LATEST_UPSTREAM=$(git log -1 --pretty="%H" dmca/$GITHUBDMCABRANCH)
LATEST_LOCAL=$(git log -1 --pretty="%H" origin/$LOCALDMCABRANCH)
echo "Latest upstream: $LATEST_UPSTREAM"
echo "Latest local:    $LATEST_LOCAL"
[ "$LATEST_UPSTREAM" = "$LATEST_LOCAL" ] && {
    echo "No changes found"
    exit 0
}
echo

for COMMIT in $(git log --pretty='%H' --no-merges origin/$LOCALDMCABRANCH..dmca/$GITHUBDMCABRANCH); do
    processCommit "$COMMIT"
    sleep $TIMEOUT
done

git branch -f $LOCALDMCABRANCH dmca/$GITHUBDMCABRANCH
git push --force origin $LOCALDMCABRANCH
