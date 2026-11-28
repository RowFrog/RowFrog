# scripts/local/tool-path.sh: puts the Mac's tool folders on PATH, whichever exist, in a fixed order.
# Sourced (not run) by the local scripts, so they call uv, xcodegen, node, npm, python3 and gh
# by name and work the same with MacPorts, Homebrew or uv's own installer (owner, 27 Nov 2026).
# MacPorts first, so today's Mac behaves exactly as before; once MacPorts is gone, its folder is skipped.
# RF_TOOL_DIRS overrides the list (for testing, or during a switch).
# Own variable names, cleared first, so nothing from the calling script leaks in or out.
# Load it through the main checkout, because install.sh copies the hooks into .git/hooks and
# backup.sh to backups/make-backup.sh (--show-toplevel fails inside .git/hooks):
#   . "$(dirname "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)")/scripts/local/tool-path.sh"
unset _rf_dir _rf_tools
for _rf_dir in ${RF_TOOL_DIRS:-/opt/local/bin /opt/local/sbin /opt/homebrew/bin /opt/homebrew/sbin $HOME/.local/bin}; do
  # Always in front, even when the login PATH already has the folder further back, as the old lines did.
  if [ -d "$_rf_dir" ]; then _rf_tools="${_rf_tools:+$_rf_tools:}$_rf_dir"; fi
done
export PATH="${_rf_tools:+$_rf_tools:}/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
unset _rf_dir _rf_tools
