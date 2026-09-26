#!/bin/bash
# brew-cask-only.sh — makes Homebrew refuse to install/reinstall/upgrade
# formulae or tap non-cask taps, while leaving cask operations untouched.
#
# WHY THIS EXISTS: modern Homebrew fetches formula metadata over its JSON
# API rather than through a locally cloned homebrew/core tap, so `brew
# untap homebrew/core` does NOT block formula installs — the tap was
# never in the install path to begin with once the API is in use.
# Homebrew itself has no "casks only" setting. This wrapper is the only
# thing that actually holds: a shell function named `brew` that inspects
# the command before handing off to the real `brew` binary.
#
# INSTALL: add this line near the end of ~/.zshrc (or ~/.bashrc, if
# you're on bash):
#
#     source ~/.brew-cask-only.sh
#
# (copy this file to ~/.brew-cask-only.sh first, or point `source` at
# wherever you keep it), then open a new terminal or run
# `source ~/.zshrc` in your current one.
#
# ESCAPE HATCH: if you genuinely need a formula install once (some
# formula-only dependency, a one-off), prefix the command with
# BREW_ALLOW_FORMULA=1:
#
#     BREW_ALLOW_FORMULA=1 brew install wget
#
# This function only exists in your interactive shell — it has no effect
# on Homebrew itself, scripts that call `brew` with an absolute path, or
# any other user/shell on the machine.
#
# PRIVILEGE-SEPARATED HOMEBREW SETUPS (e.g. a dedicated unprivileged
# `pkg` user running the actual `brew` binary): set BREW_SUDO_USER to
# that account's name before sourcing this file, and every real
# invocation below runs as `sudo -EHu "$BREW_SUDO_USER" ... ` instead of
# a plain `command brew ...`. Optionally also set BREW_BIN to the real
# binary's full path (e.g. /opt/homebrew/bin/brew) so that invocation
# doesn't depend on `brew` being resolvable on the sudo'd-to user's own
# PATH — it defaults to the bare name `brew` if left unset. Leave
# BREW_SUDO_USER unset entirely for a normal, single-user Homebrew
# install — behavior is unchanged from before either of these existed.
#
# If this shell previously sourced a plain `alias brew=...` (e.g. this
# repo's non-casks-only homebrew.include, sourced earlier in the same
# session from your shell rc), that alias has to go before `brew()` can
# be defined below — bash/zsh alias-expand a word before checking
# whether it's a function definition, so `brew() {` after an existing
# `alias brew=...` is a parse error ("defining function based on alias
# `brew'"), not a runtime one. Confirmed against a real switch from the
# plain to the casks-only include inside an already-open terminal.
unalias brew 2>/dev/null || true

_brew_cask_only_real() {
    if [ -n "${BREW_SUDO_USER:-}" ]; then
        sudo -EHu "$BREW_SUDO_USER" "${BREW_BIN:-brew}" "$@"
    else
        command brew "$@"
    fi
}

brew() {
    if [ "${BREW_ALLOW_FORMULA:-0}" = "1" ]; then
        _brew_cask_only_real "$@"
        return $?
    fi

    local subcmd="$1"

    case "$subcmd" in
        install|reinstall|upgrade)
            shift
            local args=("$@")
            local has_cask=0
            local has_formula=0
            local a
            for a in "${args[@]}"; do
                case "$a" in
                    --cask) has_cask=1 ;;
                    --formula) has_formula=1 ;;
                esac
            done

            if [ "$has_formula" = "1" ]; then
                echo "brew: formula installs are blocked on this machine" \
                     "(MacPorts/portcask handles everything that isn't a cask)." \
                     "Use BREW_ALLOW_FORMULA=1 brew $subcmd ... to override just this once." >&2
                return 1
            fi

            if [ "$has_cask" != "1" ]; then
                echo "brew: refusing 'brew $subcmd' without --cask on this machine." \
                     "Re-run as: brew $subcmd --cask ${args[*]}" \
                     "(or BREW_ALLOW_FORMULA=1 brew $subcmd ... to override just this once)." >&2
                return 1
            fi

            _brew_cask_only_real "$subcmd" "${args[@]}"
            ;;

        tap)
            shift
            local a
            for a in "$@"; do
                case "$a" in
                    homebrew/cask|homebrew/cask-fonts|homebrew/cask-versions|homebrew/cask-drivers) ;;
                    -*) ;;  # flags like --force-auto-update are fine
                    *)
                        echo "brew: refusing to tap '$a' — only cask-related taps are" \
                             "allowed on this machine." \
                             "Use BREW_ALLOW_FORMULA=1 brew tap ... to override just this once." >&2
                        return 1
                        ;;
                esac
            done
            _brew_cask_only_real tap "$@"
            ;;

        bundle)
            echo "brew: 'brew bundle' is blocked on this machine — a Brewfile can" \
                 "silently install formulae alongside casks. Install casks one at a" \
                 "time with 'brew install --cask <name>', or run" \
                 "BREW_ALLOW_FORMULA=1 brew bundle ... to override just this once." >&2
            return 1
            ;;

        *)
            # Everything else (list, info, search, update, doctor, cask,
            # cleanup, uninstall, outdated, config, --version, ...)
            # passes straight through untouched.
            _brew_cask_only_real "$@"
            ;;
    esac
}
