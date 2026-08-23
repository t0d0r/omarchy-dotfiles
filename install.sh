#!/usr/bin/env bash

set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_dir="${repo_dir}/.config"
config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}"
backup_dir="${config_dir}/omarchy-dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
backed_up=false

while IFS= read -r -d '' source_file; do
  relative_path="${source_file#"${source_dir}/"}"
  destination="${config_dir}/${relative_path}"

  if [[ -e "${destination}" ]]; then
    mkdir -p "${backup_dir}/$(dirname -- "${relative_path}")"
    cp -a -- "${destination}" "${backup_dir}/${relative_path}"
    backed_up=true
  fi

  mkdir -p "$(dirname -- "${destination}")"
  install -m "$(stat -c '%a' "${source_file}")" -- "${source_file}" "${destination}"
  printf 'Installed %s\n' "${destination}"
done < <(find "${source_dir}" -type f -print0 | sort -z)

if [[ "${backed_up}" == true ]]; then
  printf '\nPrevious files were backed up to %s\n' "${backup_dir}"
fi

if command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1; then
  printf 'Hyprland configuration reloaded.\n'
else
  printf 'Log out and back in to apply all configuration.\n'
fi

