#!/bin/bash

export UserName=pkg
export GroupName=staff
export HomeDir=/Users/pkg
export Sudoer_TempFile=$(mktemp)

CasksOnly=0
for arg in "$@"
do
    case "$arg" in
        --casks-only)
            CasksOnly=1
            ;;
        *)
            echo "Unknown argument: ${arg}" >&2
            exit 1
            ;;
    esac
done

LastID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
NextID=$((LastID + 1))
StaffGID=$(dscl . -read /Groups/staff PrimaryGroupID | awk '{print $2}')

if dscl . list /Users/${UserName}
then
    echo "User ${UserName} exists. Skipping."
else
    sudo dscl . create /Users/${UserName}
    sudo dscl . create /Users/${UserName} RealName "${UserName} Account"
    sudo dscl . create /Users/${UserName} UniqueID ${NextID}
    sudo dscl . create /Users/${UserName} PrimaryGroupID ${StaffGID}
    sudo dscl . create /Users/${UserName} UserShell /bin/bash
    sudo dscl . create /Users/${UserName} NFSHomeDirectory ${HomeDir}
    sudo dscl . -append /Groups/admin GroupMembership ${UserName}
fi

# dscl only creates the user RECORD — it never creates the actual home
# directory on disk, and /Users itself isn't writable by ${UserName}
# even as an admin-group member (only root can mkdir directly under
# it). Confirmed against a real failure: Homebrew running as ${UserName}
# couldn't create its own cache dir ("mkdir: /Users/pkg: Permission
# denied") because ${HomeDir} never existed at all. This check runs
# unconditionally (not just in the branch above) so it also repairs an
# existing ${UserName} account from before this fix existed, like the
# one that just hit that failure.
if [ ! -d "${HomeDir}" ]
then
    echo "Creating home directory for ${UserName}..."
    sudo createhomedir -c -u ${UserName}
    if [ ! -d "${HomeDir}" ]
    then
        echo "Failed to create home directory ${HomeDir} for ${UserName} — aborting." >&2
        exit 1
    fi
fi

if [ ! -f /etc/sudoers.d/homebrew-sudoer ]
then
    echo "Creating sudoer file for Homebrew user ${UserName}"
    cat ./templates/homebrew.sudoer | \
        /usr/bin/sed s#__UserName__#${UserName}#g \
        > ${Sudoer_TempFile}
    sudo /usr/bin/install -v -o root -g wheel ${Sudoer_TempFile} /etc/sudoers.d/homebrew-sudoer
fi

echo "Installing Homebrew..."
HostArch=$(uname -m)
if [ "$HostArch" = "arm64" ]
then
    HomebrewPrefix=/opt/homebrew
    sudo -EHu ${UserName} NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    HomebrewInstallStatus=$?
else
    # Homebrew's official installer hard-aborts on anything but arm64
    # ("Homebrew on macOS is only supported on Apple Silicon
    # processors!") with no override flag — confirmed against its
    # current source. Homebrew itself still runs on Intel (demoted to
    # Tier 3 upstream: works, just unsupported), so bootstrap it
    # directly as the unprivileged ${UserName} user rather than the
    # gatekept installer script.
    #
    # This CANNOT reuse /opt/homebrew (the arm64 path above) — Homebrew
    # hard-refuses to run on an Intel processor when installed at its
    # own ARM default prefix ("Cannot install on Intel processor in
    # ARM default prefix (/opt/homebrew)!"), confirmed against a real
    # failure, and there is no environment variable or flag to bypass
    # that check (confirmed against Homebrew's own reports/behavior —
    # every fix anyone's found is to use a prefix that ISN'T one of its
    # two hardcoded defaults, /opt/homebrew or /usr/local). So Intel
    # gets its own non-default prefix here, owned entirely by
    # ${UserName}, same privilege-separation story as the arm64 path.
    #
    # This MUST be a real `git clone`, not a tarball — confirmed
    # against a real "Homebrew's master branch is no longer supported"
    # / "fatal: not a git repository" failure from a tarball-only
    # bootstrap (a plain tarball has no .git at all, and Homebrew
    # itself depends on git — for its own `brew update` self-repair,
    # and for tap/cask-repo management generally). Homebrew/brew's
    # default branch is `main` (confirmed against the live repo), so a
    # fresh clone checks that out directly with no master/main
    # migration to worry about.
    HomebrewPrefix=/opt/homebrew/x86_64
    echo "Host architecture is ${HostArch}, not arm64 — Homebrew's official installer refuses Intel Macs"
    echo "outright (no override flag exists). Bootstrapping Homebrew manually into ${HomebrewPrefix} instead"
    echo "(a non-default prefix, since Homebrew hard-refuses Intel at its own /opt/homebrew ARM default —"
    echo "confirmed no override exists for that either). Tier 3 upstream / unsupported, but functional."
    if [ -d "${HomebrewPrefix}/.git" ]
    then
        echo "Homebrew already bootstrapped at ${HomebrewPrefix} (found .git) — skipping re-clone."
        HomebrewInstallStatus=0
    else
        sudo mkdir -p "${HomebrewPrefix}"
        sudo chown -R ${UserName}:${GroupName} "${HomebrewPrefix}"
        sudo -EHu ${UserName} git clone https://github.com/Homebrew/brew "${HomebrewPrefix}"
        HomebrewInstallStatus=$?
    fi
fi

if [ "$HomebrewInstallStatus" -ne 0 ]
then
    echo "" >&2
    echo "Homebrew installation into ${HomebrewPrefix} failed (see output above) — aborting before" >&2
    echo "touching your shell config." >&2
    exit 1
fi

## Ensure ~/.config is present
if [ ! -d ~/.config ]
then
    mkdir -pv ~/.config
fi

# Casks-only mode traps `install`/`reinstall`/`upgrade`/`tap`/`bundle` in
# the shell function itself (see brew-cask-only.sh) before anything ever
# reaches the pkg-user `brew`, rather than gating at the sudoers/dscl
# level below — deploy both the gating script and an include that wires
# it up with BREW_SUDO_USER=${UserName} so it still runs the real brew
# as the unprivileged account, exactly like the plain include does.
if [ "$CasksOnly" = "1" ]
then
    cp -v ./brew-cask-only.sh ~/.config/brew-cask-only.sh
    IncludeTemplate=./templates/homebrew.shell.include.casks-only
else
    IncludeTemplate=./templates/homebrew.shell.include
fi

IncludeTempFile=$(mktemp)
cat ${IncludeTemplate} | \
    /usr/bin/sed -e s#__UserName__#${UserName}#g -e s#__HomebrewPrefix__#${HomebrewPrefix}#g \
    > ${IncludeTempFile}

if [ ! -f ~/.config/homebrew.include ]
then
    cp -v ${IncludeTempFile} ~/.config/homebrew.include
    echo ""
    echo ""
    if [ "$CasksOnly" = "1" ]
    then
        echo "Secure homebrew setup is complete (casks-only). To activate brew in your shell, add the"
        echo "following line to your shell profile:"
    else
        echo "Secure homebrew setup is complete. To activate brew in your shell, add the following line to"
        echo "your shell profile:"
    fi
    echo ""
    echo "source ~/.config/homebrew.include"
    if [ "$CasksOnly" = "1" ] && [ "$HostArch" != "arm64" ]
    then
        echo ""
        echo "Note: casks-only mode doesn't add ${HomebrewPrefix}/bin to your PATH (the brew wrapper already"
        echo "invokes it by full path), and this Intel bootstrap didn't run the official installer's own PATH"
        echo "setup either. If you also want brew-installed cask binaries directly on your PATH, add:"
        echo ""
        echo "export PATH=\"${HomebrewPrefix}/bin:\$PATH\""
    fi
else
    cp -v ${IncludeTempFile} ~/.config/homebrew.include.updated
    echo ""
    echo ""
    if [ "$CasksOnly" = "1" ]
    then
        echo "Secure homebrew setup is complete (casks-only). We found an existing ~/.config/homebrew.include,"
        echo "so we've placed an updated copy in ~/.config/homebrew.include.updated. To activate brew in your"
        echo "shell, review the differences and replace your current include with the updated copy if desired."
    else
        echo "Secure homebrew setup is complete. We found an exiting ~/.config/homebrew.include, so we've"
        echo "placed an updated copy in ~/.config/homebrew.include.updated. To activate brew in your shell,"
        echo "review the differences and replace your current include with the updated copy if desired."
    fi
    if [ "$CasksOnly" = "1" ] && [ "$HostArch" != "arm64" ]
    then
        echo ""
        echo "Note: casks-only mode doesn't add ${HomebrewPrefix}/bin to your PATH (the brew wrapper already"
        echo "invokes it by full path), and this Intel bootstrap didn't run the official installer's own PATH"
        echo "setup either. If you also want brew-installed cask binaries directly on your PATH, add:"
        echo ""
        echo "export PATH=\"${HomebrewPrefix}/bin:\$PATH\""
    fi
fi
