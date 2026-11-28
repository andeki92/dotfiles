#!/usr/bin/env zsh

# sops decrypts with the homelab admin age key held on a YubiKey, through
# age-plugin-yubikey, which asks for the PIN and a touch. The file is only a
# pointer to the key on the YubiKey (serial and PIV slot), not a secret.
# Write it once per machine with the YubiKey plugged in:
#   age-plugin-yubikey --identity > "$XDG_CONFIG_HOME/sops/age/yubikey-identity.txt"
# sops still reads $XDG_CONFIG_HOME/sops/age/keys.txt as well, when it exists.
export SOPS_AGE_KEY_FILE="$XDG_CONFIG_HOME/sops/age/yubikey-identity.txt"
