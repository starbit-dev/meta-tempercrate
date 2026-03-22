python do_patch:append() {
    from pathlib import Path

    s = Path(d.getVar("S"))

    # 1) Inject RAUC env entries in config_distro_bootcmd.h
    p1 = s / "include" / "config_distro_bootcmd.h"
    text1 = p1.read_text()
    lines1 = text1.splitlines(keepends=True)

    if 'rauc_select=' not in text1:
        insert_block = [
            '\t"rauc_slot_a_part=8\\0" \\\n',
            '\t"rauc_slot_b_part=a\\0" \\\n',
            '\t"rauc_root=PARTLABEL=rootfs-a\\0" \\\n',
            '\t"rauc_root_a=PARTLABEL=rootfs-a\\0" \\\n',
            '\t"rauc_root_b=PARTLABEL=rootfs-b\\0" \\\n',
            '\t"rauc_default_left=1\\0" \\\n',
            '\t"rauc_boot=test -n \\\"${rauc_root}\\\" || setenv rauc_root ${rauc_root_a}; echo RAUC boot ${rauc_slot} from mmc ${devnum}:${distro_bootpart}; sysboot mmc ${devnum}:${distro_bootpart} any ${scriptaddr} /extlinux/extlinux.conf\\0" \\\n',
            '\t"rauc_init=setenv devnum ${boot_instance}; test -n \\\"${BOOT_ORDER}\\\" || setenv BOOT_ORDER \\\"A B\\\"; test -n \\\"${BOOT_A_LEFT}\\\" || setenv BOOT_A_LEFT ${rauc_default_left}; test -n \\\"${BOOT_B_LEFT}\\\" || setenv BOOT_B_LEFT ${rauc_default_left}; test -n \\\"${rauc_root}\\\" || setenv rauc_root ${rauc_root_a}\\0" \\\n',
            '\t"rauc_try_A=if test ${BOOT_A_LEFT} -gt 0; then setexpr BOOT_A_LEFT ${BOOT_A_LEFT} - 1; setenv distro_bootpart ${rauc_slot_a_part}; setenv rauc_slot A; setenv rauc_root ${rauc_root_a}; saveenv; run rauc_boot; fi\\0" \\\n',
            '\t"rauc_try_B=if test ${BOOT_B_LEFT} -gt 0; then setexpr BOOT_B_LEFT ${BOOT_B_LEFT} - 1; setenv distro_bootpart ${rauc_slot_b_part}; setenv rauc_slot B; setenv rauc_root ${rauc_root_b}; saveenv; run rauc_boot; fi\\0" \\\n',
            '\t"rauc_select=run rauc_init; for slot in ${BOOT_ORDER}; do if test \\\"${slot}\\\" = \\\"A\\\"; then run rauc_try_A; fi; if test \\\"${slot}\\\" = \\\"B\\\"; then run rauc_try_B; fi; done; echo RAUC: no bootable slot left; false\\0" \\\n',
        ]

        out1 = []
        inserted1 = False
        for line in lines1:
            out1.append(line)
            if 'boot_syslinux_conf=extlinux/extlinux.conf\\0' in line and not inserted1:
                out1.extend(insert_block)
                inserted1 = True

        if not inserted1:
            raise Exception("boot_syslinux_conf line not found in include/config_distro_bootcmd.h")

        p1.write_text(''.join(out1))

    # 2) Prepend run rauc_select to the ST STM32MP13 boot command
    p2 = s / "include" / "configs" / "stm32mp13_st_common.h"
    text2 = p2.read_text()

    old = '#define ST_STM32MP13_BOOTCMD "bootcmd_stm32mp=" \\\n\t"echo \\\"Boot over ${boot_device}${boot_instance}!\\\";" \\\n'
    new = '#define ST_STM32MP13_BOOTCMD "bootcmd_stm32mp=" \\\n\t"run rauc_select; " \\\n\t"echo \\\"Boot over ${boot_device}${boot_instance}!\\\";" \\\n'

    if 'run rauc_select; ' not in text2:
        if old not in text2:
            raise Exception("ST_STM32MP13_BOOTCMD anchor not found in include/configs/stm32mp13_st_common.h")
        text2 = text2.replace(old, new, 1)
        p2.write_text(text2)
}
