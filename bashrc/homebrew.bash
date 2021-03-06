export PATH=${HomeDir}/${BrewPrefix}/bin:${HomeDir}/${BrewPrefix}/sbin:${PATH}

brew() {
    ## Debugging stuff
    # echo "1 = $1"
    # echo "2 = $2"
    # echo "${@:2}"
    if [[ $1 == "search" ]]
    then
        command brew search "${@:2}"
    elif [[ $1 == "--prefix" ]]
    then
        command brew --prefix "${@:2}"
    elif [[ $1 == "--help" ]]
    then
        command brew --help "${@:2}"
    elif [[ $1 == "list" ]]
    then
        command brew list "${@:2}"
    elif [[ $1 == "info" ]]
    then
        command brew info "${@:2}"
    elif [[ $1 == "formulae" ]]
    then
        command brew formulae "${@:2}"
    elif [[ $1 == "casks" ]]
    then
        command brew casks "${@:2}"
    elif [[ $1 == "config" ]]
    then
        command brew config "${@:2}"
    elif [[ $1 == "doctor" ]]
    then
        command brew doctor "${@:2}"
    else
        command sudo -Hu ${UserName} brew "$@"
    fi
}