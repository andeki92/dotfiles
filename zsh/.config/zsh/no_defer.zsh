#!/usr/bin/env zsh

function is_linux() {
    if [ "$(uname -s)" = "Linux" ]; then
        return 0
    else
        return 1
    fi
}

# Source rust environment if it exists
[ -f ~/.cargo/env ] && source ~/.cargo/env

# --- asdf 🛠️ (https://asdf-vm.com/) ---
if [ -f ~/.asdf/asdf.sh ]; then
    source ~/.asdf/asdf.sh

    # add asdf completions to zsh
    fpath=(${ASDF_DIR}/completions $fpath)
fi

# --- mise-en-place
if [ -f ~/.local/bin/mise ]; then
  eval "$(~/.local/bin/mise activate zsh)"
fi

if is_linux; then
    eval $(keychain --eval --agents ssh id_rsa >/dev/null 2>&1) >/dev/null 2>&1
fi

# --- Starship 🚀 (https://starship.rs/) ---
# Check that the function `starship_zle-keymap-select()` is defined.
# xref: https://github.com/starship/starship/issues/3418
type starship_zle-keymap-select >/dev/null ||
    {
        eval "$(starship init zsh)"
    }

# --- fzf 😺 (https://github.com/junegunn/fzf) ---
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

export FZF_DEFAULT_OPTS=" \
--color=bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796 \
--color=fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6 \
--color=marker:#f4dbd6,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796 \
--border
"

export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

_fzf_compgen_path() {
    fd --hidden --exclude .git . "$1"
}

_fzf_compgen_dir() {
    fd --hidden --exclude .git . "$1"
}

autoload -Uz compinit && compinit

# Source kubectl completion
# command -v kubectl >/dev/null 2>&1 && source ~/.config/zsh/autocomplete/kubectl
command -v kubectl >/dev/null 2>&1 && source <(kubectl completion zsh)
command -v helm >/dev/null 2>&1 && source <(helm completion zsh)

# --- tmux ---

if [ "$TMUX" = "" ]; then
    source ~/.config/tmux/tmux-sessionizer "$PWD"
fi
