python () {
    if d.getVar("TEMPERCRATE_SB_ENABLE") != "1":
        bb.warn("TemperCrate Secure Boot is disabled: TF-A and FIP will be built without authentication.")
}