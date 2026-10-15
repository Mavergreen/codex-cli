#!/bin/sh
# platform: host-agnostic
set -eu
printf 'https://github.com/openai/codex/releases/tag/rust-v%s\n' "${1:?usage: upstream-release-notes-url.sh <upstream-version>}"
