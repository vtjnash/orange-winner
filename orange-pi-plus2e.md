This is intended as a guide for bootstrapping from nothing to a fully working and updated Linux distro.

Process overview
----------------
1. Compile U-Boot
2. Install ArchLinux on SD card
3. Copy U-Boot on SD card
4. Build a custom kernel
5. Copy the kernel to the SD card
6. Install to internal eMMC NAND flash

Compile u-boot
--------------

### Download and configure toolchain ###

Go to <https://developer.arm.com/-/media/Files/downloads/gnu-a/10.3-2021.07/binrel/gcc-arm-10.3-2021.07-x86_64-arm-none-linux-gnueabihf.tar.xz>, pick the latest version of AArch32 target with hard float (arm-none-linux-gnueabihf). The file should be named something like `gcc-arm-<version>-<date>-x86_64-arm-linux-gnueabihf.tar.xz`

Extract the content of the archive to a folder and make sure that the `bin` folder of the package is in your `PATH`. It can be added for the current session only by using:

```
export PATH="$PATH":/home/user/folder/gcc-arm-<VERSION>-<DATE>-x86_64_arm-linux-gnueabihf/bin/
```

Specify that cross compilation to ARM should be used:

```
export CROSS_COMPILE=arm-none-linux-gnueabihf-
```

### Download and compile U-Boot ###

Clone the latest stable u-boot from `git@github.com:u-boot/u-boot.git`.

```
git clone git@github.com:u-boot/u-boot.git
cd u-boot
```

In the main u-boot folder, configure u-boot for your device.

```
ls configs # >> pick the config name that matches your device
make orangepi_plus2e_defconfig
sudo apt install bc bison build-essential coccinelle \
  device-tree-compiler dfu-util efitools flex gdisk graphviz imagemagick \
  liblz4-tool libguestfs-tools libncurses-dev libpython3-dev libsdl2-dev \
  libssl-dev lz4 lzma lzma-alone openssl python3 python3-coverage \
  python3-pycryptodome python3-pyelftools python3-pytest \
  python3-sphinxcontrib.apidoc python3-sphinx-rtd-theme python3-virtualenv \
  swig
```

Build the u-boot image for your OrangePi.

```
make -jN
```

From this, we will need the `u-boot-sunxi-with-spl.bin` file and the `tools/mkimage` program.


Install a Linux userspace on SD card (method 1)
-----------------------------------------------

This is best if you have access to an existing Linux machine and want total control over the file-system layout.
A much more exhaustive step-by-step guide is http://linux-sunxi.org/Bootable_SD_card#Bootloader.

1. Clean up the beginning of the SD Card (optional):
    Identify the name of your SD card by using `lsblk`.
	```
    dd if=/dev/zero of=/dev/sdX bs=1M count=8
    ```
	where `/dev/sdX` is the name of the SD Card.
3. 2. Partition the SD Card.
    -> More detailed instructions for this can be found at http://archlinuxarm.org/platforms/armv7/allwinner/pcduino3, or in most installer guides
    Start by deleting all partitions that may already exist on the card.
    (optional) Create a boot partition starting at 2048 formatted as fat
    Create a primary partition starting at 2048 (or after the boot partition) and extending to the end of the card formatted as ext4
    Write the partition and exit
3. Create and mount the ext4 filesystem:
    ```
    mkfs.ext4 /dev/sdX1
    mkdir mnt
    mount /dev/sdX1 mnt
    ```
    where `/dev/sdX1' is the name of the partition on the SD Card
4. If you made a separate boot partition, mount that now too:
    ```
    mkfs.fat /dev/sdX1
    mkdir mnt
    mount /dev/sdX1 mnt
    ```
4. Download and extract the root filesystem:
    ```
    wget http://archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz
    bsdtar -xpf ArchLinuxARM-armv7-latest.tar.gz -C mnt
    sync
    ```

Install a Linux userspace on SD card (method 2)
-----------------------------------------------

This can be a quicker method.
If you're eventually installing to an internal eMMC, the OS here isn't too important,
so this method can save some hassle.

Download an existing SD card image, such as
http://www.orangepi.org/orangepibbsen/forum.php?mod=viewthread&tid=342
or
http://www.orangepi.org/orangepibbsen/forum.php?mod=viewthread&tid=2221&extra=page%3D1
and copy it to the SD card:

```
dd if=<download>.img of=/dev/sdX
```

Copy U-Boot to SD card
----------------------

Now we will install the U-Boot bootloader.
In the main u-boot folder where you compiled u-boot you will find the bootloader file called `u-boot-sunxi-with-spl.bin`

```
dd if=u-boot-sunxi-with-spl.bin of=/dev/sdX bs=1024 seek=8
```

With just this step, you should be able to turn on the card and see output on serial and hdmi.

Build a kernel
--------------

We'll use nearly a stock kernel:

```
git clone https://github.com/torvalds/linux.git linux-sunxi
cd linux-sunxi
```

Configure the kernel build:

```
make sunxi_defconfig ARCH=arm
```

The default configuration should work, but you will almost certainly want to add more functionality.

```
make menuconfig ARCH=arm
```

For example, I added `CONFIG_HIDRAW` and `CONFIG_USB_HIDDEV` (for USB keyboard support).

Tip: The quickest way to do change an option is to search for it by typing `/CONFIG_HIDRAW<enter>1`, then enabling it by pressing `<space>`.

Finally, build it:

```
make ARCH=arm
```

From this, we will need the `arch/arm/boot/zImage` and `arch/arm/boot/dts/*.dtb` files.

```
make -j40 ARCH=arm modules_install INSTALL_MOD_PATH=~+/output
```

From this, we will need the `output/lib` folder.


Installing the kernel
---------------------

Mount the BOOT partition locally.

```
mount /dev/sdX mnt
cd mnt
cd boot # if you didn't set up a separate boot partition
```

Optionally, you may delete all of contents of this folder (and subfolders);
we're about to replace them anyways.
Copy over the kernel files and device-tree-support descriptors:

```
cp <linux-sunxi>arch/arm/boot/zImage .
mkdir dtbs # if it doesn't already exist
cp <linux-sunxi>arch/arm/boot/dts/*.dtb dtbs
```

Finally, we need to tell U-Boot how to load this kernel:

We'll start with the following script, and then customize it for your usage:

```
part uuid ${devtype} ${devnum}:${bootpart} uuid
setenv bootargs console=${console} root=PARTUUID=${uuid} rw rootwait panic=20

if load ${devtype} ${devnum}:${bootpart} ${kernel_addr_r} /boot/zImage; then
  if load ${devtype} ${devnum}:${bootpart} ${fdt_addr_r} /boot/dtbs/${fdtfile}; then
    if load ${devtype} ${devnum}:${bootpart} ${ramdisk_addr_r} /boot/initramfs-linux.img; then
      bootz ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdt_addr_r};
    else
      bootz ${kernel_addr_r} - ${fdt_addr_r};
    fi;
  fi;
fi

if load ${devtype} ${devnum}:${bootpart} 0x48000000 /boot/uImage; then
  if load ${devtype} ${devnum}:${bootpart} 0x43000000 /boot/script.bin; then
    setenv bootm_boot_mode sec;
    bootm 0x48000000;
  fi;
fi
```

- If you made a separate partition for /boot:

  * Delete the line starting with `part uuid`.

  * Replace `root=PARTUUID=${uuid}` with `root=/dev/mmcblk0p2`.

  * Delete all instances of `/boot/`.

- If you have a display driver (optional):

  * Replace `console=${console}` with `console=tty1` to enable console output over HDMI instead of serial.

Save this script as `boot.txt` somewhere and compile it with:

```
<u-boot>/tools/mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d boot.txt boot.scr
```

Place this file on the SD card alongside the `zImage` file.


Install to internal eMMC NAND flash
-----------------------------------

The steps to this are actually the same as above.

In some SD card builds, there will be a script `install_to_emmc` (or download from https://github.com/loboris/OrangePi-BuildLinux/blob/master/install_to_emmc),
which may help automate some of this process. In some cases, you'll need to install `parted` and `dosfstools` first!

```
pacman -Syu
pacman -S parted dosfstools
```

```
dd if=u-boot-sunxi-with-spl.bin of=/dev/mmcblk2 bs=1024 seek=8
```


Adding Wifi support
-------------------

Wifi: http://linux-sunxi.org/Wifi#RTL8189FTV

First, you need to enable WIFI support in the kernel image.
Go back and re-run `menuconfig` as described above.
This time, turn on `CONFIG_WLAN`, `CONFIG_CFG80211`, `CONFIG_MAC80211`.
Rebuild the kernel with `make ARCH=arm`.
This will produce a new `zImage` file that you should use to replace
the existing one in the `boot` partition / folder on the SD card.

Then in the kernel run `make ARCH=arm prepare`.

```
git clone https://github.com/jwrdegoede/rtl8189ES_linux.git
cd rtl8189ES_linux
git checkout rtl8189fs
# vim include/autoconf.h # set options (disable CONFIG_DEBUG)
make -j4 ARCH=arm KSRC=<linux-sunxi>
```

From this, we will need the `8189fs.ko`, `modules.order`, and `Module.symvers` files.

Test this with `insmod 8189fs.ko`, until you're satisfied this is working.

Copy this file to `/lib/modules/$(uname -r)`, along with any files in `<linux-sunxi>/output/lib` (if you built any of the menuconfig options as modules),
then run `/sbin/depmod` to enable at boot.

For the Linux/GNU userspace, you'll probably want to install `iw` and `wicd` to monitor and inspect the state of this interface.

Userspace graphics support
--------------------------

Install at minimum `xf86-video-fbdev`, `xorg-server`, `xorg-xinit`, and `xterm`.
Then you can run `startx` to get a very basic GUI environment.


USB OTG Boot (optional)
-----------------------

If you ever mess up the bootloader, you can fix that. Here's how.
This is also especially useful if you want to try out an
experimental kernel before saving it to the device.

First, you'll need the `sunxi-tools` (http://linux-sunxi.org/Sunxi-tools):

```
git clone https://github.com/linux-sunxi/sunxi-tools
## Make sure you have some version of libusb installed:
# apt install apt-get install libusb-1.0-0-dev  ## Debian / Ubuntu
# yum install libusbx-devel                     ## Fedora
# pacman -Si libusb                             ## Arch
# port install libusb && \
#    export PATH=/opt/local/bin:$PATH           ## MacOS Macports
# brew install libusb                           ## MacOS Homebrew
make
```

Next you'll need a way to enter FEL mode (http://linux-sunxi.org/FEL) mode Boot1.
I've found that the SD card boot loader image works well enough:

```
wget https://github.com/linux-sunxi/sunxi-tools/raw/master/bin/fel-sdboot.sunxi
dd if=fel-sdboot.sunxi of=/dev/sdX bs=1024 seek=8
```

You can also hold down the OTG button (probably will need a paperclip) when applying power (after connecting the USB OTG cable).

Connect the USB OTG port (micro USB connector) to your computer and (optional) check that the device is responding:

```
lsusb -t
./sunxi-tools/sunxi-fel -l
```

Make a `zramboot.txt` file with the following contents, and compile it with `mkimage`, as we did above, to `zramboot.scr`.

```
setenv bootargs console=tty1 root=/dev/mmcblk0p2 panic=10
bootz 0x42000000 - 0x43000000
```

Adjust the `console=` and `root=` lines as needed, per the advice above.

And run the U-Boot image, device-tree file, and kernel from the local system (ignoring the BOOT drive / folder):

```
./sunxi-tools/sunxi-fel uboot \
    u-boot-sunxi-with-spl.bin \
    write 0x42000000 zImage \
    write 0x43000000 sun8i-h3-orangepi-plus2e.dtb \
    write 0x43100000 zramboot.scr
```


Useful links
------------

- Kernel status: http://linux-sunxi.org/Linux_mainlining_effort
- U-Boot status: http://linux-sunxi.org/Mainline_U-boot
- CPU info: http://linux-sunxi.org/H3
- Board info: http://linux-sunxi.org/Xunlong_Orange_Pi_Plus_2E
- Basis for this guide: http://www.orangepi.org/orangepibbsen/forum.php?mod=viewthread&tid=845&extra=page%3D1
