# macinbox

Puts macOS Mojave in a Vagrant box.

<p align=center>
  <img src="https://raw.githubusercontent.com/bacongravy/macinbox/demo/demo.gif">
  <i>Some sequences shortened. Original run time 14.5 minutes.</i>
</p>

Supports creating boxes in either the 'vmware_fusion' or 'parallels' formats.

## System Requirements

* macOS 10.14 Mojave host operating system
* At least 8 GB RAM (16 GB recommended)
* At least 2 cores (4 recommended)
* At least 100 GB of available disk space

## Dependencies

The following software is required. Versions other than those mentioned may work, but these are the latest versions tested:

* [macOS 10.14 Mojave installer application](http://appstore.com/mac/macosmojave)
* [Vagrant 2.1.5](https://www.vagrantup.com/)

To create and boot a box in the 'vmware_fusion' format you must also have:

* [VMware Fusion Pro 10.1.3](http://www.vmware.com/products/fusion.html)
* [Vagrant VMware Fusion Provider 5.0.4](https://www.vagrantup.com/vmware/)

To create and boot a box in the 'parallels' format you must also have:

* [Parallels Desktop 13 for Mac Pro Edition 13.3.2](https://www.parallels.com/products/desktop/)
* [Vagrant Parallels Provider 1.7.8](https://parallels.github.io/vagrant-parallels/)

## Installation

Install the gem:

    $ sudo gem install macinbox

## Basic Usage

Run with `sudo` and no arguments, the `macinbox` tool will create and add a Vagrant VMware box named 'macinbox' which boots fullscreen to the desktop of the 'vagrant' user:

    $ sudo macinbox

Please be patient, as this may take a while. (On a 2.5 GHz MacBookPro11,5 it takes about 11 minutes, 30 seconds.) After the tool completes you can create a new Vagrant environment with the box and start it:

    $ vagrant init macinbox && vagrant up

A few moments after running this command you will see your virtual machine's display appear fullscreen. (Press Command-Control-F to exit fullscreen mode.) After the virtual machine completes booting (approximately 1-2 minutes) you will see the desktop of the 'vagrant' user and can begin using the virtual machine.

To create a Parallels Desktop box, pass the `--box-format` option:

    $ sudo macinbox --box-format parallels

## Advanced Usage

To see the advanced options, pass the `--help` option:

```
Usage: macinbox [options]

        --box-format FORMAT          Format of the box (default: vmware_fusion)

    -n, --name NAME                  Name of the box         (default: macinbox)
    -d, --disk SIZE                  Size (GB) of the disk   (default: 64)
    -t, --fstype TYPE                Type for disk format    (default: APFS)
    -m, --memory SIZE                Size (MB) of the memory (default: 2048)
    -c, --cpu COUNT                  Number of virtual cores (default: 2)
    -s, --short NAME                 Short name of the user  (default: vagrant)
    -f, --full NAME                  Full name of the user   (default: Vagrant)
    -p, --password PASSWORD          Password of the user    (default: vagrant)

        --installer PATH             Path to the macOS installer app
        --vmware PATH                Path to the VMware Fusion app
        --parallels PATH             Path to the Parallels Desktop app

        --no-auto-login              Disable auto login
        --no-skip-mini-buddy         Show the mini buddy on first login
        --no-hidpi                   Disable HiDPI resolutions
        --no-fullscreen              Display the virtual machine GUI in a window
        --no-gui                     Disable the GUI

        --debug                      Enable debug mode

    -v, --version
    -h, --help
```

Enabling debug mode causes the intermediate files (disk image, VMDK, and box) to be preserved after the tool exits rather than being cleaned up. WARNING!!! These intermediate files are very large and you can run out of disk space very quickly when using this option.

This advanced example creates and adds a box named 'macinbox-large-nogui' with 4 cores, 8 GB or RAM, and a 128 GB disk; turns off auto login; and prevents the VMware GUI from being shown when the VM is started:

    $ macinbox -n macinbox-large-nogui -c 4 -m 8192 -d 128 --no-auto-login --no-gui

## Retina Display and HiDPI Support

By default `macinbox` will configure the guest OS to have HiDPI resolutions enabled, and configure the virtual machine to use the native display resolution.  You can disable this behavior using the `--no-hidpi` option.

## Box Format Support

By default `macinbox` will create a Vagrant box in the 'vmware_fusion' format with the VMware Tools pre-installed. When the box format is set to 'parallels' using the `--box-format` option then the Parallels Tools are pre-installed instead.

## Implementation Details

This tool performs the following actions:

1. Wraps the installer app in a disk image
1. Creates a new blank disk image
1. Installs macOS
1. Installs the VMware or Parallels tools
1. (VMware only) Updates the SystemPolicyConfiguration KextPolicy to allow the VMware tools kernel extension to load automatically
1. Adds an .InstallerConfiguration file to automate the Setup Assistant app and create a user account on first boot
1. Enables password-less sudo
1. Enables sshd
1. Adds an rc.installer_cleanup script which waits for the user account to be created on first boot and then installs the default insecure Vagrant SSH key in the user's home directory
1. Enables HiDPI resolutions
1. Converts the image into a virtual hard disk
1. Creates a Vagrant box using the virtual hard disk
1. Adds the box to Vagrant


The box created by this tool includes a built-in Vagrantfile which disables the following default Vagrant behaviors:

1. Checking Vagrant Cloud for new versions of the box
1. Forwarding from port 2222 on the host to port 22 (ssh) on the guest
1. Sharing the root folder of the Vagrant environment as '/vagrant' on the guest

To re-enable the default ssh port forwarding you can add the following line to your environment's Vagrantfile:

    config.vm.network :forwarded_port, guest: 22, host: 2222, id: "ssh"

To re-enable the default synced folder you can add the following line to your environment's Vagrantfile:

    config.vm.synced_folder ".", "/vagrant"

## Design Philosophy

This tool is intended to do everything that needs to be done to a fresh install of macOS before the first boot to turn it into a Vagrant box that boots macOS with a seamless user experience. However, this tool is also intended to the do the least amount of configuration possible. Nothing is done that could instead be deferred to a provisioning step in a Vagrantfile or packer template.

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

This project draws inspiration from an episode of Mr. Robot. In the episode, Elliot is shown quickly booting what appeared to be a virtual machine running a fresh Linux desktop environment, in order to examine the contents of an untrusted CD-ROM. As I watched I thought, "I want to be able to do that kind of thing with macOS!". Surely I'm not the only person who has downloaded untrusted software from the internet, and wished that there was an easy way to evaluate it without putting my primary working environment at risk?

This project is a direct successor to my [vagrant-box-macos](https://github.com/bacongravy/vagrant-box-macos) project, which itself was heavily inspired by Tim Sutton's [osx-vm-templates](https://github.com/timsutton/osx-vm-templates) project.

With the release of macOS 10.12.4 the prevailing techniques for customizing macOS installs were hampered by a new installer requirement that all packages be signed by Apple. After attempting various techniques to allow `vagrant-box-macos` to support macOS 10.13 High Sierra, I decided a different approach to box creation was needed, and `macinbox` was born.

## Development

Start by running `sudo gem install bundler` and `bundle install`.

To run `macinbox` directly from the root of the git workspace without installing the gem, run `sudo bundle exec macinbox`.

To install this gem onto your local machine, run `sudo bundle exec rake install`.

You can also run `bin/console` for an interactive prompt that will allow you to experiment. For example:

```
opts = Macinbox::CLI::DEFAULT_OPTION_VALUES
opts[:collector] = Macinbox::Collector.new
opts[:full_name] = "Vagrant"
opts[:password] = "vagrant"
opts[:box_format] = "parallels"
opts[:image_path] = "macinbox.dmg"
opts[:vmdk_path] = "macinbox.vmdk"
opts[:hdd_path] = "macinbox.hdd"
opts[:box_path] = "macinbox.box"
opts[:debug] = true
include Macinbox::Actions
CreateImageFromInstaller.new(opts).run
CreateVMDKFromImage.new(opts).run
CreateHDDFromVMDK.new(opts).run
CreateBoxFromHDD.new(opts).run
```

To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bacongravy/macinbox.
