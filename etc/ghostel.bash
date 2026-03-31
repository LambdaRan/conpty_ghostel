# Ghostel shell integration for bash
# Source this from your .bashrc:
#   [[ "$INSIDE_EMACS" = 'ghostel' ]] && source /path/to/ghostel/etc/ghostel.bash

# Idempotency guard — skip if already loaded (e.g. auto-injected).
[[ "$(type -t __ghostel_osc7)" = "function" ]] && return

# Enable PTY echo.  Bash's readline buffers its own echo output so it
# never reaches the Emacs process filter.  PTY-level echo makes the
# kernel echo input immediately.
builtin command stty echo 2>/dev/null

# Report working directory to the terminal via OSC 7
__ghostel_osc7() {
    printf '\e]7;file://%s%s\e\\' "$HOSTNAME" "$PWD"
}
PROMPT_COMMAND="__ghostel_osc7${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
