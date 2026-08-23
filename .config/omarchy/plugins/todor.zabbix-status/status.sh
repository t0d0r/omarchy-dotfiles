#!/usr/bin/env bash

set -u

key="${HOME}/.ssh/id_ed25519"
host="do"

if [[ ! -r "$key" ]]; then
  printf 'ERROR\tSSH key not found: %s\n' "$key"
  exit 20
fi

fingerprint="$(ssh-keygen -lf "$key" 2>/dev/null | awk '{print $2}')"
if [[ -z "$fingerprint" ]]; then
  printf 'ERROR\tCould not read SSH key fingerprint\n'
  exit 21
fi

agent_keys="$(ssh-add -l 2>/dev/null || true)"
if ! grep -Fq "$fingerprint" <<<"$agent_keys"; then
  printf 'NEEDS_KEY\tUnlock SSH key\n'
  exit 10
fi

output="$(timeout 20s ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=8 \
  "$host" '~/bin/zabbix.status' 2>&1)"
exit_code=$?

if (( exit_code != 0 )); then
  output="$(printf '%s' "$output" | tr '\n\t' '  ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  [[ -n "$output" ]] || output="SSH command failed (exit ${exit_code})"
  printf 'ERROR\t%s\n' "$output"
  exit "$exit_code"
fi

printf 'OK\n%s\n' "$output"
