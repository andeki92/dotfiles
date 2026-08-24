# DeepSeek Harness (dsh) home — forced under XDG regardless of dsh's own
# default (resolveDshHome falls back to ~/.dsh otherwise).
export DSH_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/dsh"
