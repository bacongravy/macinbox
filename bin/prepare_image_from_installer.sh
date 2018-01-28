#!/bin/sh -e

# required arguments

INSTALLER_APP="$1"
OUTPUT_PATH="$2"

# optional arguments

MACINBOX_DISK_SIZE=${MACINBOX_DISK_SIZE:-64}
MACINBOX_SHORT_NAME=${MACINBOX_SHORT_NAME:-vagrant}
MACINBOX_FULL_NAME=${MACINBOX_FULL_NAME:-$MACINBOX_SHORT_NAME}
MACINBOX_PASSWORD=${MACINBOX_PASSWORD:-$MACINBOX_SHORT_NAME}
MACINBOX_AUTO_LOGIN=${MACINBOX_AUTO_LOGIN:-true}

#####

log_info() {
	echo "   \033[0;32m-- $*\033[0m" 1>&2
}

log_error() {
	echo "   \033[0;31m-- $*\033[0m" 1>&2
}

bail() {
	log_error "$1"
	exit 1
}

if [ $(id -u) -ne 0 -o -z "${SUDO_USER}" ]; then
	bail "Script must be run as root with sudo."
fi

#####

VMWARE_FUSION_APP=${VMWARE_FUSION_APP:-$(mdfind 'kMDItemCFBundleIdentifier == com.vmware.fusion' | head -1)}

if [ -z "${VMWARE_FUSION_APP}" ]; then
	VMWARE_FUSION_APP="/Applications/VMware Fusion.app"
fi

if [ ! -e "${VMWARE_FUSION_APP}" ]; then
	bail "VMware Fusion not found."
fi

if [ -z "${INSTALLER_APP}" ]; then
	bail "No installer app specified."
fi

if [ ! -e "${INSTALLER_APP}" ]; then
	bail "Installer app not found."
fi

if [ -z "${OUTPUT_PATH}" ]; then
	bail "No output path specified."
fi

######

TEMP_DIR="$(/usr/bin/mktemp -d -t prepare_image_from_installer)"

INSTALL_INFO_PLIST="${INSTALLER_APP}/Contents/SharedSupport/InstallInfo.plist"

SCRATCH_IMAGE="${TEMP_DIR}/scratch.sparseimage"
SCRATCH_MOUNTPOINT="${TEMP_DIR}/scratch_mountpoint"

SCRATCH_VMHGFS_FILESYSTEM_RESOURCES="${SCRATCH_MOUNTPOINT}/Library/Filesystems/vmhgfs.fs/Contents/Resources"
SCRATCH_SPC_KEXTPOLICY="${SCRATCH_MOUNTPOINT}/private/var/db/SystemPolicyConfiguration/KextPolicy"
SCRATCH_INSTALLER_CONFIGURATION_FILE="${SCRATCH_MOUNTPOINT}/private/var/db/.InstallerConfiguration"
SCRATCH_SUDOERS_D="${SCRATCH_MOUNTPOINT}/private/etc/sudoers.d"
SCRATCH_LAUNCHD_DISABLED_PLIST="${SCRATCH_MOUNTPOINT}/private/var/db/com.apple.xpc.launchd/disabled.plist"
SCRATCH_RC_INSTALLER_CLEANUP="${SCRATCH_MOUNTPOINT}/private/etc/rc.installer_cleanup"
SCRATCH_RC_VAGRANT="${SCRATCH_MOUNTPOINT}/private/etc/rc.vagrant"

VMWARE_TOOLS_IMAGE="${VMWARE_FUSION_APP}/Contents/Library/isoimages/darwin.iso"
VMWARE_TOOLS_MOUNTPOINT="${TEMP_DIR}/vmware_tools_mountpoint"
VMWARE_TOOLS_PACKAGE="${VMWARE_TOOLS_MOUNTPOINT}/Install VMware Tools.app/Contents/Resources/VMware Tools.pkg"
VMWARE_TOOLS_PACKAGE_DIR="${TEMP_DIR}/vmware_tools_package"

#####

mkdir "${SCRATCH_MOUNTPOINT}"
mkdir "${VMWARE_TOOLS_MOUNTPOINT}"

cleanup() {
	trap - EXIT INT TERM
	hdiutil detach -quiet -force "${SCRATCH_MOUNTPOINT}" > /dev/null 2>&1 || true
	hdiutil detach -quiet -force "${VMWARE_TOOLS_MOUNTPOINT}" > /dev/null 2>&1 || true
	rm -rf "${TEMP_DIR}" > /dev/null 2>&1 || true
	[[ $SIG == EXIT ]] || kill -$SIG $$ || true
}

for sig in EXIT INT TERM; do
	trap "SIG=$sig; cleanup;" $sig
done

#####

log_info "Checking macOS versions..."

if [ ! -e "${INSTALL_INFO_PLIST}" ]; then
	bail "InstallInfo.plist not found in installer app bundle"
fi

INSTALLER_OS_VERS=$(/usr/libexec/PlistBuddy -c 'Print :System\ Image\ Info:version' "${INSTALL_INFO_PLIST}")
INSTALLER_OS_VERS_MAJOR=$(echo ${INSTALLER_OS_VERS} | awk -F "." '{print $1}')
INSTALLER_OS_VERS_MINOR=$(echo ${INSTALLER_OS_VERS} | awk -F "." '{print $2}')
INSTALLER_OS_VERS_PATCH=$(echo ${INSTALLER_OS_VERS} | awk -F "." '{print $3}')

log_info "Installer macOS version detected: ${INSTALLER_OS_VERS_MAJOR}.${INSTALLER_OS_VERS_MINOR}.${INSTALLER_OS_VERS_PATCH}"

HOST_OS_VERS=$(sw_vers -productVersion)
HOST_OS_VERS_MAJOR=$(echo ${HOST_OS_VERS} | awk -F "." '{print $1}')
HOST_OS_VERS_MINOR=$(echo ${HOST_OS_VERS} | awk -F "." '{print $2}')
HOST_OS_VERS_PATCH=$(echo ${HOST_OS_VERS} | awk -F "." '{print $3}')

log_info "Host macOS version detected: ${HOST_OS_VERS_MAJOR}.${HOST_OS_VERS_MINOR}.${HOST_OS_VERS_PATCH}"

if [ "${INSTALLER_OS_VERS_MAJOR}" != "${HOST_OS_VERS_MAJOR}" ] || [ "${INSTALLER_OS_VERS_MINOR}" != "${HOST_OS_VERS_MINOR}" ]; then
	bail "Host OS version and installer OS version do not match"
fi

#####

log_info "Creating and attaching a new scratch image..."

hdiutil create -size "${MACINBOX_DISK_SIZE}g" -type SPARSE -fs HFS+J -volname "Macintosh HD" -uid 0 -gid 80 -mode 1775 "${SCRATCH_IMAGE}"
hdiutil attach "${SCRATCH_IMAGE}" -mountpoint "${SCRATCH_MOUNTPOINT}" -nobrowse -owners on

#####

log_info "Installing macOS..."

installer -verboseR -dumplog -pkg "${INSTALL_INFO_PLIST}" -target "${SCRATCH_MOUNTPOINT}"

#####

log_info "Installing the VMware Tools..."

hdiutil attach "${VMWARE_TOOLS_IMAGE}" -mountpoint "${VMWARE_TOOLS_MOUNTPOINT}" -nobrowse
pkgutil --expand "${VMWARE_TOOLS_PACKAGE}" "${VMWARE_TOOLS_PACKAGE_DIR}"
ditto -x -z "${VMWARE_TOOLS_PACKAGE_DIR}/files.pkg/Payload" "${SCRATCH_MOUNTPOINT}"

mkdir -p "${SCRATCH_VMHGFS_FILESYSTEM_RESOURCES}"
ln -s "/Library/Application Support/VMware Tools/mount_vmhgfs" "${SCRATCH_VMHGFS_FILESYSTEM_RESOURCES}/"

#####

log_info "Setting SystemPolicyConfiguration KextPolicy to allow loading the VMware Tools kernel extensions..."

sqlite3 "${SCRATCH_SPC_KEXTPOLICY}" <<-EOF
	PRAGMA foreign_keys=OFF;
	BEGIN TRANSACTION;
	CREATE TABLE kext_load_history_v3 ( path TEXT PRIMARY KEY, team_id TEXT, bundle_id TEXT, boot_uuid TEXT, created_at TEXT, last_seen TEXT, flags INTEGER );
	INSERT INTO kext_load_history_v3 VALUES('/Library/Extensions/VMwareGfx.kext','EG7KH642X6','com.vmware.kext.VMwareGfx','7BD644E2-74AB-4310-8E56-D7CE28DC8CDB','2018-01-25 08:16:36','2018-01-25 08:17:47',7);
	INSERT INTO kext_load_history_v3 VALUES('/Library/Application Support/VMware Tools/vmhgfs.kext','EG7KH642X6','com.vmware.kext.vmhgfs','7BD644E2-74AB-4310-8E56-D7CE28DC8CDB','2018-01-25 08:16:43','2018-01-25 08:18:26',13);
	INSERT INTO kext_load_history_v3 VALUES('/Library/Application Support/VMware Tools/vmmemctl.kext','EG7KH642X6','com.vmware.kext.vmmemctl','7BD644E2-74AB-4310-8E56-D7CE28DC8CDB','2018-01-25 08:16:43','2018-01-25 08:18:26',5);
	CREATE TABLE kext_policy ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, developer_name TEXT, flags INTEGER, PRIMARY KEY (team_id, bundle_id) );
	INSERT INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.VMwareGfx',1,'VMware, Inc.',1);
	INSERT INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmmemctl',1,'VMware, Inc.',1);
	INSERT INTO kext_policy VALUES('EG7KH642X6','com.vmware.kext.vmhgfs',1,'VMware, Inc.',1);
	CREATE TABLE kext_policy_mdm ( team_id TEXT, bundle_id TEXT, allowed BOOLEAN, payload_uuid TEXT, PRIMARY KEY (team_id, bundle_id) );
	CREATE TABLE settings ( name TEXT, value TEXT, PRIMARY KEY (name) );
	INSERT INTO settings VALUES('migrationPerformed','YES');
	COMMIT;
EOF

#####

log_info "Automating creation of user account on first boot..."

cat > "${SCRATCH_INSTALLER_CONFIGURATION_FILE}" <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
		<key>Users</key>
		<array>
			<dict>
				<key>admin</key>
				<true/>
				<key>autologin</key>
				<${MACINBOX_AUTO_LOGIN}/>
				<key>fullName</key>
				<string>${MACINBOX_FULL_NAME}</string>
				<key>shortName</key>
				<string>${MACINBOX_SHORT_NAME}</string>
				<key>password</key>
				<string>${MACINBOX_PASSWORD}</string>
				<key>skipMiniBuddy</key>
				<true/>
			</dict>
		</array>
	</dict>
	</plist>
EOF

#####

log_info "Enabling password-less sudo..."

cat > "${SCRATCH_SUDOERS_D}/${MACINBOX_SHORT_NAME}" <<-EOF
	${MACINBOX_SHORT_NAME} ALL=(ALL) NOPASSWD: ALL
EOF

chmod 0440 "${SCRATCH_SUDOERS_D}/${MACINBOX_SHORT_NAME}"

#####

log_info "Enabling sshd..."

/usr/libexec/PlistBuddy -c 'Add :com.openssh.sshd bool False' "${SCRATCH_LAUNCHD_DISABLED_PLIST}"

#####

if [ "${MACINBOX_SHORT_NAME}" = "vagrant" ]; then

	log_info "Customizing installed OS for use with Vagrant..."

	# Enable further customizations to occur on first boot

	cat > "${SCRATCH_RC_INSTALLER_CLEANUP}" <<-"EOF"
		#!/bin/sh

		rm /etc/rc.installer_cleanup
		/etc/rc.vagrant &
		exit 0
	EOF

	chmod 0755 "${SCRATCH_RC_INSTALLER_CLEANUP}"

	# Install default insecure vagrant ssh key on first boot

	cat > "${SCRATCH_RC_VAGRANT}" <<-"EOF"
		#!/bin/sh

		rm /etc/rc.vagrant
		while [ ! -e /Users/vagrant ]; do
			sleep 1
		done
		if [ ! -e /Users/vagrant/.ssh ]; then
			mkdir /Users/vagrant/.ssh
			chmod 0700 /Users/vagrant/.ssh
			chown `stat -f %u /Users/vagrant` /Users/vagrant/.ssh
		fi
		echo "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key" >> /Users/vagrant/.ssh/authorized_keys
		chmod 0600 /Users/vagrant/.ssh/authorized_keys
		chown `stat -f %u /Users/vagrant` /Users/vagrant/.ssh/authorized_keys
	EOF

	chmod 0755 "${SCRATCH_RC_VAGRANT}"
fi

#####

log_info "Saving the image..."

hdiutil detach -quiet "${SCRATCH_MOUNTPOINT}"

mv "${SCRATCH_IMAGE}" "${TEMP_DIR}/macinbox.dmg"
chown "$SUDO_USER" "${TEMP_DIR}/macinbox.dmg"
mv "${TEMP_DIR}/macinbox.dmg" "${OUTPUT_PATH}"

#####

exit 0
