#!/bin/bash
export IFS=$'\n'
[ -z "$(command -v shellcheck)" ] && echo "shellcheck not installed!" && exit 1
shellcheck --version

SHELLCHECK_ARGS=()
SHELLCHECK_ARGS+=(--wiki-link-count=256)

FILES=( $(find . -type f -name '*.sh') )

shellcheck \
    "${SHELLCHECK_ARGS[@]}" \
    "$@" \
    "${FILES[@]}"
