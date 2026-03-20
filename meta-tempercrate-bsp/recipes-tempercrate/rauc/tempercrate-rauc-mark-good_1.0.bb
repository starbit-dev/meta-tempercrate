SUMMARY = "Automatically mark current RAUC slot as good after successful boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://tempercrate-rauc-mark-good.sh \
    file://tempercrate-rauc-mark-good.service \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "tempercrate-rauc-mark-good.service"
SYSTEMD_AUTO_ENABLE = "enable"

RDEPENDS:${PN} = "rauc"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/tempercrate-rauc-mark-good.sh ${D}${bindir}/tempercrate-rauc-mark-good.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/tempercrate-rauc-mark-good.service ${D}${systemd_system_unitdir}/tempercrate-rauc-mark-good.service
}