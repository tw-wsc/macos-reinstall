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
# 1. Find install in User's desktop
# 2. Confirm the installer size should bigger than 4GB


# User notice
SURETY="$(osascript -e 'display dialog "This laptop will be erased once the installer is available, it will take some time. Please connect to the Internet and make sure it has enough power." with title "Erase macOS" buttons {"Cancel", "Okay"} default button "Okay" with icon caution giving up after 10')"

if [ "$SURETY" = "button returned:Okay, gave up:false" ]; then
    echo "Starting erase-install ..."
else
    echo "Quit"
    exit
fi

# Prevent the display from sleeping
/usr/bin/caffeinate -d &

# URL for downloading installinstallmacos.py
installinstallmacos_URL=https://raw.githubusercontent.com/grahampugh/macadmin-scripts/master/installinstallmacos.py

# Directory in which to place the macOS installer
installer_directory="/Applications"
user=`stat -f "%Su" /dev/console`
desktop="/Users/$user/Desktop"

# Temporary working directory
workdir="/Library/Management/erase-install"
macOSDMG=$( find ${workdir}/*.dmg -maxdepth 1 -type f -print -quit 2>/dev/null )

#Check installer location
installer_app=$( find "${installer_directory}/Install macOS"*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
if [[ "${installer_app}" = "" ]]; then
installer_app=$( find "${desktop}/Install macOS"*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
installer_directory="/Users/$user/Desktop"
fi


# Functions

find_existing_installer() {

    # First let's see if this script has been run before and left an installer
    if [[ -f "${macOSDMG}" ]]; then
        echo "[ $( date ) ] Installer dmg found at: ${macOSDMG}"
        echo "[ $(date) ] Mounting ${macOSDMG}"
        echo
        hdiutil attach "${macOSDMG}"
        installmacOSApp=$( find '/Volumes/Install macOS'*/*.app -maxdepth 1 -type d -print -quit 2>/dev/null )
    # Next see if there's an already downloaded installer
    elif [[ -d "${installer_app}" ]]; then
        #Check installer size
        filesize=$(find "${installer_directory}/Install macOS"*.app -type f -size +4G 2>/dev/null)
        if [[ "${filesize}" = "" ]]; then
            osascript -e 'display dialog "Installer incomplete.\nScript will auto download installer later." with title "macOS installer incomplete" buttons "Okay" default button "Okay" with icon caution'
            return
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

run_installinstallmacos() {
    # Download installinstallmacos.py
    if [[ ! -d "${workdir}" ]]; then
        echo
        echo "[ $(date) ] Making working directory at ${workdir}"
        echo
        mkdir -p ${workdir}
    fi

    curl -o ${workdir}/installinstallmacos.py -s ${installinstallmacos_URL}

    # 3. Use installinstallmacos.py to download the desired version of macOS

    echo "[ $(date) ] Getting current production version from ${workdir}/installinstallmacos.py"
    echo
    # Generate the plist
    python ${workdir}/installinstallmacos.py --workdir ${workdir} --list
    echo

    # Get the number of entries
    plist_count=$( /usr/libexec/PlistBuddy -c 'Print result:' ${workdir}/softwareupdate.plist | grep index | wc -l | sed -e 's/^ *//' )
    echo "[ $(date) ] $plist_count entries found"
    plist_count=$((plist_count-1))

    for index in $( seq 0 $plist_count ); do
        title=$( /usr/libexec/PlistBuddy -c "Print result:${index}:title" ${workdir}/softwareupdate.plist )
        if [[ ${title} != *"Beta"* ]]; then
            build_check=$( /usr/libexec/PlistBuddy -c "Print result:${index}:build" ${workdir}/softwareupdate.plist )
            if [[ $build ]]; then
                build=$( /usr/bin/python -c 'from distutils.version import LooseVersion; build = "'$build'"; build_check = "'$build_check'"; lowest_build = [build if LooseVersion(build) > LooseVersion(build_check) else build_check]; print lowest_build[0]' )
            else
                build=$build_check
            fi
            if [[ $build_check == $build ]]; then
                chosen_title="${title}"
            fi
        fi
    done

    if [[ ! ${build} ]]; then
        echo "[ $(date) ] No valid build found. Exiting"
        exit 1
    else
        echo "[ $(date) ] Build '$build - $chosen_title' found"
    fi

    echo
    # Now run installinstallmacos.py again specifying the build
    python ${workdir}/installinstallmacos.py --workdir "${workdir}" --build ${build} --compress

    # Identify the installer dmg
    macOSDMG=$( find ${workdir} -maxdepth 1 -name 'Install_macOS*.dmg'  -print -quit )
}

# Main body

[[ $1 == "cache" || $4 == "cache" ]] && cache_only="yes" || cache_only="no"

# Look for the installer, download it if it is not present
find_existing_installer
if [[ ! -d "${installmacOSApp}" ]]; then
    run_installinstallmacos
fi

# Now look again
find_existing_installer
if [[ ! -d "${installmacOSApp}" ]]; then
    echo "[ $(date) ] macOS Installer not found, cannot continue"
    exit 1
fi

if [[ ${cache_only} == "yes" ]]; then
    appName=$( basename "$installmacOSApp" )
    if [[ ! -d "${installmacOSApp}" ]]; then
        echo "[ $(date) ] Installer is at: $installmacOSApp"
    fi

    # Unmount the dmg
    existingInstaller=$( find /Volumes -maxdepth 1 -type d -name 'Install macOS*' -print -quit )
    if [[ -d "${existingInstaller}" ]]; then
        diskutil unmount force "${existingInstaller}"
    fi
    # Clear the working directory
    rm -rf "${workdir}/content"
    exit
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
