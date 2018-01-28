#!/bin/sh -e

INPUT_IMAGE="$1"
OUTPUT_PATH="$2"

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

if [ -z "${INPUT_IMAGE}" ]; then
	bail "Input image not specified."
fi

if [ ! -e "${INPUT_IMAGE}" ]; then
	bail "Input image not found."
fi

if [ -z "${OUTPUT_PATH}" ]; then
	bail "No output path specified."
fi

######

TEMP_DIR="$(/usr/bin/mktemp -d -t prepare_vmdk_from_image)"

IMAGE_MOUNTPOINT="${TEMP_DIR}/image_mountpoint"
IMAGE_DEVICE="/dev/null"

VMWARE_RAWDISKCREATOR="${VMWARE_FUSION_APP}/Contents/Library/vmware-rawdiskCreator"
VMWARE_VDISKMANAGER="${VMWARE_FUSION_APP}/Contents/Library/vmware-vdiskmanager"

#####

mkdir "${IMAGE_MOUNTPOINT}"

cleanup() {
	trap - EXIT INT TERM
  log_info "Cleaning up..."
  hdiutil detach -quiet -force "${IMAGE_MOUNTPOINT}" > /dev/null 2>&1 || true
	diskutil eject "${IMAGE_DEVICE}" > /dev/null 2>&1 || true
	rm -rf "${TEMP_DIR}" > /dev/null 2>&1 || true
	[[ $SIG == EXIT ]] || kill -$SIG $$ || true
}

for sig in EXIT INT TERM; do
	trap "SIG=$sig; cleanup;" $sig
done

#####

log_info "Mounting the image..."

IMAGE_DEVICE=$(
	hdiutil attach "${INPUT_IMAGE}" -mountpoint "${IMAGE_MOUNTPOINT}" -nobrowse -owners on |
	grep GUID_partition_scheme |
	cut -f1 |
	tr -d '[:space:]'
)

if [ ! -e "${IMAGE_DEVICE}" ]; then
	bail "Failed to find the device file of the image"
fi

#####

log_info "Converting the image to VMDK format..."

"${VMWARE_RAWDISKCREATOR}" create "${IMAGE_DEVICE}" fullDevice "${TEMP_DIR}/rawdisk" lsilogic
"${VMWARE_VDISKMANAGER}" -t 0 -r "${TEMP_DIR}/rawdisk.vmdk" "${TEMP_DIR}/macinbox.vmdk"

#####

log_info "Moving the VMDK to the destination..."

chown "$SUDO_USER" "${TEMP_DIR}/macinbox.vmdk"
mv "${TEMP_DIR}/macinbox.vmdk" "${OUTPUT_PATH}"

#####

exit 0
