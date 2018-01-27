#!/bin/sh -e

# required arguments

INPUT_VMDK="$1"
OUTPUT_PATH="$2"

# optional arguments

MACINBOX_BOX_NAME="${MACINBOX_BOX_NAME:-macinbox}"
MACINBOX_CPU_COUNT="${MACINBOX_CPU_COUNT:-2}"
MACINBOX_MEMORY_SIZE="${MACINBOX_MEMORY_SIZE:-2048}"
MACINBOX_GUI="${MACINBOX_GUI:-true}"

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

if [ -z "${INPUT_VMDK}" ]; then
	bail "No input VMDK specified."
fi

if [ ! -e "${INPUT_VMDK}" ]; then
	bail "Input VMDK not found."
fi

if [ -z "${OUTPUT_PATH}" ]; then
	bail "No output path specified."
fi

######

TEMP_DIR="$(/usr/bin/mktemp -d -t prepare_box_from_vmdk)"

#####

cleanup() {
	trap - EXIT INT TERM
  log_info "Cleaning up..."
	rm -rf "${TEMP_DIR}" > /dev/null 2>&1 || true
	[[ $SIG == EXIT ]] || kill -$SIG $$ || true
}

for sig in EXIT INT TERM; do
	trap "SIG=$sig; cleanup;" $sig
done

#####

log_info "Creating the Vagrant box..."

cat > "${TEMP_DIR}/${MACINBOX_BOX_NAME}.vmx" <<-EOF
  .encoding = "UTF-8"
  config.version = "8"
  virtualHW.version = "14"
  numvcpus = "${MACINBOX_CPU_COUNT}"
  memsize = "${MACINBOX_MEMORY_SIZE}"
  sata0.present = "TRUE"
  sata0:0.fileName = "${MACINBOX_BOX_NAME}.vmdk"
  sata0:0.present = "TRUE"
  sata0:1.autodetect = "TRUE"
  sata0:1.deviceType = "cdrom-raw"
  sata0:1.fileName = "auto detect"
  sata0:1.startConnected = "FALSE"
  sata0:1.present = "TRUE"
  ethernet0.connectionType = "nat"
  ethernet0.addressType = "generated"
  ethernet0.virtualDev = "e1000e"
  ethernet0.linkStatePropagation.enable = "TRUE"
  ethernet0.present = "TRUE"
  usb.present = "TRUE"
  usb_xhci.present = "TRUE"
  ehci.present = "TRUE"
  ehci:0.parent = "-1"
  ehci:0.port = "0"
  ehci:0.deviceType = "video"
  ehci:0.present = "TRUE"
  pciBridge0.present = "TRUE"
  pciBridge4.present = "TRUE"
  pciBridge4.virtualDev = "pcieRootPort"
  pciBridge4.functions = "8"
  pciBridge5.present = "TRUE"
  pciBridge5.virtualDev = "pcieRootPort"
  pciBridge5.functions = "8"
  pciBridge6.present = "TRUE"
  pciBridge6.virtualDev = "pcieRootPort"
  pciBridge6.functions = "8"
  pciBridge7.present = "TRUE"
  pciBridge7.virtualDev = "pcieRootPort"
  pciBridge7.functions = "8"
  vmci0.present = "TRUE"
  smc.present = "TRUE"
  hpet0.present = "TRUE"
  ich7m.present = "TRUE"
  usb.vbluetooth.startConnected = "TRUE"
  board-id.reflectHost = "TRUE"
  firmware = "efi"
  displayName = "${MACINBOX_BOX_NAME}"
  guestOS = "darwin17-64"
  nvram = "${MACINBOX_BOX_NAME}.nvram"
  virtualHW.productCompatibility = "hosted"
  keyboardAndMouseProfile = "macProfile"
  powerType.powerOff = "soft"
  powerType.powerOn = "soft"
  powerType.suspend = "soft"
  powerType.reset = "soft"
  tools.syncTime = "TRUE"
  sound.autoDetect = "TRUE"
  sound.virtualDev = "hdaudio"
  sound.fileName = "-1"
  sound.present = "TRUE"
  extendedConfigFile = "${MACINBOX_BOX_NAME}.vmxf"
  floppy0.present = "FALSE"
  mks.enable3d = "FALSE"
  gui.fitGuestUsingNativeDisplayResolution = "TRUE"
  gui.viewModeAtPowerOn = "fullscreen"
EOF

cat > "${TEMP_DIR}/metadata.json" <<-EOF
  {"provider": "vmware_fusion"}
EOF

cat > "${TEMP_DIR}/Vagrantfile" <<-EOF
  # -*- mode: ruby -*-
  # vi: set ft=ruby :
  ENV["VAGRANT_DEFAULT_PROVIDER"] = "vmware_fusion"

  Vagrant.configure(2) do |config|
    config.vm.network :forwarded_port, guest: 22, host: 2222, id: "ssh", disabled: true
    config.vm.synced_folder ".", "/vagrant", disabled: true
    config.vm.provider "vmware_fusion" do |v|
      v.gui = ${MACINBOX_GUI}
    end
  end
EOF

INPUT_VMDK_DIRNAME="$(cd $(dirname "${INPUT_VMDK}") 2> /dev/null && pwd -P)"
INPUT_VMDK_BASENAME="$(basename "${INPUT_VMDK}")"

tar czf "${TEMP_DIR}/${MACINBOX_BOX_NAME}.box" -C "${TEMP_DIR}" "./${MACINBOX_BOX_NAME}.vmx" "./metadata.json" "./Vagrantfile" -C "${INPUT_VMDK_DIRNAME}" "./${INPUT_VMDK_BASENAME}"

chown "$SUDO_USER" "${TEMP_DIR}/${MACINBOX_BOX_NAME}.box"
mv "${TEMP_DIR}/${MACINBOX_BOX_NAME}.box" "${OUTPUT_PATH}"

#####

exit 0
