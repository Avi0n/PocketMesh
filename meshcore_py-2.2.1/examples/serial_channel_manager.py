#!/usr/bin/env python3

import asyncio
import sys
from meshcore import MeshCore
from meshcore.events import EventType

# Default port - change as needed
PORT = "/dev/tty.usbserial-583A0069501"
BAUDRATE = 115200

async def main():
    # Check command line arguments
    if len(sys.argv) > 1:
        port = sys.argv[1]
    else:
        port = PORT
        
    print(f"Connecting to device on {port}...")
    
    try:
        mc = await MeshCore.create_serial(port, BAUDRATE, debug=True)
        print("Connected!")
        
        # Display device info
        print(f"Device: {mc.self_info.get('adv_name', 'Unknown')}")
        print(f"Public Key: {mc.self_info.get('public_key', 'Unknown')}")
        print()
        
        while True:
            print("Channel Manager")
            print("1. Get channel info")
            print("2. Set channel")
            print("3. Exit")
            choice = input("Enter choice (1-3): ")
            
            if choice == "1":
                await get_channel_info(mc)
            elif choice == "2":
                await set_channel_config(mc)
            elif choice == "3":
                break
            else:
                print("Invalid choice. Please try again.\n")
                
    except Exception as e:
        print(f"Error: {e}")
    finally:
        if 'mc' in locals():
            await mc.disconnect()
            print("Disconnected.")

async def get_channel_info(mc):
    """Get information about a specific channel"""
    try:
        channel_idx = int(input("Enter channel index (0-255): "))
        
        print(f"Getting info for channel {channel_idx}...")
        result = await mc.commands.get_channel(channel_idx)
        
        if result.type == EventType.CHANNEL_INFO:
            payload = result.payload
            print(f"Channel {payload.get('channel_idx', 'Unknown')}:")
            print(f"  Name: {payload.get('channel_name', 'Unknown')}")
            print(f"  Secret: {payload.get('channel_secret', b'').hex()}")
        elif result.type == EventType.ERROR:
            print(f"Error getting channel info: {result.payload}")
        else:
            print(f"Unexpected response: {result.type}")
            
    except ValueError:
        print("Invalid channel index. Please enter a number.")
    except Exception as e:
        print(f"Error: {e}")
    print()

async def set_channel_config(mc):
    """Configure a channel with name and secret"""
    try:
        channel_idx = int(input("Enter channel index (0-255): "))
        channel_name = input("Enter channel name (max 32 chars): ")
        
        # Get secret as hex string
        print("Enter channel secret as hex (32 hex chars for 16 bytes):")
        print("Example: 0123456789abcdef0123456789abcdef")
        secret_hex = input("Secret: ").strip()
        
        # Validate and convert secret
        if len(secret_hex) != 32:
            print("Error: Secret must be exactly 32 hex characters (16 bytes)")
            return
            
        try:
            channel_secret = bytes.fromhex(secret_hex)
        except ValueError:
            print("Error: Invalid hex string")
            return
            
        print(f"Setting channel {channel_idx}...")
        result = await mc.commands.set_channel(channel_idx, channel_name, channel_secret)
        
        if result.type == EventType.OK:
            print("Channel configured successfully!")
        elif result.type == EventType.ERROR:
            print(f"Error setting channel: {result.payload}")
        else:
            print(f"Unexpected response: {result.type}")
            
    except ValueError:
        print("Invalid input. Please enter valid numbers.")
    except Exception as e:
        print(f"Error: {e}")
    print()

if __name__ == "__main__":
    asyncio.run(main())
