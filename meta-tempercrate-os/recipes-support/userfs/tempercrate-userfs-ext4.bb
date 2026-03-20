SUMMARY = "Empty ext4 filesystem for userfs"
DESCRIPTION = "Generates an empty ext4 filesystem image for the userfs partition"
LICENSE = "MIT"

inherit deploy

DEPENDS += "e2fsprogs-native"

USERFS_SIZE_MB ?= "1"
USERFS_LABEL ?= "userfs"
USERFS_IMAGE_NAME ?= "tempercrate-userfs.ext4"

do_compile:prepend() {
    rm -rf ${WORKDIR}/empty-root
    mkdir -p ${WORKDIR}/empty-root
}

do_compile() {
    rm -f ${WORKDIR}/${USERFS_IMAGE_NAME}
    truncate -s ${USERFS_SIZE_MB}M ${WORKDIR}/${USERFS_IMAGE_NAME}
    ${RECIPE_SYSROOT_NATIVE}/sbin/mkfs.ext4 -F -L ${USERFS_LABEL} -d ${WORKDIR}/empty-root ${WORKDIR}/${USERFS_IMAGE_NAME}
}

do_install[noexec] = "1"

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${WORKDIR}/${USERFS_IMAGE_NAME} ${DEPLOYDIR}/${USERFS_IMAGE_NAME}
}

addtask deploy after do_compile