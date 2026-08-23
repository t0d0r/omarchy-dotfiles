# Omarchy dotfiles

Personal Omarchy configuration for a reproducible desktop setup.

Included:

- Hyprland user overrides
- US + Bulgarian phonetic keyboard layouts (switch with Left Alt + Right Alt)
- Omarchy shell and menu configuration
- Galactic Empire theme and background
- Zabbix status bar widget
- Active post-update hooks

## Install on a fresh Omarchy system

```bash
git clone https://github.com/t0d0r/omarchy-dotfiles.git
cd omarchy-dotfiles
./install.sh
```

The installer backs up every existing destination file before replacing it.
Hyprland normally reloads automatically; log out and back in if every component
does not update immediately.

## Machine-specific setup

The Zabbix widget expects:

- an SSH host alias named `do` in `~/.ssh/config`
- the private key `~/.ssh/id_ed25519`
- `~/bin/zabbix.status` on the remote host

SSH configuration and credentials are intentionally not tracked.

