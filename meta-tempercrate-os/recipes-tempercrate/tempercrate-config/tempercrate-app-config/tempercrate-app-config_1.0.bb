# TODO: /app must be created on a separete partition independent from the OS
SUMMARY = "TemperCrate application configuration"
DESCRIPTION = "Installs /app/config/config.json into the image"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://config.json"

S = "${WORKDIR}"

do_install() {
    # Create /app/config in the target rootfs
    install -d ${D}/app/config

    # Install the config file
    install -m 0644 ${WORKDIR}/config.json ${D}/app/config/config.json
}

FILES:${PN} += "/app/config/config.json /app/config"
