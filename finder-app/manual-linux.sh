#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.15.163
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

OUTDIR=/tmp/aeld

if [ $# -lt 1 ]
then
	echo "Using default directory ${OUTDIR} for output"
else
	OUTDIR=$1
	echo "Using passed directory ${OUTDIR} for output"
fi

mkdir -p ${OUTDIR}
if [ $? != 0 ]; then echo "ERROR"; exit; fi

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # TODO: Add your kernel build steps here
    make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} mrproper
    if [ $? != 0 ]; then echo "ERROR"; exit; fi

    make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} defconfig
    if [ $? != 0 ]; then echo "ERROR"; exit; fi

    make -j4 ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} all
    if [ $? != 0 ]; then echo "ERROR"; exit; fi

    make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} modules
    if [ $? != 0 ]; then echo "ERROR"; exit; fi

    make ARCH=arm64 CROSS_COMPILE=${CROSS_COMPILE} dtbs
    if [ $? != 0 ]; then echo "ERROR"; exit; fi
fi

cp -r "${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image" "${OUTDIR}"

echo "Adding the Image in outdir"

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# TODO: Create necessary base directories

mkdir rootfs
if [ $? != 0 ]; then echo "ERROR"; exit; fi

cd rootfs

mkdir -p bin dev etc home  lib lib64 proc sbin sys tmp usr var
if [ $? != 0 ]; then echo "ERROR"; exit; fi

mkdir -p usr/bin usr/lib usr/sbin
if [ $? != 0 ]; then echo "ERROR"; exit; fi

mkdir -p var/log
if [ $? != 0 ]; then echo "ERROR"; exit; fi



cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    # TODO:  Configure busybox
    make distclean
    if [ $? != 0 ]; then echo "ERROR"; exit; fi

    make defconfig
    if [ $? != 0 ]; then echo "ERROR"; exit; fi
else
    cd busybox
fi

# TODO: Make and install busybox
make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}
if [ $? != 0 ]; then echo "ERROR"; exit; fi

make ARCH=${ARCH} CROSS_COMPILE=${CROSS_COMPILE}  CONFIG_PREFIX="${OUTDIR}/rootfs" install
if [ $? != 0 ]; then echo "ERROR"; exit; fi


# TODO: Add library dependencies to rootfs

echo "Library dependencies"

SYSROOT_PATH=$(${CROSS_COMPILE}gcc -print-sysroot)

PROGRAM_INTERPRETER=$(${CROSS_COMPILE}readelf -l "${OUTDIR}/rootfs/bin/busybox"|   sed -n 's/.*Requesting program interpreter: \(.*\)/\1/p' | xargs basename | tr -d '[]')

echo ${PROGRAM_INTERPRETER}

PROGRAM_INTERPRETER_PATH=$(find "${SYSROOT_PATH}" -name "${PROGRAM_INTERPRETER}")

echo ${PROGRAM_INTERPRETER_PATH}

cp "$PROGRAM_INTERPRETER_PATH" "${OUTDIR}/rootfs/lib/"

mapfile -t SHARED_LIBRARIES < <(${CROSS_COMPILE}readelf -d "${OUTDIR}/rootfs/bin/busybox"| awk '/NEEDED/ {print $5}' | tr -d '[]')

echo 

# Loop through each library in SHARED_LIBRARIES
for lib in "${SHARED_LIBRARIES[@]}"; do
    echo "Searching for $lib in $SYSROOT_PATH..."
    
    # Find the library in SYSROOT_PATH
    lib_path=$(find "$SYSROOT_PATH" -name "$lib" | head -n 1)
    
    # Check if the library was found
    if [[ -n "$lib_path" ]]; then
        echo "Found $lib at $lib_path"
        
        # Copy the library to the output directory
        cp "$lib_path" "$OUTDIR/rootfs/lib64/"
        echo "Copied $lib to $OUTDIR/rootfs/lib64/"
    else
        echo "Library $lib not found in $SYSROOT_PATH!"
    fi
done

# TODO: Make device nodes
cd "${OUTDIR}/rootfs"

sudo mknod -m 666 dev/null c 1 3
sudo mknod -m 600 dev/console c 5 1


# TODO: Clean and build the writer utility
cd "$FINDER_APP_DIR"
make clean 
make CROSS_COMPILE=${CROSS_COMPILE} 

# TODO: Copy the finder related scripts and executables to the /home directory
# on the target rootfs
cp writer "${OUTDIR}/rootfs/home/"

cp finder.sh "${OUTDIR}/rootfs/home/"
mkdir -p "${OUTDIR}/rootfs/home/conf"
cp conf/username.txt "${OUTDIR}/rootfs/home/conf/"
cp conf/assignment.txt "${OUTDIR}/rootfs/home/conf/"
cp finder-test.sh "${OUTDIR}/rootfs/home/"

cp autorun-qemu.sh "${OUTDIR}/rootfs/home/"

# TODO: Chown the root directory
cd "${OUTDIR}/rootfs"

sudo chown -R root:root *
# TODO: Create initramfs.cpio.gz

find  . | cpio  -H newc -ov --owner root:root > "${OUTDIR}/initramfs.cpio"

cd "${OUTDIR}"

gzip -f initramfs.cpio