#!/usr/bin/env zsh

if [[ -n "$GHOSTTY_QUICK_TERMINAL" && -z "$HERDR_ENV" && $- == *i* ]]; then
    #!/usr/bin/env bash
    # Attach the Ghostty quick terminal to whichever herdr pane is currently focused.
    # Falls back to the full herdr UI if resolution fails for any reason.

    if ! command -v jq >/dev/null 2>&1; then
      exec herdr
    fi

    term_id="$(herdr pane list 2>/dev/null \
      | jq -r '.result.panes[]? | select(.focused == true) | .terminal_id' \
      | head -n1)"

    if [[ -n "$term_id" && "$term_id" != "null" ]]; then
      exec herdr terminal attach "$term_id" --takeover
    fi

    exec herdr
fi
