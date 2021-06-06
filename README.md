Secure Homebrew
===

Simple script to install homebrew for secure usage. Sets up homebrew in /opt/homebrew/x86_64 despite admonitions to the contrary from upstream - `/usr/local` is a poor place to install software for security reasons as well as potential conflicts with many Mac software packages.

Why Should I Install Homebrew This Way?
---

By default, homebrew requires the user to make /usr/local writable by unprivileged account(s). This places the user in harm's way by opening a vector for placement or replacement of brew installed binaries and libraries by bad actors, and can even lead to the override of system libraries and shared object injection if one is not judicious. 

Brew installed packages and changes to the installation path are also not auditable - this is a weakness that _MacPorts_ lacks - because MacPorts requires you to use `sudo`, all package lifecycle actions are tracked.

What The Script Does
---

The script will:

- Create a user `pkg`
    - This user will have no password or remote access/sharing capabilities and exists only for installation of brew packages and casks.
    - For the purpose of cask installation this user does also need to be a sudoer, so be aware of the implications here - but this is the case with homebrew normally, so the risk profile remains much smaller than a default homebrew setup.
- Deploy a shell script wrapper for `brew`
    - This wrapper will execute most query and diagnostic functions of homebrew without changing user ID's or escalating privileges.
    - If `install`, `update`, `upgrade`, `reinstall`, `remove`, etc are executed the script will trap these and execute them as the `pkg` user. This creates an explicit interaction with the user for any modifications to the part of the filesystem hosting third party software and all actions are recorded in the system log.
- Deploy a sudoers file permitting homebrew itself to perform administrative functions without prompting a second time for a user password.
    - The security implications of this are light - the created user has no password or other means of being switched to other than by administrators who can otherwise become root directly.

Usage
---

In order to use this repo you must be able to run `sudo` on your Mac.

1. Check out this repo
1. chmod +x install.sh
1. ./install.sh
    - You will be prompted for your user password
1. The script will place `~/.config/homebrew.include` in your home directory and should work with any Bourne compatible shell. Add the following line to your shell profile in order to start using it:
    - `source ~/.config/homebrew.include`
1. The bash function strives to execute brew without privileges wherever possible - only administrative actions (install, reinstall, update, upgrade, remove, etc) require privilege elevation.