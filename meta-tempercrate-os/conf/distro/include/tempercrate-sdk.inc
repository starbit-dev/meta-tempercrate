# TemperCrate SDK content (target sysroot)
#TOOLCHAIN_TARGET_TASK:append = " paho-mqtt-c-dev paho-mqtt-cpp-dev networkmanager-dev"
#TOOLCHAIN_TARGET_TASK:append = " glib-2.0-dev"
#TOOLCHAIN_TARGET_TASK:append = " dbus-dev"
#TOOLCHAIN_TARGET_TASK:append = " boost-dev"
#TOOLCHAIN_TARGET_TASK:append = " libmodbus-dev"




# ================================
# TemperCrate SDK – Target sysroot content
# ================================

# GPIO
TOOLCHAIN_TARGET_TASK:append = " libgpiod-dev"

# OpenSSL / TLS
TOOLCHAIN_TARGET_TASK:append = " openssl-dev"

# Boost (headers + C++ components)
TOOLCHAIN_TARGET_TASK:append = " boost-dev"

# D-Bus
TOOLCHAIN_TARGET_TASK:append = " dbus-dev"

# GLib / GObject
TOOLCHAIN_TARGET_TASK:append = " glib-2.0-dev"

# Bluetooth (BlueZ)
TOOLCHAIN_TARGET_TASK:append = " bluez5-dev"

# SQLite
TOOLCHAIN_TARGET_TASK:append = " libsqlite3-dev"
#TOOLCHAIN_TARGET_TASK:append = " sqlite3"

# MQTT (Paho)
TOOLCHAIN_TARGET_TASK:append = " paho-mqtt-c-dev"
TOOLCHAIN_TARGET_TASK:append = " paho-mqtt-cpp-dev"

# Modbus
TOOLCHAIN_TARGET_TASK:append = " libmodbus-dev"

# Avahi (mDNS / Zeroconf client)
TOOLCHAIN_TARGET_TASK:append = " avahi-dev"

# NetworkManager (libnm)
TOOLCHAIN_TARGET_TASK:append = " networkmanager-dev"

# ModemManager (libmm-glib)
TOOLCHAIN_TARGET_TASK:append = " modemmanager-dev"

# FT4222 vendor library
TOOLCHAIN_TARGET_TASK:append = " ft4222-dev"

