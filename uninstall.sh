#!/bin/bash
#
# uninstall.sh — cleanly removes a Homebrew install that was set up with
# the companion install.sh, which wraps Homebrew's own upstream installer
# to run under a dedicated, admin-group "pkg" macOS user account rather
# than the invoking user.
#
# This undoes, in reverse order, everything install.sh did:
#   1. Runs Homebrew's own official uninstall.sh AS the pkg user (same
#      `sudo -EHu` pattern install.sh used), which is the upstream-
#      documented way to remove Homebrew itself — see
#      https://github.com/Homebrew/install/blob/main/README.md and
#      https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh.
#      That script removes the Homebrew git repo/source, Cellar and
#      Caskroom, the standard prefix subdirectories (bin/etc/include/lib/
#      opt/sbin/share/var/Frameworks), shell completions, docs/man pages,
#      caches, and logs. It does NOT touch shell profile PATH lines, and
#      it does not know anything about the pkg user wrapper — that's
#      everything below.
#   2. Removes /etc/sudoers.d/homebrew-sudoer (added by install.sh).
#   3. Removes the pkg user from the admin group (added by install.sh).
#   4. Removes ~/.config/homebrew.include (and .updated, if present) from
#      the CALLING user's home directory — these were written there by
#      install.sh, not into the pkg user's own home.
#   5. Optionally deletes the pkg user account and its home directory
#      entirely — destructive and NOT done by default; see --purge-user
#      below.
#
# Homebrew's own docs/FAQ don't enumerate manual cleanup steps beyond
# running their uninstall script, so step 1 is treated as authoritative
# for everything under Homebrew's own prefix; steps 2-5 exist only
# because install.sh's user-wrapping approach isn't something upstream
# Homebrew knows about or cleans up itself.
#
# Usage:
#   ./uninstall.sh                  # uninstall Homebrew; keep the pkg
#                                    # user account (prompts if a
#                                    # terminal is attached, otherwise
#                                    # keeps it and tells you how to
#                                    # remove it later)
#   ./uninstall.sh --purge-user     # also delete the pkg user account
#                                    # and its home directory, no prompt
#   ./uninstall.sh --keep-user      # never delete the pkg user account,
#                                    # no prompt either way
#
# Must be run by an admin user (the same kind of account that ran
# install.sh) — NOT as the pkg user itself.

set -uo pipefail

export UserName=pkg
export GroupName=staff
export HomeDir=/Users/pkg

PurgeUser=""   # "" = ask if interactive; "yes" = --purge-user; "no" = --keep-user

for arg in "$@"; do
    case "$arg" in
        --purge-user) PurgeUser="yes" ;;
        --keep-user) PurgeUser="no" ;;
        -h|--help)
            sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown argument: $arg (see --help)" >&2
            exit 1
            ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    echo "error: run this as your normal admin user, not as root/pkg — it calls sudo itself where needed." >&2
    exit 1
fi

if [ "$(whoami)" = "${UserName}" ]; then
    echo "error: run this as your normal admin user, not as the '${UserName}' account itself." >&2
    exit 1
fi

UserExists=""
if dscl . -read /Users/"${UserName}" >/dev/null 2>&1; then
    UserExists="yes"
fi

if [ -z "${UserExists}" ]; then
    echo "No '${UserName}' user account found — Homebrew doesn't appear to be installed via install.sh's wrapper."
    echo "Nothing to do."
    exit 0
fi

echo "== Step 1: running Homebrew's own uninstall.sh as '${UserName}' =="
# Same invocation shape install.sh used for the installer, pointed at
# Homebrew's official uninstaller instead. NONINTERACTIVE=1 is
# Homebrew's own documented flag for skipping the interactive y/N
# confirmation (equivalent to passing --force) — see
# https://github.com/Homebrew/install/issues/654.
if sudo -Hu "${UserName}" command -v brew >/dev/null 2>&1; then
    sudo -EHu "${UserName}" NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
else
    echo "'${UserName}' has no 'brew' on PATH — Homebrew itself already looks uninstalled, or was never finished installing. Skipping."
fi

echo ""
echo "== Step 2: removing /etc/sudoers.d/homebrew-sudoer =="
if [ -f /etc/sudoers.d/homebrew-sudoer ]; then
    sudo rm -v /etc/sudoers.d/homebrew-sudoer
else
    echo "not present, skipping"
fi

echo ""
echo "== Step 3: removing '${UserName}' from the admin group =="
if dscl . -read /Groups/admin GroupMembership 2>/dev/null | grep -qw "${UserName}"; then
    sudo dscl . -delete /Groups/admin GroupMembership "${UserName}"
    echo "removed"
else
    echo "not a member, skipping"
fi

echo ""
echo "== Step 4: removing ~/.config/homebrew.include =="
# These were written into the CALLING user's home by install.sh (it ran
# these lines without sudo -u pkg), not into ${HomeDir}.
Removed=""
if [ -f ~/.config/homebrew.include ]; then
    rm -v ~/.config/homebrew.include
    Removed="yes"
fi
if [ -f ~/.config/homebrew.include.updated ]; then
    rm -v ~/.config/homebrew.include.updated
    Removed="yes"
fi
if [ -z "${Removed}" ]; then
    echo "not present, skipping"
fi

echo ""
echo "== Step 5: the '${UserName}' user account =="
if [ "${PurgeUser}" = "no" ]; then
    echo "--keep-user given: leaving the '${UserName}' account and ${HomeDir} in place."
elif [ "${PurgeUser}" = "yes" ]; then
    DoPurge="yes"
else
    if [ -t 0 ]; then
        read -r -p "Delete the '${UserName}' user account AND its home directory (${HomeDir})? This cannot be undone. [y/N] " reply
        case "$reply" in
            [Yy]*) DoPurge="yes" ;;
            *) DoPurge="no" ;;
        esac
    else
        DoPurge="no"
    fi
fi

if [ "${DoPurge:-}" = "yes" ]; then
    sudo dscl . -delete /Users/"${UserName}"
    sudo rm -rf "${HomeDir}"
    echo "deleted the '${UserName}' account and ${HomeDir}"
else
    echo "leaving the '${UserName}' account and ${HomeDir} in place."
    echo "To remove them later by hand:"
    echo "    sudo dscl . -delete /Users/${UserName}"
    echo "    sudo rm -rf ${HomeDir}"
fi

echo ""
echo "Done. One thing this script does NOT do: if you added"
echo "    source ~/.config/homebrew.include"
echo "to a shell profile (~/.zprofile, ~/.bash_profile, etc.) as install.sh's"
echo "final message instructed, remove that line yourself — this script"
echo "doesn't know which profile file you put it in."
