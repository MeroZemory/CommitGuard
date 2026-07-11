#!/bin/zsh
# Installs CommitGuard as a per-user LaunchAgent and starts it immediately.
set -eu

SCRIPT_DIR="${0:A:h}"
WATCHDOG="$SCRIPT_DIR/commit-guard-macos.sh"
LABEL="com.merozemory.commitguard"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

[[ -x "$WATCHDOG" ]] || chmod +x "$WATCHDOG"
mkdir -p "$HOME/Library/LaunchAgents"
uid=$(id -u)

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$WATCHDOG</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$SCRIPT_DIR/commit-guard-macos.launchd.out.log</string>
  <key>StandardErrorPath</key><string>$SCRIPT_DIR/commit-guard-macos.launchd.err.log</string>
</dict></plist>
EOF

if launchctl print "gui/$uid/$LABEL" >/dev/null 2>&1; then
  # Keep the registered agent and restart it in place. This avoids a launchd
  # race where bootout followed immediately by bootstrap returns I/O error.
  launchctl kickstart -k "gui/$uid/$LABEL"
else
  launchctl bootstrap "gui/$uid" "$PLIST"
fi
print "CommitGuard started as $LABEL"
print "Test notifications: $WATCHDOG --test-notification"
