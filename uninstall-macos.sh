#!/bin/zsh
# Removes the per-user CommitGuard LaunchAgent.
set -u

LABEL="com.merozemory.commitguard"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
uid=$(id -u)
launchctl bootout "gui/$uid/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
print "CommitGuard macOS autostart removed. The repository and logs were left in place."
