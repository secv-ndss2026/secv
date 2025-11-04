# Artifact for NDSS2026 SECV: Securing Connected Vehicles with Hardware Trust Anchors.
This is the open-source for the SECV: Securing Connected Vehicles with Hardware Trust Anchors, NDSS 2026 Fall paper.
Here, we will provide code modifications for the core parts of the paper and the instructions on building SECV for S32G3. 
We provide code patches showing the major changes made to help reduce the time of search. The major components here are the Linux Kernel, the OPTEE-OS, drivers, and Arm Trusted Firmware.

## Caution and Disclaimer:
This is only a prototype and is not production-ready. We only provide a proof of concept for the research conducted, as presented in the paper.
Additionally, especially for S32G3, some of the required firmware requires Licenses, and thus, we are not permitted to distribute them. But one may obtain most of the needed firmware with a free account on NXP.

## Building the default S32G3 Image:
The image can be built with Yocto as follows, and at least one should have `repo` installed:
- ***Build Environment:*** Ubuntu 20.04
- ***Hardware Requirements:*** At least 16GB RAM, at least 4 CPU Cores, and 70GB or more disk space.

### Initial Setup and obtaining the baseline code-base
```sh
$ mkdir nxp-yocto-goldvip
$ cd nxp-yocto-golvip
$ repo init -b develop -m default.xml -u https://github.com/nxp-auto-goldvip/gvip-manifests
$ repo sync
$ ./sources/meta-alb/scripts/host-prepare.sh
$ sudo apt-get install libssl-dev
# We don't need to use a hypervisor, so we went with goldvip-no-hv
$ source nxp-setup-alb.sh -D fsl-goldvip-no-hv \
 -m s32g399ardb3 \
 -e "meta-aws meta-java meta-vip"
```
After running the above commands, one should now have a `build_s32g399ardb3` folder added automatically.

#### Test-building:
Run the following command to test-build. This should download most of the needed dependencies.
```sh
$ bitbake fsl-image-goldvip
```
For the above build to succeed, one needs certain proprietary NXP binaries. These include the bootloader binaries, the HSM (HSE) library binaries, etc. We include a manual from NXP on how to handle this.

During the build, the GoldVIP image requires `openjdk8`, but this fails to download automatically.
