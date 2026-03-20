FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://create_st_fip_binary_tempercrate.sh \
    file://check_fip_cot_keys.sh \
"

LIC_FILES_CHKSUM:append = " file://${WORKDIR}/create_st_fip_binary_tempercrate.sh;beginline=1;endline=7;md5=4f71019041e152e4db4799abd4eb2612"

python () {
    if d.getVar("TEMPERCRATE_SB_ENABLE") != "1":
        return

    import os

    required = [
        "TEMPERCRATE_SB_SIGN_TOOL",
        "TEMPERCRATE_SB_SIGN_KEY_PASS",
        "TEMPERCRATE_SB_SIGN_KEY",
        "TEMPERCRATE_SB_ROOT_KEY",
        "TEMPERCRATE_SB_TRUSTED_WORLD_KEY",
        "TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY",
        "TEMPERCRATE_SB_TOS_FW_KEY",
        "TEMPERCRATE_SB_NT_FW_KEY",
        "TEMPERCRATE_SB_SOC_FW_KEY",
        "TEMPERCRATE_SB_SCP_FW_KEY",
    ]

    for v in required:
        value = d.getVar(v) or ""
        if not value:
            bb.fatal("TEMPERCRATE Secure Boot variable missing in fip-stm32mp: %s" % v)

        if v != "TEMPERCRATE_SB_SIGN_KEY_PASS" and not os.path.exists(value):
            bb.fatal("TEMPERCRATE Secure Boot file not found in fip-stm32mp: %s=%s" % (v, value))
}

SIGN_ENABLE = "${@'1' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else '0'}"

SIGN_TOOL = "${@d.getVar('TEMPERCRATE_SB_SIGN_TOOL') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"
SIGN_KEY = "${@d.getVar('TEMPERCRATE_SB_SIGN_KEY') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"
SIGN_KEY:stm32mp13 = "${SIGN_KEY}"
SIGN_KEY_stm32mp13 = "${SIGN_KEY}"
SIGN_KEY_PASS = "${@d.getVar('TEMPERCRATE_SB_SIGN_KEY_PASS') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"

TRUSTED_BOARD_BOOT = "${@'1' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else '0'}"
GENERATE_COT = "${@'1' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else '0'}"
CREATE_KEYS = "${@'0' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"
SAVE_KEYS = "${@'0' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"

ROT_KEY = "${@d.getVar('TEMPERCRATE_SB_ROOT_KEY') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"
TRUSTED_WORLD_KEY = "${@d.getVar('TEMPERCRATE_SB_TRUSTED_WORLD_KEY') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"
NON_TRUSTED_WORLD_KEY = "${@d.getVar('TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"
BL31_KEY = "${@d.getVar('TEMPERCRATE_SB_SOC_FW_KEY') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"
BL32_KEY = "${@d.getVar('TEMPERCRATE_SB_TOS_FW_KEY') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"
BL33_KEY = "${@d.getVar('TEMPERCRATE_SB_NT_FW_KEY') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"
SCP_BL2_KEY = "${@d.getVar('TEMPERCRATE_SB_SCP_FW_KEY') or '' if d.getVar('TEMPERCRATE_SB_ENABLE') == '1' else ''}"

python __anonymous() {
    if d.getVar("TEMPERCRATE_SB_ENABLE") != "1":
        return

    secure_boot_vars = [
        ("GENERATE_COT", "1"),
        ("CREATE_KEYS", "0"),
        ("SAVE_KEYS", "0"),
        ("ROT_KEY", d.getVar("TEMPERCRATE_SB_ROOT_KEY")),
        ("TRUSTED_WORLD_KEY", d.getVar("TEMPERCRATE_SB_TRUSTED_WORLD_KEY")),
        ("NON_TRUSTED_WORLD_KEY", d.getVar("TEMPERCRATE_SB_NON_TRUSTED_WORLD_KEY")),
        ("BL31_KEY", d.getVar("TEMPERCRATE_SB_SOC_FW_KEY")),
        ("BL32_KEY", d.getVar("TEMPERCRATE_SB_TOS_FW_KEY")),
        ("BL33_KEY", d.getVar("TEMPERCRATE_SB_NT_FW_KEY")),
        ("SCP_BL2_KEY", d.getVar("TEMPERCRATE_SB_SCP_FW_KEY")),
    ]

    missing = [name for name, value in secure_boot_vars if value in (None, "")]
    if missing:
        bb.fatal("TEMPERCRATE Secure Boot enabled, but required FIP values are missing: %s" % ", ".join(missing))

    extra = []
    for name, value in secure_boot_vars:
        extra.append('%s="%s"' % (name, value))

    d.appendVar("EXTRA_OEMAKE", " " + " ".join(extra))
}

do_deploy:prepend() {
    install -d ${RECIPE_SYSROOT_NATIVE}${bindir_native}
    install -m 0755 ${WORKDIR}/create_st_fip_binary_tempercrate.sh \
        ${RECIPE_SYSROOT_NATIVE}${bindir_native}/create_st_fip_binary.sh
}

do_deploy:append() {
    if [ "${TEMPERCRATE_SB_ENABLE}" != "1" ]; then
        bbnote "TEMPERCRATE Secure Boot disabled: skipping TF-A CoT embedded key verification"
        exit 0
    fi

    bbnote "Running TF-A CoT embedded key verification"

    export DEBUG_CHECK_FIP="0"
    export CHECK_FIP_DIR="${T}/checkfip"
    export CHECK_FIP_FILE="$(find ${WORKDIR}/deploy-fip-stm32mp/fip -maxdepth 1 -type f -name '*-sdcard_Signed.bin' | head -n1)"

    if [ -z "${CHECK_FIP_FILE}" ]; then
        bbfatal "Unable to locate runtime signed FIP in ${WORKDIR}/deploy-fip-stm32mp/fip"
    fi

    if [ -z "${SECURE_BOOT_CONFIG_PATH}" ]; then
        bbfatal "SECURE_BOOT_CONFIG_PATH is not available in the task environment"
    fi

    bbnote "Checking FIP: ${CHECK_FIP_FILE}"
    bbnote "Using SECURE_BOOT_CONFIG_PATH=${SECURE_BOOT_CONFIG_PATH}"

    cd ${TOPDIR}

    bash ${WORKDIR}/check_fip_cot_keys.sh
    rc=$?

    if [ $rc -eq 0 ]; then
        bbplain "TF-A CoT embedded key verification PASSED"
    else
        bbfatal "TF-A CoT embedded key verification FAILED"
    fi
}

export SIGN_ENABLE
export SIGN_TOOL
export SIGN_KEY
export SIGN_KEY_PASS
export TRUSTED_BOARD_BOOT
export GENERATE_COT
export CREATE_KEYS
export SAVE_KEYS
export ROT_KEY
export TRUSTED_WORLD_KEY
export NON_TRUSTED_WORLD_KEY
export BL31_KEY
export BL32_KEY
export BL33_KEY
export SCP_BL2_KEY