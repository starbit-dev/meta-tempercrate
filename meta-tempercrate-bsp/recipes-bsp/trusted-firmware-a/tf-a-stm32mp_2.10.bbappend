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
            bb.fatal("TEMPERCRATE Secure Boot variable missing in tf-a-stm32mp: %s" % v)

        if v != "TEMPERCRATE_SB_SIGN_KEY_PASS" and not os.path.exists(value):
            bb.fatal("TEMPERCRATE Secure Boot file not found in tf-a-stm32mp: %s=%s" % (v, value))

    if d.getVar("TEMPERCRATE_SB_VERBOSE_TFA") == "1":
        d.setVar("ST_TF_A_LOG_LEVEL_RELEASE", "40")
    else:
        d.setVar("ST_TF_A_LOG_LEVEL_RELEASE", "20")
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
        bb.fatal("TEMPERCRATE Secure Boot enabled, but required TF-A values are missing: %s" % ", ".join(missing))

    extra = []
    for name, value in secure_boot_vars:
        extra.append('%s="%s"' % (name, value))

    d.appendVar("EXTRA_OEMAKE", " " + " ".join(extra))
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