#!/bin/bash

export UserName=pkg
export GroupName=staff
export HomeDir=/opt/homebrew
export BrewPrefix=x86_64
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

echo "Creating Homebrew installation directory"
if [ ! -d ${HomeDir} ]
then
    sudo mkdir ${HomeDir}
else
    echo "${HomeDir} exists, skipping."
fi

echo "Creating Homebrew install prefix"
if [ ! -d ${HomeDir}/${BrewPrefix} ]
then
    sudo -Hu ${UserName} mkdir -pv ${HomeDir}/${BrewPrefix}
else
    echo "brew installation directory exists, skipping."
fi

echo "Installing Homebrew "
if [ ! -d ${HomeDir}/${BrewPrefix}/.git ]
then
    sudo -Hu ${UserName} git clone https://github.com/Homebrew/brew.git ${HomeDir}/${BrewPrefix}/
else
    echo "brew appears to be installed. Skipping."
fi

echo "Setting file ownerships for ${HomeDir}"
sudo chown -R ${UserName}:${GroupName} ${HomeDir}

echo "Creating sudoer file for Homebrew user ${UserName}"
if [ ! -f /etc/sudoers.d/homebrew-sudoer ]
then
    cat ./templates/homebrew.sudoer | \
        /usr/bin/sed s#__UserName__#${UserName}#g \
        > ${Sudoer_TempFile}
    sudo mv -v ${Sudoer_TempFile} /etc/sudoers.d/homebrew-sudoer
    sudo chown root:wheel /etc/sudoers.d/homebrew-sudoer
fi

if [ ! -f ~/.config/homebrew.include ]
then
    cat ./templates/homebrew.shell.include | \
        /usr/bin/sed s#__HomeDir__#${HomeDir}#g | \
        /usr/bin/sed s#__BrewPrefix__#${BrewPrefix}#g | \
        /usr/bin/sed s#__UserName__#${UserName}#g \
        > ~/.config/homebrew.include
    echo ""
    echo ""
    echo "Secure homebrew setup is complete. To activate brew in your shell, add the following line:"
    echo ""
    echo "source ~/.config/homebrew.include"
    echo ""
    echo "to your shell profile."
fi