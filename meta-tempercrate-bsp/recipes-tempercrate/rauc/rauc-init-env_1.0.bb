SUMMARY = "Initialize RAUC U-Boot environment variables on first boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://rauc-init-env.sh \
    file://rauc-init-env.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "rauc-init-env.service"
SYSTEMD_AUTO_ENABLE = "enable"

RDEPENDS:${PN} = "u-boot-fw-utils"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/rauc-init-env.sh ${D}${bindir}/rauc-init-env.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/rauc-init-env.service ${D}${systemd_system_unitdir}/rauc-init-env.service
}