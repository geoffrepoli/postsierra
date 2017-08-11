#!/usr/bin/env bash
set -u
PROJECT=aquamata
IDENTIFIER=com.doggles.$PROJECT

#####                                 #####
####  ::::::::::::::::::::::::::::::\  ####
###   ::    AQUAMATA   |  v0.8.1  ::\   ###
##    ::  -+-+-+-+-+-+-+-+-+-+-+- ::\    ##
#     ::  G E O F F  R E P O L I  ::\     #
##    ::    github.com/doggles    ::\    ##
###   ::::::::::::::::::::::::::::::\   ###
####  \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\  ####
#####                                 #####


##   ----------------------------
##  -  C O N F I G U R A T I O N  -
##   ----------------------------

# ---------------
#   JAMF PARAMETERS
#     ---------------

# :: Installer policy trigger name
# Add to Parameter 4 in Jamf Script editor
TRIGGER="$4"

# :: Explicit path to installer
# Add to Parameter 5 in Jamf Script editor
INSTALLER="$5"

#  -----------------
#    PREINSTALL DIALOG
#      -----------------

# :: jamfHelper header
pre_heading="Please wait while we verify your hardware and download the installer."

# :: jamfHelper message text
pre_description="This process will take approximately 5-10 minutes. Once completed your computer will reboot. You will be prompted to enter your password to begin the upgrade."

# :: jamfHelper icon
pre_icon="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"

# ------------------
#   POSTINSTALL DIALOG
#     ------------------

# :: jamfHelper header
post_heading="Updating configuration settings"

# :: jamfHelper message text
post_description="Your Mac will reboot in a few minutes"

# :: jamfHelper icon
post_icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Sync.icns"

# --------------
#   FAILURE DIALOG
#     --------------

# :: jamfHelper header
fail_heading="Requirements Not Met"

# :: jamfHelper message text
fail_description="We are unable to upgrade your Mac at this time. Please ensure you have at least 20 GB of free space available. Additionally, if you are using a MacBook, check that it is connected to power and try again. If you continue to experience this issue, please contact the help desk."

# :: jamfHelper icon
fail_icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertNoteIcon.icns"

#### xxxx #### ++++ ####
#### ++++ #### xxxx ####
#### xxxx #### ++++ ####

##   --------------------------------------
##  -  R E Q U I R E M E N T S  C H E C K  -
##   --------------------------------------

# Truncate jamfHelper path
jamfHelper()
{
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper "$@"
}

# Get correct jamf binary path
jamf()
{
	if [ -f /usr/local/jamf/bin/jamf ]
	then /usr/local/jamf/bin/jamf "$@"
	else /usr/sbin/jamf "$@"
	fi
}

# Check whether device is on AC or battery
usingPowerAdapter()
{
	if [[ $(pmset -g ps) =~ "AC Power" ]]
	then return 0
	else return 1
	fi
}

# Check free space on disk
enoughFreeSpace()
{
	if (( $(diskutil info / | awk '/Available/ || /Free/ && /Space/{print substr($6,2)}') > 21474836480 ))
	then return 0
	else return 1
	fi
}

##   ---------------------------------------
##  -  P O S T - I N S T A L L  S C R I P T  -
##   ---------------------------------------

if usingPowerAdapter && enoughFreeSpace; then

	mkdir /usr/local/$PROJECT
	cat > /usr/local/$PROJECT/postinstall.sh <<-POSTINSTALL
	#!/usr/bin/env bash

	# Insert required postinstall tasks/policies/commands
	postinstallItems()
	{
		# USER-CONFIGURABLE
		# COMMANDS GO HERE
	}

	# Truncate jamfHelper path
	jamfHelper()
	{
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper "$@"
	}

	# Get correct jamf binary path
	jamf()
	{
		if [ -f /usr/local/jamf/bin/jamf ]
		then /usr/local/jamf/bin/jamf "$@"
		else /usr/sbin/jamf "$@"
		fi
	}

	# Check if Finder is running, signaling user is logged in
	userLoggedIn()
	{
		pgrep Finder && return 0 || return 1
	}

	# Unload daemon and remove all associated files
	removeDaemon()
	{
		rm -rf "$INSTALLER"
		rm -rf /usr/local/$PROJECT
		rm -f /Library/LaunchDaemons/$IDENTIFIER.plist
		launchctl unload -w /Library/LaunchDaemons/$IDENTIFIER.plist
	}

	# run removeDaemon() + Reboot
	cleanup()
	{
		removeDaemon
		shutdown -r now
	}

	if userLoggedIn && [ ! -f /var/tmp/${PROJECT}_done ]; then
		jamfHelper \\															# Launch jamfHelper curtain
			-windowType fs \\
			-heading "$post_heading" \\
			-description "$post_description" \\
			-icon "$post_icon" \\
			-lockHUD &
		postinstallItems													# Start postinstall workflow
		jamf recon																# Update computer inventory with JSS
		touch /var/tmp/${PROJECT}_done						# Create completion file
		trap 'cleanup' EXIT												# Remove launch daemon on script exit and reboot
	elif [ -f /var/tmp/${PROJECT}_done ]; then
		trap 'removeDaemon' EXIT									# Remove daemon and install files, no reboot
	fi
	exit
	POSTINSTALL

	chown root:wheel /usr/local/$PROJECT/postinstall.sh
	chmod +x /usr/local/$PROJECT/postinstall.sh

##   ----------------------------
##  -  L A U N C H  D A E M O N  -
##   ----------------------------

	cat > /Library/LaunchDaemons/$IDENTIFIER.plist <<-PLIST
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
  		<key>Label</key>
  		<string>$IDENTIFIER</string>
  		<key>StartInterval</key>
  		<integer>10</integer>
  		<key>RunAtLoad</key>
  		<true/>
  		<key>ProgramArguments</key>
  		<array>
  			<string>/usr/local/$PROJECT/postinstall.sh</string>
  		</array>
	</dict>
	</plist>
	PLIST

	chown root:wheel /Library/LaunchDaemons/$IDENTIFIER.plist
	chmod 644 /Library/LaunchDaemons/$IDENTIFIER.plist

##   -------------------
##  -  L A U N C H E R  -
##   -------------------

	jamfHelper \
		-windowType fs \
		-icon "$pre_icon" \
		-heading "$pre_heading" \
		-description "$pre_description" \
		-iconSize 100 \
		-lockHUD &
	pid=$!
	jamf policy -trigger "$TRIGGER"
	"$INSTALLER"/Contents/Resources/startosinstall \
		--applicationpath "$INSTALLER" \
		--nointeraction \
		--pidtosignal $pid &
	sleep 3

else

	jamfHelper \
		-windowType utility \
		-icon "$fail_icon" \
		-heading "$fail_heading" \
		-description "$fail_description" \
		-button1 "OK" \
		-defaultButton 1

fi

exit
