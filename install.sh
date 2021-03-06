#!/bin/bash

export UserName=pkg
export GroupName=staff
export HomeDir=/opt/homebrew
export BrewPrefix=x86_64

LastID=$(dscl . -list /Users UniqueID | awk '{print $2}' | sort -n | tail -1)
NextID=$((LastID + 1))
StaffGID=$(dscl . -read /Groups/staff PrimaryGroupID | awk '{print $2}')

if dscl . list /Users/${UserName}
then
    echo "User ${UserName} exists. Skipping."
else
    echo "Creating user ${UserName}"
    sudo dscl . create /Users/${UserName}
    sudo dscl . create /Users/${UserName} RealName "${UserName} Account"
    sudo dscl . create /Users/${UserName} UniqueID ${NextID}
    sudo dscl . create /Users/${UserName} PrimaryGroupID ${StaffGID}
    sudo dscl . create /Users/${UserName} UserShell /bin/bash
    sudo dscl . create /Users/${UserName} NFSHomeDirectory ${HomeDir}
    sudo dscl . -append /Groups/admin GroupMembership ${UserName}
fi

if [ ! -d ${HomeDir} ]
then
    sudo mkdir ${HomeDir}
    sudo chown -R ${UserName}:${GroupName} ${HomeDir}
else
    echo "${HomeDir} exists, skipping."
fi

if [ ! -d ${HomeDir}/${BrewPrefix} ]
then
    sudo -Hu ${UserName} mkdir -pv ${HomeDir}/${BrewPrefix}
else
    echo "brew installation directory exists, skipping."
fi

if [ ! -d ${HomeDir}/${BrewPrefix}/.git ]
then
    sudo -Hu ${UserName} git clone https://github.com/Homebrew/brew.git ${HomeDir}/${BrewPrefix}/
else
    echo "brew apears to be installed. Skipping."
    # exit 0
fi

if [ ! -f ~/.config/homebrew.bash ]
then
    cat ./bashrc/homebrew.bash | envsubst '${HomeDir} ${BrewPrefix} ${UserName}' > ~/.config/homebrew.bash
    echo ""
    echo ""
    echo "Secure homebrew setup is complete. To activate brew in your shell, add the following line:"
    echo ""
    echo "source ~/.config/homebrew.bash"
    echo ""
    echo "to your bash profile."
fi