#!/bin/bash

# erase-install
#
#
# WARNING. This is a self-destruct script. Do not try it out on your own device!
#
#
# Specifically, this script does the following:
# 1. Checks whether a valid existing macOS installer (>= 10.13.4) is already present in the `/Applications` folder
# 2. If run without an argument, runs `startosinstall --eraseinstall` with the relevant options in order to wipe the drive and reinstall macOS.
#
# Requirements:
# macOS 10.13.4+ is already installed on the device
# Device file system is APFS
#
# Feature added by Ma Jin(jinma@thoughtworks.com) on 27.08.2018
# 1. User notice
# 2. Prevent the display from sleeping
# 3. Check Bootcamp and delete it if exist
# 4. Clear old install logs
# 5. Send laptop data wipe email

# Feature added by Zhang Jian(jnzhang@thoughtworks.com) on 4.12.2018
# 1. User notice
# 2. Prevent the display from sleeping


# User notice
SURETY="$(osascript -e 'display dialog "This laptop will be erased once the downloading is completed, it will take some time. \nPlease connect to the Internet and make sure it has enough power." with title "Erase macOS" buttons {"Cancel", "Okay"} default button "Okay" with icon caution giving up after 10')"

if [ "$SURETY" = "button returned:Okay, gave up:false" ]; then
    echo "Starting erase-install ..."
else
    echo "Quit"
    exit
fi

# Prevent the display from sleeping
/usr/bin/caffeinate -d &

# Directory in which to place the macOS installer
installer_directory="/Applications"
user=`stat -f "%Su" /dev/console`
desktop="/Users/$user/Desktop"
filesize=$(find "${installer_directory}/Install macOS"*.app -type f -size +1G 2>/dev/null)
# Temporary working directory
workdir="/Library/Management/erase-install"

macOSDMG=$( find ${workdir}/*.dmg -maxdepth 1 -type f -print -quit 2>/dev/null )

# Functions

find_existing_installer() {
    #Check installer location
    installer_app=$( find "${installer_directory}/Install macOS"*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
    if [[ "${installer_app}" = "" ]]; then
      installer_app=$( find "${desktop}/Install macOS"*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
      installer_directory="/Users/$user/Desktop"
    fi
    # First let's see if there's an already downloaded installer
    if [[ -d "${installer_app}" ]]; then
        #Check installer size
        if [[ "${filesize}" = "" ]]; then
#          osascript -e 'display dialog "安装文件不完整，请删除已下载的安装文件后重新下载. 联系techops-support@thoughtworks.com获得更多帮助." with title "安装文件效验失败" buttons "Okay" default button "Okay" with icon caution'
          osascript -e 'display dialog "Installer incomplete.\nPlease remove the installer and download again.\n\nEmail to techops-support@thoughtworks.com for more help." with title "macOS installer incomplete" buttons "Okay" default button "Okay" with icon caution'
          exit
        fi
        # make sure it is 10.13.4 or newer so we can use --eraseinstall
        installer_version=$( /usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "${installer_app}/Contents/Info.plist" 2>/dev/null | cut -c1-3 )
        if [[ ${installer_version} > 133 ]]; then
            echo "[ $( date ) ] Valid installer found. No need to download."
            installmacOSApp="${installer_app}"
        else
            echo "[ $( date ) ] Installer too old."
        fi
    else
        echo "[ $( date ) ] No valid installer found."
    fi
}


# Now look again
find_existing_installer
if [[ ! -d "${installmacOSApp}" ]]; then
    echo "[ $(date) ] macOS Installer not found, cannot continue"
    exit 1
fi

# Check Bootcamp and delete it if exist
Bootcamp="$(diskutil list internal |grep BOOTCAMP | awk '{print $8}')"
Container="$(diskutil list internal |grep Apple_APFS | awk '{print $7}')"

if [ -n "$Bootcamp" ]; then
echo "BOOTCAMP found on $Bootcamp, start formatting!"
diskutil eraseVolume free n $Bootcamp
diskutil apfs resizeContainer $Container 0
else
echo "No BOOTCAMP found!"
fi

# Clear old install logs
echo > /var/log/install.log

#check wifi status
rts=1
until [[ "$rts" -eq 0 ]]
do
    /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | grep running
    rts=$?
done

# Send laptop data wipe email
system_profiler SPHardwareDataType | grep "Serial Number" | awk '{ print "echo \047"$0"\047 | mail -s \047"$4" has been wiped\047 \047techopscn-security@thoughtworks.com\047"}' | bash

# 5. Run the installer
echo "[ $(date) ] WARNING! Running ${installmacOSApp} with eraseinstall option"
echo

"${installmacOSApp}/Contents/Resources/startosinstall" --applicationpath "${installmacOSApp}" --eraseinstall --agreetolicense --nointeraction
