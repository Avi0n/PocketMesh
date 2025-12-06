#!/usr/bin/env python3
"""
Example demonstrating the new pub-sub system in MeshCore
Shows how to subscribe to events and use the event system
"""
import asyncio
import argparse

from meshcore import MeshCore
from meshcore.events import EventType


async def message_callback(event):
    print(f"\nReceived message: {event.payload['text']}")
    print(f"From: {event.payload.get('pubkey_prefix', 'channel')}")
    print(f"Type: {event.payload['type']}")
    print(f"Timestamp: {event.payload['sender_timestamp']}")


async def advertisement_callback(event):
    print("\nDetected advertisement")


async def main():
    parser = argparse.ArgumentParser(description="MeshCore Pub-Sub Example")
    parser.add_argument(
        "--port", "-p", help="Serial port", required=True
    )
    parser.add_argument(
        "--baud", "-b", type=int, help="Baud rate", default=115200
    )
    args = parser.parse_args()

    print(f"Connecting to {args.port} at {args.baud} baud...")
    
    # Create MeshCore instance with serial connection
    meshcore = await MeshCore.create_serial(args.port, args.baud, debug=True)
    
    # Connection is already established
    success = True
    if not success:
        print("Failed to connect to MeshCore device")
        return
        
    print("Connected to MeshCore device")
    
    res = await meshcore.commands.send_device_query()

    # Get contacts
    result = await meshcore.commands.get_contacts()
    if result.type == EventType.ERROR:
        print(f"Error fetching contacts: {result.payload}")
        return
    contacts = result.payload
    if contacts:
        print(f"\nFound {len(contacts)} contacts:")
        for name, contact in contacts.items():
            print(f"- {name}")
            
    
    await meshcore.commands.send_advert(flood=True)
    
    # Subscribe to private messages
    private_subscription = meshcore.subscribe(EventType.CONTACT_MSG_RECV, message_callback)
    
    # Subscribe to channel messages
    channel_subscription = meshcore.subscribe(EventType.CHANNEL_MSG_RECV, message_callback)
    
    # Subscribe to advertisements
    advert_subscription = meshcore.subscribe(EventType.ADVERTISEMENT, advertisement_callback)
    
    await meshcore.start_auto_message_fetching()
    
    print("\nSubscribed to events:")
    print("- Private messages")
    print("- Channel messages")
    print("- Advertisements")
    
    print("\nWaiting for events. Press Ctrl+C to exit...\n")
    
    # Get device info
    device_info = await meshcore.commands.send_device_query()
    if device_info:
        print(f"Device info: {device_info}")
        
    # Get time from the device
    device_time = await meshcore.commands.get_time()
    print(f"Device time: {device_time}")
    
    # Access current time through the property
    print(f"Current time (property): {meshcore.time}")
    
    try:
        while True:
            # Wait for messages
            await asyncio.sleep(1)
    except KeyboardInterrupt:
        meshcore.stop()
        print("\nExiting...")
    except asyncio.CancelledError:
        # Handle task cancellation from KeyboardInterrupt in asyncio.run()
        print("\nTask cancelled - cleaning up...")
    finally:
        # Clean up subscriptions
        meshcore.unsubscribe(private_subscription)
        meshcore.unsubscribe(channel_subscription)
        meshcore.unsubscribe(advert_subscription)
        
        # Stop auto-message fetching
        await meshcore.stop_auto_message_fetching()
        
        # Disconnect
        await meshcore.disconnect()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        # This prevents the KeyboardInterrupt traceback from being shown
        print("\nExited cleanly")
    except Exception as e:
        print(f"Error: {e}")
