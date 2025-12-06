#!/usr/bin/env python3
"""
Example: BLE Private Key Export with MeshCore

This example demonstrates how to export the private key from a MeshCore device
using BLE with PIN-based pairing for enhanced security.

Note: This feature requires:
1. A MeshCore device running companion radio firmware
2. ENABLE_PRIVATE_KEY_EXPORT=1 compile-time flag enabled
3. Authenticated BLE connection with PIN
"""

import asyncio
import argparse
from meshcore import MeshCore
from meshcore.events import EventType


async def main():
    parser = argparse.ArgumentParser(description="Export private key from MeshCore device via BLE")
    parser.add_argument("-a", "--addr", help="BLE address of the device (optional, will scan if not provided)")
    parser.add_argument("-p", "--pin", help="PIN for BLE pairing (required for private key export)")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    
    args = parser.parse_args()
    
    if not args.pin:
        print("❌ PIN is required for private key export. Use -p or --pin to specify it.")
        return 1
    
    try:
        print("Connecting to MeshCore device...")
        print(f"Using PIN for pairing: {args.pin}")
        
        # Create BLE connection with PIN (required for private key export)
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
            print(f"Firmware version: {result.payload.get('fw ver', 'Unknown')}")
        
        # Export private key
        print("\n🔑 Requesting private key export...")
        result = await meshcore.commands.export_private_key()
        
        if result.type == EventType.PRIVATE_KEY:
            private_key = result.payload["private_key"]
            print("✅ Private key exported successfully!")
            print(f"Private key (64 bytes): {private_key.hex()}")
            print(f"Private key length: {len(private_key)} bytes")
            
            # Optionally save to file
            save_to_file = input("\nSave private key to file? (y/N): ").lower().strip()
            if save_to_file == 'y':
                filename = input("Enter filename (default: private_key.bin): ").strip()
                if not filename:
                    filename = "private_key.bin"
                
                with open(filename, 'wb') as f:
                    f.write(private_key)
                print(f"Private key saved to {filename}")
                
        elif result.type == EventType.DISABLED:
            print("❌ Private key export is disabled on this device")
            print("This feature requires:")
            print("  - Companion radio firmware")
            print("  - ENABLE_PRIVATE_KEY_EXPORT=1 compile-time flag")
            
        elif result.type == EventType.ERROR:
            print(f"❌ Error exporting private key: {result.payload}")
            
        else:
            print(f"❌ Unexpected response: {result.type}")
        
        print("\nPrivate key export test completed!")
        
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
    sys.exit(asyncio.run(main()))
