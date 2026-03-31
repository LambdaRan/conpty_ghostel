# Ghostel shell integration for fish
# Source this from your config.fish:
#   test "$INSIDE_EMACS" = 'ghostel'; and source /path/to/ghostel/etc/ghostel.fish

# Idempotency guard — skip if already loaded (e.g. auto-injected).
functions -q __ghostel_osc7; and return

# Report working directory to the terminal via OSC 7
function __ghostel_osc7 --on-event fish_prompt
    printf '\e]7;file://%s%s\e\\' (hostname) "$PWD"
end
