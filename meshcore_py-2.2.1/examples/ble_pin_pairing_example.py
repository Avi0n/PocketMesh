#!/usr/bin/env python3
"""
Example: BLE PIN Pairing with MeshCore

This example demonstrates how to connect to a MeshCore device using BLE
with PIN-based pairing for enhanced security.
"""

import asyncio
import argparse
from meshcore import MeshCore


async def main():
    parser = argparse.ArgumentParser(description="Connect to MeshCore device with BLE PIN pairing")
    parser.add_argument("-a", "--addr", help="BLE address of the device (optional, will scan if not provided)")
    parser.add_argument("-p", "--pin", help="PIN for BLE pairing (optional)")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    
    args = parser.parse_args()
    
    try:
        print("Connecting to MeshCore device...")
        if args.pin:
            print(f"Using PIN for pairing: {args.pin}")
        
        # Create BLE connection with optional PIN
        meshcore = await MeshCore.create_ble(
            address=args.addr,
            pin=args.pin,
            debug=args.debug
        )
        
        print("✅ Connected successfully!")
        
        # Get device information to verify connection
        result = await meshcore.commands.send_device_query()
        if result.payload:
            print(f"Device model: {result.payload.get('model', 'Unknown')}")
            print(f"Firmware version: {result.payload.get('fw_version', 'Unknown')}")
        
        # Get device self-info
        result = await meshcore.commands.send_appstart()
        if result.payload:
            print(f"Device public key: {result.payload.get('public_key', 'Unknown')[:16]}...")
        
        print("\nConnection test completed successfully!")
        
    except ConnectionError as e:
        print(f"❌ Failed to connect: {e}")
        return 1
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1
    finally:
        if 'meshcore' in locals():
            await meshcore.disconnect()
            print("Disconnected from device")
    
    return 0


if __name__ == "__main__":
    import sys
    try:
        sys.exit(asyncio.run(main()))
    except KeyboardInterrupt:
        print("\nInterrupted by user")
        sys.exit(1)