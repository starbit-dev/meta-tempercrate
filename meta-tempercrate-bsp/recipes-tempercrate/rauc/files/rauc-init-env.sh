#!/bin/sh
set -eu

if ! command -v fw_printenv >/dev/null 2>&1; then
    exit 0
fi

if ! command -v fw_setenv >/dev/null 2>&1; then
    exit 0
fi

boot_order="$(fw_printenv -n BOOT_ORDER 2>/dev/null || true)"
boot_a_left="$(fw_printenv -n BOOT_A_LEFT 2>/dev/null || true)"
boot_b_left="$(fw_printenv -n BOOT_B_LEFT 2>/dev/null || true)"

[ -n "$boot_order" ] || fw_setenv BOOT_ORDER "A B"
[ -n "$boot_a_left" ] || fw_setenv BOOT_A_LEFT 3
[ -n "$boot_b_left" ] || fw_setenv BOOT_B_LEFT 3

exit 0
