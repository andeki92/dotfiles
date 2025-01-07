show_kube() {      # save this module in a file with the name <module_name>.sh
    local index=$1 # this variable is used by the module loader in order to know the position of this module
    local icon="$(get_tmux_option "@catppuccin_kube_icon" "󱃾")"
    local color="$(get_tmux_option "@catppuccin_kube_color" "#66ccff")"

    # This wrapper is a "trick" from https://github.com/catppuccin/tmux/issues/90
    # allowing us to reload it every n-seconds
    local text="$(get_tmux_option "@catppuccin_kube_text" "#($HOME/.config/tmux/custom/kube_companion.sh)")"

    local module=$(build_status_module "$index" "$icon" "$color" "$text")

    echo $module
}
