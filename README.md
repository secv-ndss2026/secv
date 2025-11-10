# Artifact for NDSS2026 SECV: Securing Connected Vehicles with Hardware Trust Anchors.

This is the open-source for the SECV: Securing Connected Vehicles with Hardware Trust Anchors, NDSS 2026 Fall paper.
Here, we will provide code modifications for the core parts of the paper and the instructions on building SECV for S32G3.
We provide code patches showing the major changes made to help reduce the time of search time. The major components here are the **Linux Kernel (NW OS)**, **OPTEE-OS (Trusted OS)**, **drivers (NW & SW components)**, and **Arm Trusted Firmware (The Security Monitor)**. This open-source is based on **Linux Kernel 6.6.52**, **OPTEE-OS V4.0**, and **Arm Trusted Firmware 2.10.7**. This implementation has been tested on NXP S32G3, but we are making an effort to provide a porting for **Raspberry Pi 4** with an SPI driver. Except for secure peripheral handling in ATF and OPTEE where implementations are specific to S32G3, we believe the provided patches apply universally regardless of the board, except where mentioned specifically.

## Caution and Disclaimer:

This is only a prototype and is not production-ready. We only provide a proof of concept for the research conducted, as presented in the paper.
Additionally, especially for S32G3, some of the required firmware requires Licenses, and thus, we are not permitted to distribute them. But one may obtain most of the needed firmware with a free account on NXP.

## Architecture

```bash
.
├── GoldVIP-S32G3-1.13.0-User-Manual.pdf
├── LICENSE
├── patches
│   ├── arm-trusted-firmware
│   │   └── secv-secure-monitor.patch
│   ├── linux
│   │   ├── secv-flexcan-drivers.patch
│   │   ├── secv-ima-auth.patch
│   │   └── secv-kernel-isolation.patch
│   └── optee-os
│       └── secv-trusted-os.patch
├── README.md
├── s32g3
|   ├── linux-s32
|   ├── optee_os
|   ├── arm-trusted-firmware
│   └── local.conf # in case of building with NXP's Yocto
└── scripts
    ├── candump.sh
    ├── canperf.sh
    ├── latency.py
    └── show_lmbench_result.sh
```

## Building the default S32G3 Image:

The image can be built with Yocto as follows, and at least one should have `repo` installed:

- **_Build Environment:_** Ubuntu 20.04
- **_Hardware Requirements:_** At least 16GB RAM, at least 4 CPU Cores, and 70GB or more disk space.

### Initial Setup and obtaining the baseline code-base

```sh
$ mkdir nxp-yocto-goldvip
$ cd nxp-yocto-golvip
$ repo init -b release/goldvip-1.13.0 -m default.xml -u https://github.com/nxp-auto-goldvip/gvip-manifests
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

During the build, the GoldVIP image requires `openjdk8`, but this fails to download automatically. As a workaround, we download the following packages using `wget` into the `downloads` folder.

```sh
https://mirrors.kernel.org/yocto-sources/openjdk-f89009ada191.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-corba-aarch64-shenandoah-jdk8u272-b10.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-corba-jdk8u272-ga.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-hotspot-aarch64-shenandoah-jdk8u272-b10.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-hotspot-jdk8u272-ga.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-jaxp-aarch64-shenandoah-jdk8u272-b10.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-jaxp-jdk8u272-ga.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-jaxws-aarch64-shenandoah-jdk8u272-b10.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-jaxws-jdk8u272-ga.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-jdk-aarch64-shenandoah-jdk8u272-b10.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-jdk-jdk8u272-ga.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-jdk8u-aarch64-shenandoah-jdk8u272-b10.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-jdk8u-jdk8u272-ga.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-langtools-aarch64-shenandoah-jdk8u272-b10.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-langtools-jdk8u272-ga.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-nashorn-aarch64-shenandoah-jdk8u272-b10.tar.bz2
https://mirrors.kernel.org/yocto-sources/openjdk8-272-nashorn-jdk8u272-ga.tar.bz2
```

After that, the default build should complete successfully.

#### SECV Baseline Building:

To build the SECV baseline, one needs to modify the `conf/local.conf` file to include more packages. It should suffice to replace the `local.conf` file with the one we provided in this repository. For this move the `local.conf` file provided under the `s32g3` directory of this repository into the `build/conf/local.conf` directory of your build environment.
After the image is built, one may find it at build/tmp/deploy/images/s32g3/....sdcard
This is the baseline image against which we compare SECV in terms of performance, communication latency and resource usage.
In our experiments, the EVN platform (running Linux and the built environment) is connected to the IVN gateway (the Cortex-M7 side of the board), via the CAN bus, as shown in the diagram below. This allows us to model a networked system, under which the EVN platform may be another board such as a Raspberry Pi or any other board capable of handling compute-heavy workloads.
We include scripts to reproduce the LMBench experiments, the communication performance, the system performance (LMBench), and the IVN gateway resource usage. The scripts are identifiable by their filenames.

#### Applying Patches and Building SECV:

To apply the patches, one needs to move them into the corresponding yocto layer. For example, for Linux, move the patches to the `sources/meta-gvip/recipes-kernel/linux/patches` directory of your yocto environment. Then modify the file at `sources/meta-gvip/recipes-kernel/linux/linux-s32_%.bbappend` to include the patches as follows:
To the file, add:

```sh
SRC_URI:append = "\
    file://patches/secv-kernel-isolation.patch \
    file://patches/secv-flexcan-drivers.patch \
    file://patches/secv-ima-auth.patch \
"
```

After that, one can rebuild the image again to enforce these changes by rerunning the build command:

```sh
bitbake fsl-image-goldvip
```

## Evaluation

#### System Performance

Run:

```sh
$lmbench-run
```

Then a prompt will appear asking for configuration input. For our experiment, use the default settings by **pressing Enter.** Where the `vi` screen opens, simply close it by pressing `:q<ENTER>`.
After 20~50 minutes, the result is stored at /usr/share/lmbench/results/. To enhance readability, we provide a script that presents the results in a well-organized manner.

```sh
$cd /usr/share/lmbench/results
$/home/root/scripts/show_lmbench_results.sh <result_file.0>
```

#### Communication Performance (Microbenchmarks)

Run:

```sh
$./scripts/canperf.sh -t can0 -r can1 -i 0 -o 4 -g 0 -s 8 -l 10
```
This command transmits CAN messages of ID 0 over CAN interface `can0` to the IVN gateway. The gateway acknowledges the messages and responds with CAN messages of ID 4. After it runs, it prints the results, including the throughput and the IVN gateway percentage load (`M7_0 core load`).
It also saves the timestamp differences of successive received messages in a file, `/tmp/candump.log`, which we use to compute the total latency. To measure the average latency, run the following command:
```sh
$python3 scripts/latency.py /tmp/candump.log
```
To reproduce the results in the SECV paper, you may repeat the experiment with (-g 1) to change the transmission gap to 1ms instead of 0ms, and (-s 16/32/64) for message sizes 16, 32, and 16.
#### Communication Performance (Real-World Workload)

Run:

```sh
$./scripts/canperf.sh -t can0 -r can1 --payload can_fd_message.log
$./scripts/canperf.sh -t can0 -r can1 --payload can_msg_day2.log
$./scripts/canperf.sh -t can0 -r can1 --payload can2_g1.log

```

This experiment employs the publicly available CAN message dataset released by [HCRL](https://ocslab.hksecurity.net/Datasets). Used dataset are already provisioned on our board


