#!/bin/bash

export UserName=pkg
export GroupName=staff
export HomeDir=/Users/pkg
export Sudoer_TempFile=$(mktemp)

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

if [ ! -f /etc/sudoers.d/homebrew-sudoer ]
then
    echo "Creating sudoer file for Homebrew user ${UserName}"
    cat ./templates/homebrew.sudoer | \
        /usr/bin/sed s#__UserName__#${UserName}#g \
        > ${Sudoer_TempFile}
    sudo /usr/bin/install -v -o root -g wheel ${Sudoer_TempFile} /etc/sudoers.d/homebrew-sudoer
fi

echo "Installing Homebrew..."
sudo -EHu pkg NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

## Ensure ~/.config is present
if [ ! -d ~/.config ]
then
    mkdir -pv ~/.config
fi

if [ ! -f ~/.config/homebrew.include ]
then
    cp -v ./templates/homebrew.shell.include ~/.config/homebrew.include
    echo ""
    echo ""
    echo "Secure homebrew setup is complete. To activate brew in your shell, add the following line to"
    echo "your shell profile:"
    echo ""
    echo "source ~/.config/homebrew.include"
else
    cp -v ./templates/homebrew.shell.include ~/.config/homebrew.include.updated
    echo ""
    echo ""
    echo "Secure homebrew setup is complete. We found an exiting ~/.config/homebrew.include, so we've"
    echo "placed an updated copy in ~/.config/homebrew.include.updated. To activate brew in your shell,"
    echo "review the differences and replace your current include with the updated copy if desired."
fi

