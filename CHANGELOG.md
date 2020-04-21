## 4.1.1 (April 21, 2020)

BUG FIXES:

- Do not silently continue if the `installer` command fails. [GH-51]

## 4.1.0 (April 21, 2020)

FEATURES:

- Re-enable installation of VMware Tools on Catalina. [GH-45]

## 4.0.0 (November 12, 2019)

FEATURES:

- Prevent incompatible host and guest OS versions from being used together. [GH-24]

BREAKING CHANGES:

- Use the Catalina installer app by default.
- Skip installation of VMware Tools on Catalina because it is not working properly.

## 3.4.0 (November 12, 2019)

FEATURES:

- Create `vagrant` group on first boot of the box. [GH-37]
- Add a preflight check to ensure that VMware disk conversion will be successful. [GH-12]

BUG FIXES:

- Handle missing package in Parallels Tools. [GH-43]

IMPROVEMENTS:

- Remove dependency on vmware-rawdiskCreator tool.

## 3.3.0 (February 26, 2019)

FEATURES:

- Add --verbose option to show the commands being run. [GH-28]
- Add --user-script option to support running user-provided customizations. [GH-24]

BUG FIXES:

- Only display the animated progress bar when stderr is a tty. [GH-25]

## 3.2.0 (February 2, 2019)

FEATURES:

- Add --use-qemu option to support building vmware_desktop boxes with qemu-img. [GH-12]
- Add --installer-dmg option to support using installers wrapped in disk images. [GH-21]

IMPROVEMENTS:

- Use clonefile (`cp -c`) to copy files faster.
- Use the detected OS version as the box version.
- Skip creation of the wrapper image when it isn't necessary. [GH-21]

## 3.1.0 (January 21, 2019)

FEATURES:

- Add support for virtualbox box format. [GH-18]

BUG FIXES:

- Make vagrant ssh key installation more reliable.
- Update gemspec requirements for Mojave. [GH-17]

## 3.0.0 (December 14, 2018)

FEATURES:

- Add support for vmware_desktop box format. [GH-14]
- Add support for VAGRANT_HOME environment variable. [GH-15]

IMPROVEMENTS:

- Use full paths when invoking external commands. [GH-16]

BREAKING CHANGES:

- Switch default box format to vmware_desktop. Requires the Vagrant VMware Desktop Plugin. [GH-14]

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
