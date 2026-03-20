SUMMARY = "TemperCrate EVSE runtime packages"
DESCRIPTION = "Common runtime package set for TemperCrate EVSE application stack"
LICENSE = "MIT"

# Force arch-specific packagegroup (needed with package_deb due to dynamic renames)
ALLARCH_PACKAGEGROUP = "0"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit packagegroup

RDEPENDS:${PN} = " \
    networkmanager \
    dbus \
    tempercrate-dbus-policy \
    glib-2.0 \
    libmodbus \
    libavahi-client \
    libavahi-common \
    avahi-daemon \
    sqlite3 \
    openssl \
    paho-mqtt-c \
    paho-mqtt-cpp \
    ft4222 \
    libgpiod \
    libstdc++ \
    libgcc \
    mosquitto \
    mosquitto-clients \
    open-plc-utils \
    hostapd \
    app-mount \
    rauc \
    rauc-init-env \
    tempercrate-rauc-mark-good \
"
