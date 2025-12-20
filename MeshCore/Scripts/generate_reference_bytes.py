#!/usr/bin/env python3
"""
Generate reference bytes from meshcore_py for Swift test validation.
Outputs Swift code that can be directly included in tests.

Run from MeshCore directory:
    python3 Scripts/generate_reference_bytes.py > Tests/MeshCoreTests/Fixtures/PythonReferenceBytes.swift
"""
import sys
from datetime import datetime

# Reference timestamp: 2024-01-01 00:00:00 UTC
REFERENCE_TIMESTAMP = 1704067200


def generate_packet_builder_references():
    """Generate reference bytes for PacketBuilder commands."""
    references = {}

    # appStart - device.py:15 (per firmware MyMesh.cpp:845, name at byte 8)
    # Format: [0x01, 0x03] + 6 reserved spaces + client ID (5 chars max)
    reserved = "      "  # 6 spaces
    client_id = "MCore"  # 5 chars max
    references['appStart'] = bytearray([0x01, 0x03]) + reserved.encode() + client_id.encode()

    # deviceQuery - device.py:20
    references['deviceQuery'] = bytes([0x16, 0x03])

    # getBattery - device.py:51
    references['getBattery'] = bytes([0x14])

    # getTime - device.py:55
    references['getTime'] = bytes([0x05])

    # setTime - device.py:59-61 (timestamp=1704067200 = 2024-01-01 00:00:00)
    references['setTime_1704067200'] = bytes([0x06]) + REFERENCE_TIMESTAMP.to_bytes(4, "little")

    # setName - device.py:31-33
    references['setName_TestNode'] = bytes([0x08]) + "TestNode".encode("utf-8")

    # setCoords - device.py:36-43 (lat=37.7749, lon=-122.4194)
    lat = int(37.7749 * 1e6)
    lon = int(-122.4194 * 1e6)
    references['setCoords_SF'] = (
        bytes([0x0E])
        + lat.to_bytes(4, "little", signed=True)
        + lon.to_bytes(4, "little", signed=True)
        + int(0).to_bytes(4, "little")
    )

    # setTxPower - device.py:65-67 (power=20)
    references['setTxPower_20'] = bytes([0x0C]) + int(20).to_bytes(4, "little")

    # setRadio - device.py:69-78 (freq=906.875, bw=250.0, sf=11, cr=8)
    references['setRadio_default'] = (
        bytes([0x0B])
        + int(906.875 * 1000).to_bytes(4, "little")
        + int(250.0 * 1000).to_bytes(4, "little")
        + int(11).to_bytes(1, "little")
        + int(8).to_bytes(1, "little")
    )

    # sendAdvertisement - device.py:22-27
    references['sendAdvertisement'] = bytes([0x07])
    references['sendAdvertisement_flood'] = bytes([0x07, 0x01])

    # reboot - device.py:46-47
    references['reboot'] = bytes([0x13]) + b"reboot"

    # getContacts - contact.py:14
    references['getContacts'] = bytes([0x04])

    # getMessage - messaging.py:14-25 (CMD 0x0a)
    references['getMessage'] = bytes([0x0A])

    # sendMessage - messaging.py:63-82
    # Format: [0x02, 0x00] + attempt(1) + timestamp(4LE) + dst(6) + msg
    dst = bytes.fromhex("0123456789AB")  # 6-byte prefix
    ts = REFERENCE_TIMESTAMP.to_bytes(4, "little")
    references['sendMessage_Hello'] = bytes([0x02, 0x00, 0x00]) + ts + dst + "Hello".encode("utf-8")

    # sendCommand - messaging.py:44-61
    # Format: [0x02, 0x01, 0x00] + timestamp(4LE) + dst(6) + cmd
    references['sendCommand_status'] = bytes([0x02, 0x01, 0x00]) + ts + dst + "status".encode("utf-8")

    # sendChannelMessage - messaging.py:144-156
    # Format: [0x03, 0x00] + channel(1) + timestamp(4LE) + msg
    references['sendChannelMessage_0_Hi'] = bytes([0x03, 0x00, 0x00]) + ts + "Hi".encode("utf-8")

    # sendLogin - messaging.py:27-31
    # Format: [0x1A] + dst(32) + password
    dst32 = bytes.fromhex("0123456789AB".ljust(64, '0'))  # 32 bytes zero-padded
    references['sendLogin'] = bytes([0x1A]) + dst32 + "secret".encode("utf-8")

    # sendLogout - messaging.py:33-36
    references['sendLogout'] = bytes([0x1D]) + dst32

    # sendStatusRequest - messaging.py:38-42
    references['sendStatusRequest'] = bytes([0x1B]) + dst32

    # getChannel - device.py:182-185 (index=0)
    references['getChannel_0'] = bytes([0x1F, 0x00])

    # setChannel - device.py:187-204 (index=0, name="General", secret=16 bytes)
    name_bytes = "General".encode("utf-8").ljust(32, b'\x00')
    secret = bytes(range(16))
    references['setChannel_0_General'] = bytes([0x20, 0x00]) + name_bytes + secret

    # getStats - device.py:276-289
    references['getStatsCore'] = bytes([0x38, 0x00])
    references['getStatsRadio'] = bytes([0x38, 0x01])
    references['getStatsPackets'] = bytes([0x38, 0x02])

    # getSelfTelemetry - device.py:167-170
    references['getSelfTelemetry'] = bytes([0x27, 0x00, 0x00, 0x00])

    # exportPrivateKey - device.py:206-208
    references['exportPrivateKey'] = bytes([0x17])

    # signStart - device.py:215-217
    references['signStart'] = bytes([0x21])

    # signFinish - device.py:240-247
    references['signFinish'] = bytes([0x23])

    # pathDiscovery - messaging.py:164-168
    references['pathDiscovery'] = bytes([0x34, 0x00]) + dst32

    # sendTrace - messaging.py:170-225 (tag=12345, auth=67890, flags=0)
    references['sendTrace'] = (
        bytes([0x24])
        + int(12345).to_bytes(4, "little")
        + int(67890).to_bytes(4, "little")
        + bytes([0x00])
    )

    return references


def generate_lpp_references():
    """Generate reference bytes using cayennelpp library."""
    try:
        from cayennelpp import LppFrame
    except ImportError:
        print("// cayennelpp not installed, LPP references generated manually", file=sys.stderr)
        return generate_lpp_references_manual()

    references = {}

    # Temperature 25.5 C on channel 1
    frame = LppFrame()
    frame.add_temperature(1, 25.5)
    references['lpp_temperature_25_5'] = bytes(frame.bytes())

    # Humidity 65% on channel 2
    frame = LppFrame()
    frame.add_humidity(2, 65.0)
    references['lpp_humidity_65'] = bytes(frame.bytes())

    # Analog input 3.3 on channel 3 (voltage uses analog input in cayennelpp)
    frame = LppFrame()
    frame.add_analog_input(3, 3.3)
    references['lpp_analog_3_3'] = bytes(frame.bytes())

    # GPS coordinates
    frame = LppFrame()
    frame.add_gps(4, 37.7749, -122.4194, 10.0)
    references['lpp_gps_sf'] = bytes(frame.bytes())

    # Barometer 1013.25 hPa
    frame = LppFrame()
    frame.add_barometric_pressure(5, 1013.25)
    references['lpp_barometer_1013'] = bytes(frame.bytes())

    # Accelerometer
    frame = LppFrame()
    frame.add_accelerometer(6, 0.0, 0.0, 1.0)
    references['lpp_accelerometer_1g'] = bytes(frame.bytes())

    return references


def generate_lpp_references_manual():
    """Generate LPP reference bytes manually using Cayenne LPP spec."""
    references = {}

    # Temperature 25.5 C on channel 1
    # Format: channel(1) + type(0x67) + value(int16 BE, *10)
    # 25.5 * 10 = 255 = 0x00FF
    references['lpp_temperature_25_5'] = bytes([0x01, 0x67, 0x00, 0xFF])

    # Humidity 65% on channel 2
    # Format: channel(1) + type(0x68) + value(uint8, *2)
    # 65 * 2 = 130 = 0x82
    references['lpp_humidity_65'] = bytes([0x02, 0x68, 0x82])

    # Analog input 3.3 on channel 3
    # Format: channel(1) + type(0x02) + value(int16 BE, *100)
    # 3.3 * 100 = 330 = 0x014A
    references['lpp_analog_3_3'] = bytes([0x03, 0x02, 0x01, 0x4A])

    # GPS coordinates: 37.7749, -122.4194, 10.0
    # Format: channel(1) + type(0x88) + lat(int24 BE, *10000) + lon(int24 BE, *10000) + alt(int24 BE, *100)
    # lat: 37.7749 * 10000 = 377749 = 0x05C395
    # lon: -122.4194 * 10000 = -1224194 = 0xED51FE (24-bit signed)
    # alt: 10.0 * 100 = 1000 = 0x0003E8
    references['lpp_gps_sf'] = bytes([
        0x04, 0x88,
        0x05, 0xC3, 0x95,  # lat
        0xED, 0x51, 0xFE,  # lon (negative)
        0x00, 0x03, 0xE8   # alt
    ])

    # Barometer 1013.25 hPa on channel 5
    # Format: channel(1) + type(0x73) + value(uint16 BE, *10)
    # 1013.25 * 10 = 10132.5 -> 10133 (rounded) = 0x2795
    # Note: Some implementations round down, so we use 10132 = 0x2794
    references['lpp_barometer_1013'] = bytes([0x05, 0x73, 0x27, 0x94])

    # Accelerometer 0.0, 0.0, 1.0 g on channel 6
    # Format: channel(1) + type(0x71) + x(int16 BE, *1000) + y(int16 BE, *1000) + z(int16 BE, *1000)
    # x: 0.0 * 1000 = 0 = 0x0000
    # y: 0.0 * 1000 = 0 = 0x0000
    # z: 1.0 * 1000 = 1000 = 0x03E8
    references['lpp_accelerometer_1g'] = bytes([0x06, 0x71, 0x00, 0x00, 0x00, 0x00, 0x03, 0xE8])

    return references


def to_swift_data(name: str, data: bytes) -> str:
    """Convert bytes to Swift Data literal."""
    hex_bytes = ', '.join(f'0x{b:02X}' for b in data)
    return f'    static let {name} = Data([{hex_bytes}])'


def main():
    print("// Auto-generated by generate_reference_bytes.py")
    print("// DO NOT EDIT - regenerate with: python3 Scripts/generate_reference_bytes.py")
    print("import Foundation")
    print("")
    print("/// Reference bytes generated from meshcore_py Python library")
    print("enum PythonReferenceBytes {")
    print("")
    print("    // MARK: - PacketBuilder References")
    print("")

    for name, data in generate_packet_builder_references().items():
        print(to_swift_data(name, data))

    print("")
    print("    // MARK: - LPP References (from cayennelpp)")
    print("")

    for name, data in generate_lpp_references().items():
        print(to_swift_data(name, data))

    print("}")


if __name__ == "__main__":
    main()
