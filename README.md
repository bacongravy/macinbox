# macinbox

Puts macOS in a Vagrant VMware Fusion box.

## System Requirements

* macOS 10.13 High Sierra host operating system
* At least 8 GB RAM (16 GB recommended)
* At least 2 cores (4 recommended)
* At least 30 GB of available disk space (60 GB recommended)

## Dependencies

The following software is required. Versions other than those mentioned may work, but these are the latest versions tested:

* VMware Fusion 10.1.1
* Vagrant 2.0.1
* Vagrant VMware Fusion Plugin 5.0.4
* macOS 10.13.3 High Sierra installer application (must be the same version as the host operating system)

[Get VMware Fusion](http://www.vmware.com/products/fusion.html)
//
[Get Vagrant](https://www.vagrantup.com/)
//
[Get Vagrant VMware Fusion Plugin](https://www.vagrantup.com/vmware/)
//
[Get macOS 10.13 High Sierra installer application](http://appstore.com/mac/macoshighsierra)

## Installation

The `macinbox` script depends on the relative location of the scripts in the `bin/` directory of this repository. To install `macinbox`, first clone the repository, and then symlink it into a location in your `PATH`.  For example:

    $ git clone https://github.com/bacongravy/macinbox
    $ sudo ln -s "$(pwd)/macinbox/macinbox" /usr/local/bin/macinbox

## Basic Usage

Run with `sudo` and no arguments, the `macinbox` script will create and add a Vagrant VMware box named 'macinbox' using the installer app it finds in the default location:

    $ sudo macinbox

Be patient; this takes a while. After the script completes you can create a new Vagrant environment with the box and start using it:

    $ mkdir macinbox-test
    $ cd macinbox-test
    $ vagrant init macinbox
    $ vagrant up

After a few moments you should see your virtual machine's display appear in a fullscreen window, first showing the OS boot progress screen, and then after a minute or so, the desktop of the `vagrant` user.

## Advanced Usage

To see the advanced options, pass the `--help` option:

```
$ macinbox --help

Usage: macinbox [options]
    -i, --installer PATH             Path to the installer app
    -n, --name NAME                  Name of the box
    -d, --disk SIZE                  Size of the disk (specified in GB)
    -m, --memory SIZE                Size of the memory (specified in MB)
    -c, --cpu COUNT                  Number of virtual cores
    -s, --short NAME                 Short name of the user
    -f, --full NAME                  Full name of the user
    -p, --password PASSWORD          Password of the user
        --no-auto-login              Disable auto login
        --no-gui                     Disable the GUI
        --debug                      Enable debug mode
    -h, --help
```

You can specify the installer path location if it is not in the usual location. The name defaults to 'macinbox'. The disk size defaults to 64 GB. The memory size defaults to 2048 MB. The CPU count defaults to 2. The short name defaults to 'vagrant'. The full name defaults to 'Vagrant'. The password defaults to 'vagrant'. Auto-login is enabled by default. The VM GUI is enabled by default.

Using the debug option preserves the intermediate files (disk image, VMDK, and box) instead of cleaning them up after adding the box.

Here is an advanced example which creates and adds a box named 'macinbox-xl-nogui' with a 128 GB disk, 8 GB of RAM, and 4 cores; turns off auto login; and prevents the VMware GUI from being shown when the VM is started:

    $ macinbox -n macinbox-xl-nogui -d 128 -m 8192 -c 4 --no-auto-login --no-gui

## Details

This script performs the following actions:

1. Creates a new blank disk image
* Installs macOS
* Installs the VMware tools
* Updates the SystemPolicyConfiguration KextPolicy to allow the VMware tools kernel extension to load automatically
* Adds an .InstallerConfiguration file to automate the Setup Assistant app and create a user account on first boot
* Enables password-less sudo
* Enables sshd
* Adds an rc.installer_cleanup script which waits for the user account to be created on first boot and then installs the default insecure Vagrant SSH key in the user's home directory
* Converts the image into a VMDK
* Creates a Vagrant box for the VMware provider using the VMDK
* Adds the box to Vagrant

This script is intended to do everything that needs to be done to a fresh install of macOS before the first boot to turn it into a Vagrant VMware box that boots macOS with a seamless user experience. However, this script is also intended to the do the least amount of configuration possible. Nothing is done that could instead be deferred to a provisioning step in a Vagrantfile or packer template.

## Retina Display and HiDPI Support

If your host hardware includes a Retina display then you can configure the guest OS to display in HiDPI resolutions.

First, run the following command from the host Vagrant environment to enable HiDPI resolutions on the guest and restart the virtual machine:

    $ vagrant ssh -c "sudo defaults write /Library/Preferences/com.apple.windowserver.plist DisplayResolutionEnabled -bool true" && vagrant reload

Next, either ensure the 'Use full resolution for Retina display' checkbox is checked in the Display settings of the virtual machine in VMware Fusion, or that the `gui.fitGuestUsingNativeDisplayResolution = "TRUE"` setting is set in the VMX file.

Finally, open the Display pane of System Preferences on the guest, choose the 'Resolution: Scaled' radio button, and select the HiDPI resolution that appears in the table.

## Acknowledgements

This project was inspired by the great work of others:

* http://grahamgilbert.com/blog/2013/08/23/creating-an-os-x-base-box-for-vagrant-with-packer/
* http://heavyindustries.io/blog/2015/07/05/create_osx_vagrant_vmware_box.html
* https://spin.atomicobject.com/2015/11/17/vagrant-osx/
* https://github.com/timsutton/osx-vm-templates
* https://github.com/boxcutter/macos
* https://github.com/chilcote/vfuse
* http://www.modtitan.com/2017/10/lazy-vm-building-hacks-with-autodmg-and.html

## Why?

My preferred operating system is macOS, and ever since I started using Vagrant, I thought that it would be nice to have be able to boot a macOS box as easily as a Linux box. However, it wasn't until I was watching an episode of Mr. Robot that I was finally inspired to figure out how to make it happen. In the episode, Elliot is shown quickly booting what appeared to be a virtual machine running a Linux desktop environment in order to examine the contents of an untrusted CD-ROM, and I thought, "I want to be able to do that kind of thing with macOS!".

In researching prior art, I discovered Timothy Sutton's `osx-vm-templates` project and realized that I would be able to use those scripts and packer templates to accomplish my goal. However, after using those the scripts and templates a few times and trying to customize them, I found that they didn't always work reliably for me. I began trying to understand how they worked so that I could make them more reliable and customizable, and created [vagrant-box-macos](https://github.com/bacongravy/vagrant-box-macos).

With the release of macOS 10.12.4, however, the prevailing techniques for customizing OS installs were hampered by a new requirement that all packages be signed by Apple. Since supporting macOS 10.13 High Sierra (and later) was going to require a major change to the scripts anyways, I decided to create 'macinbox' as a simpler, more streamlined approach to building macOS boxes. The previous scripts were more flexible, but 'macinbox' is faster and more reliable.

I chose to support only VMware Fusion boxes because of the Vagrant VMware plugin support for linked clones and shared folders, and because in my experience I have found that macOS virtualizes better in VMware Fusion than the alternatives.
