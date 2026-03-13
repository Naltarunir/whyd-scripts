#!/usr/bin/env bash
# -----------------------------------------------------------------------
# Copyright (c) 2026 Naltarunir (https://github.com/Naltarunir)
# 
# This software is licensed under the European Union Public License 1.2 
# (EUPL-1.2) or later.
#
# The full text of the license can be found at:
# https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# -----------------------------------------------------------------------
# Please refer to the README.md before raising an issue on GitHub. 
#
# NOTE: 'set -e' and 'pipefail' are intentionally omitted. 
# Visit https://mywiki.wooledge.org/BashFAQ/105 for details.
#
# Each section handles its own errors verbosely rather than aborting silently.
# -----------------------------------------------------------------------

set -u
export LANG=C.UTF-8

LOG_DIR="$HOME/.local/share/whyd-check"
LOG_FILE="$LOG_DIR/whyd-check-$(date +%Y%m%d-%H%M%S).txt"
SYSTEM_CHECK_SCRIPT="$HOME/.local/bin/whyd-check.sh"

# ── Create log directory ─────────────────────────────────────────────
if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
    echo "[$(date)] ERROR: Could not create log directory: $LOG_DIR" >&2
    # Try to notify the desktop if possible; ignore failure
    notify-send -u critical "Whyd-check Failed" \
        "Could not create log directory: $LOG_DIR" 2>/dev/null || true
    exit 1
fi

# ── Verify the check script exists and is executable ────────────────
if [[ ! -f "$SYSTEM_CHECK_SCRIPT" ]]; then
    MSG="whyd-check.sh not found at: $SYSTEM_CHECK_SCRIPT"
    echo "[$(date)] ERROR: $MSG" | tee "$LOG_FILE"
    notify-send -u critical "Whyd-Check Failed" "$MSG" 2>/dev/null || true
    exit 1
fi

if [[ ! -x "$SYSTEM_CHECK_SCRIPT" ]]; then
    MSG="whyd-check.sh exists but is not executable: $SYSTEM_CHECK_SCRIPT"
    echo "[$(date)] ERROR: $MSG" | tee "$LOG_FILE"
    echo "[$(date)] TIP: Run: chmod +x $SYSTEM_CHECK_SCRIPT" | tee -a "$LOG_FILE"
    notify-send -u critical "Whyd-Check Failed" "$MSG" 2>/dev/null || true
    exit 1
fi

# ── Run the check and capture output + exit code ────────────────────
echo "[$(date)] Starting whyd-check..." > "$LOG_FILE"

if ! "$SYSTEM_CHECK_SCRIPT" >> "$LOG_FILE" 2>&1; then
    EXIT_CODE=$?
    echo "" >> "$LOG_FILE"
    echo "[$(date)] WARNING: whyd-check.sh exited with code $EXIT_CODE" \
        >> "$LOG_FILE"
    echo "The log above may be incomplete." >> "$LOG_FILE"
    notify-send -u normal "Whyd-Check" \
        "Check completed with warnings (exit $EXIT_CODE). See log." \
        2>/dev/null || true
else
    echo "" >> "$LOG_FILE"
    echo "[$(date)] Whyd-check completed successfully." >> "$LOG_FILE"
fi

sleep 2

# ── Open the log in the default text viewer ──────────────────────────
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$LOG_FILE" 2>/dev/null || true
else
    # Fallback: try common terminal text viewers
    for VIEWER in gedit mousepad kate xed nano; do
        if command -v "$VIEWER" >/dev/null 2>&1; then
            "$VIEWER" "$LOG_FILE" &
            break
        fi
    done
fi