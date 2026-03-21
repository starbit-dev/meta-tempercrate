# TODO: /datafs must be created on a separate partition independent from the OS
SUMMARY = "TemperCrate application configuration"
DESCRIPTION = "Installs /datafs/config/config.json into the image"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://config.json"

S = "${WORKDIR}"

do_install() {
    # Create /datafs/config in the target rootfs
    install -d ${D}/datafs/config

    # Install the config file
    install -m 0644 ${WORKDIR}/config.json ${D}/datafs/config/config.json
}

FILES:${PN} += "/datafs/config/config.json /datafs/config"
