#!/usr/bin/env bash
set -u

#####                                 #####
####  ::::::::::::::::::::::::::::::\  ####
###   ::   MACUPDATER  |  v0.6.1  ::\   ###
##    ::  -+-+-+-+-+-+-+-+-+-+-+- ::\    ##
#     ::  G E O F F  R E P O L I  ::\     #
##    ::  github.com/geoffrepoli  ::\    ##
###   ::::::::::::::::::::::::::::::\   ###
####  \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\  ####
#####                                 #####


##   ----------------------------
##  -  C O N F I G U R A T I O N  -
##   ----------------------------

# -------------
#   MAIN OPTIONS
#    -------------

# [ 1A ] macOS Policy Trigger
trigger_name="$4"

# [ 1B ] Launch Daemon plist
launch_daemon="$5"

# [ 1C ] Installer app explicit path
app_path="$6"

#  -------------------
#    PREINSTALL OPTIONS
#     -------------------

# [ 2A ] Heading to be used for userDialog
pre_heading="Please wait while we verify your hardware and download the installer."

# [2B ] Title to be used for userDialog
pre_description="
This process will take approximately 5-10 minutes.
Once completed your computer will reboot. You will be prompted to enter your password to begin the upgrade."

# [ 2C ] Icon to be used for userDialog
pre_icon="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"

# --------------------
#   POSTINSTALL OPTIONS
#    --------------------

# [ 3A ] Post-install Heading
post_heading="Updating configuration settings..."

# [ 3B ] Post-install Description
post_description="Your Mac will reboot in a few minutes"

# [ 3C ] Post-install Icon
post_icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Sync.icns"


#### xxxx #### ++++ ####
#### ++++ #### xxxx ####
#### xxxx #### ++++ ####


##   ----------------------------
##  -  S Y S T E M  C H E C K S  -
##   ----------------------------

# Check whether device is on AC or battery
[[ $(pmset -g ps) =~ "AC Power" ]] && power_adapter=true || power_adapter=false

# Check free space on disk
[[ $(sw_vers -productVersion | awk -F. '{print $2}') -ge 12 ]] && free_space=$(diskutil info / | grep "Available Space" | awk '{print $4}') || free_space=$(diskutil info / | grep "Free Space" | awk '{print $4}')

[[ ${free_space%.*} -ge 15 ]] && space_available=true || space_available=false


##   ---------------------------------------
##  -  P O S T - I N S T A L L  S C R I P T  -
##   ---------------------------------------


if $power_adapter && $space_available; then

    mkdir /usr/local/"${launch_daemon%.*}"
    cat >/usr/local/"${launch_daemon%.*}"/postinstall.sh <<-POSTINSTALL
    #!/usr/bin/env bash

    # Check if Finder is running, signaling user is logged in
    userLoggedIn()
    {
        pgrep Finder && return 0 || return 1
    }

    # Insert required postinstall tasks/policies/commands
    runPostinstallTasks()
    {
        /usr/local/jamf/bin/jamf policy -trigger triggername
        /usr/sbin/softwareupdate --install --recommended
    }

    # Remove the launch daemon with an EXIT trap
    removeDaemon()
    {
        rm -f "/Library/LaunchDaemons/${launch_daemon:?}"
        launchctl unload "/Library/LaunchDaemons/$launch_daemon"
    }

    # Remove macOS Installer and postinstall directory
    removeInstaller()
    {
        local launch_daemon="${launch_daemon%.*}"
        rm -rf "$app_path"
        rm -rf "/usr/local/${launch_daemon:?}"
    }

    # Preemptive double-check to prevent daemon from looping if computer is shutdown before daemon is removed
    postinstallCleanup()
    {
        removeInstaller
        removeDaemon
    }

    if userLoggedIn && [[ ! -f "/var/tmp/.${launch_daemon%.*}.done" ]]; then

        # Launch jamfHelper curtain
        "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType fs -heading "$post_heading" -description "$post_description" -icon "$post_icon" -lockHUD &

        # Start postinstall workflow
        runPostinstallTasks

        # Remove macOS installer app
        removeInstaller

        # Update computer inventory with JSS
        /usr/local/jamf/bin/jamf recon

        # Create completion file
        touch "/var/tmp/.${launch_daemon%.*}.done"

        # Remove launch daemon on script exit and then reboot immediately
        trap "removeDaemon" EXIT
        shutdown -r now

    elif [[ -f "/var/tmp/.${launch_daemon%.*}.done" ]]; then

        postinstallCleanup

    fi

    exit
POSTINSTALL

    chown root:wheel /usr/local/"${launch_daemon%.*}"/postinstall.sh
    chmod +x /usr/local/"${launch_daemon%.*}"/postinstall.sh


##   ----------------------------
##  -  L A U N C H  D A E M O N  -
##   ----------------------------


    cat >/Library/launch_daemons/"$launch_daemon" <<-PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>${launch_daemon%.*}</string>
        <key>StartInterval</key>
        <integer>10</integer>
        <key>RunAtLoad</key>
        <true/>
        <key>ProgramArguments</key>
        <array>
            <string>/usr/local/${launch_daemon%.*}/postinstall.sh</string>
        </array>
    </dict>
    </plist>
PLIST

    chown root:wheel /Library/LaunchDaemons/"$launch_daemon"
    chmod 644 /Library/LaunchDaemons/"$launch_daemon"


##   -------------------------
##  -  A P P L I C A T I O N  -
##   -------------------------


    # Launch jamfHelper
    echo "Launching jamfHelper as Utility Window..."
    "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType fs -icon "$pre_icon" -heading "$pre_heading" -description "$pre_description" -iconSize 100 -lockHUD &
    pid=$!

    # Cache Installer
    echo "Copying Sierra app to target..."
    /usr/local/jamf/bin/jamf policy -trigger "$trigger_name"

    # Begin Upgrade
    echo "Launching startosinstall..."
    "$app_path"/Contents/Resources/startosinstall --app_path "$app_path" --nointeraction --pidtosignal "$pid" &
    sleep 3

else

    "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" -windowType utility -icon "$pre_icon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for macOS Sierra. Please ensure you are connected to power and that you have at least 15GB of Free Space.

    If you continue to experience this issue, please contact the Service Desk" -iconSize 100 -button1 "OK" -defaultButton 1

fi

exit
