## Next version (Unreleased)

FEATURES:

- Add support for vmware_desktop box format.
- Add support for VAGRANT_HOME environment variable.

BREAKING CHANGES:

- Switch default box format to vmware_desktop. Requires the Vagrant VMware Desktop Plugin.

## 2.0.1 (November 16, 2018)

IMPROVEMENTS:

- Warn instead of raising an error when host and installer versions do not match. Allows Mojave boxes to be created from High Sierra. [GH-13]

## 2.0.0 (October 18, 2018)

FEATURES:

- Add support for Mojave.

BREAKING CHANGES:

- Remove support for High Sierra.
- Switch default fstype to APFS.

## 1.2.1 (October 4, 2018)

BUG FIXES:

- Restrict macinbox to only work with High Sierra (and not Mojave). [GH-10]

## 1.2.0 (June 9, 2018)

FEATURES:

- Adding support for --fstype TYPE. [GH-9]

IMPROVEMENTS:

- Make the exit code more readable.
- Retry a few times if detaching the image fails while trying to save it.

## 1.1.1 (April 22, 2018)

IMPROVEMENTS:

- Create Parallels HDD directly from image instead of VMDK. [GH-8]

## 1.1.0 (April 20, 2018)

FEATURES:

- Add support for creating Parallels Desktop boxes.

IMPROVEMENTS:

- Remove useless `VAGRANT_DEFAULT_PROVIDER` environment override

BUG FIXES:

- Add missing require to allow `macinbox -v` to work. [GH-5]

## 1.0.2 (March 11, 2018)

IMPROVEMENTS:

- Suppress curl and unzip output unless in debug mode.
- Versions that are empty should be considered available when determining the next available version.
- Attach but don't mount the disk image before converting it, and avoid attempting to eject it twice.

BUG FIXES:

- Override `ethernet0.virtualDev` to always be `e1000e`. [GH-3]

## 1.0.1 (February 7, 2018)

IMPROVEMENTS:

- Download darwin.iso if it is not present in the app bundle. [GH-1]
- Eject disk image after converting it.

BUG FIXES:

- Reset text color instead of setting it to black. [GH-2]

## 1.0.0 (February 3, 2018)

FEATURES:

- Puts macOS High Sierra in a VMware Fusion Vagrant box.
