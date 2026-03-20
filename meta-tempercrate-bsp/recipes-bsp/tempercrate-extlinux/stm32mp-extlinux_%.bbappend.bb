SUMMARY = "TemperCrate machine-specific extlinux.conf (single entry, no menu timeout)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Allow file:// lookups from this recipe's files/ directory
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = ""

# Fetch the correct extlinux.conf per machine.
# BitBake will place it under ${WORKDIR}/<subdir>/extlinux.conf (subdir preserved).
SRC_URI:append:stm32mp13-tempercrate-dev  = " file://stm32mp13-tempercrate-dev/extlinux.conf"
SRC_URI:append:stm32mp13-tempercrate-prod = " file://stm32mp13-tempercrate-prod/extlinux.conf"

S = "${WORKDIR}"

do_install() {
    # Create destination directory in the target rootfs
    install -d ${D}/boot/extlinux
}

# Install the machine-specific configuration file
do_install:append:stm32mp13-tempercrate-dev() {
    install -m 0644 ${WORKDIR}/stm32mp13-tempercrate-dev/extlinux.conf ${D}/boot/extlinux/extlinux.conf
}

do_install:append:stm32mp13-tempercrate-prod() {
    install -m 0644 ${WORKDIR}/stm32mp13-tempercrate-prod/extlinux.conf ${D}/boot/extlinux/extlinux.conf
}

FILES:${PN} += "/boot/extlinux/extlinux.conf"

