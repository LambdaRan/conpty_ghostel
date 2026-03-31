# Ghostel shell integration auto-injection for fish.
# Auto-loaded via XDG_DATA_DIRS.

# Restore XDG_DATA_DIRS by removing our injected path.
if set -q GHOSTEL_SHELL_INTEGRATION_XDG_DIR
    if set -q XDG_DATA_DIRS
        set --function --path xdg_data_dirs "$XDG_DATA_DIRS"
        if set --function index (contains --index "$GHOSTEL_SHELL_INTEGRATION_XDG_DIR" $xdg_data_dirs)
            set --erase --function xdg_data_dirs[$index]
        end
        if set -q xdg_data_dirs[1]
            set --global --export --unpath XDG_DATA_DIRS "$xdg_data_dirs"
        else
            set --erase --global XDG_DATA_DIRS
        end
    end
    set --erase GHOSTEL_SHELL_INTEGRATION_XDG_DIR
end

status --is-interactive; or exit 0

# Report working directory to the terminal via OSC 7
function __ghostel_osc7 --on-event fish_prompt
    printf '\e]7;file://%s%s\e\\' (hostname) "$PWD"
end
