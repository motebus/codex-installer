#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
installer=$repo_dir/install-mote-transport.sh

test -x "$installer"
sh -n "$installer"

for required in \
  'mote-transport-2026.08.30-r02-canary' \
  'sphere 4.0.0-1 amd64' \
  'mote-proxy 1.4.0-14 all' \
  'moted 3.2.0-33 amd64' \
  '7e0be26927afa349001caee54cf46117587386f7d42ce82a9611fa50ea1e7065' \
  '95e3c6e930973c203ccd8590453d33fb9b7339c6ca7a4d527479b97a774428bf' \
  '5341a5552c45d57a48260c26fb683581b9db8f948d49727a3b054c221f8085f6'
do
  grep -Fq "$required" "$installer"
done

if grep -Eiq '^[[:space:]]*(sudo[[:space:]]+)?(scp|rsync|sshpass)([[:space:]]|$)|StrictHostKeyChecking[ =]no' "$installer"; then
  printf '%s\n' 'forbidden legacy or insecure transport path found' >&2
  exit 1
fi

if test -n "${MOTE_TRANSPORT_ARTIFACT_DIR:-}"; then
  "$installer" --artifact-dir "$MOTE_TRANSPORT_ARTIFACT_DIR" --verify-only
fi

printf '%s\n' 'install-mote-transport tests: PASS'
